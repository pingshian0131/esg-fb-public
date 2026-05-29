---
name: facebook-page-post
description: Publish content (text, photo, image, video, scheduled post) to an already-configured Facebook Page via Meta Graph API. Runs `scripts/facebook_page_publish.py`, reads credentials from `~/.hermes/.env` (or `--dotenv <path>`), auto-selects feed/photos/videos endpoint by media type, supports resumable upload for large videos, and reports only safe identifiers (no tokens). Use this skill whenever the user wants to actually send a post — local media path, attached file, caption text, or scheduled timestamp. Triggers include「發到 FB」、「幫我發粉專」、「把這個影片加文案發出去」、「排程發文」、「test 發一篇」、「publish to facebook」. ASSUMES setup is already done — if tokens are missing / expired, the app is still in Development Mode, or permissions are not granted, use the facebook-page-setup skill first.
license: MIT
metadata:
  hermes:
    tags: [facebook, meta, graph-api, social-media, page-posting, video, photo, scheduling]
---

# Facebook Page Post (Publish to a Configured Page)

> **這是日常發文用的 skill。** 如果你還沒設定好 Meta App、OAuth scopes、token 或隱私權政策，請先執行 [`facebook-page-setup`](../facebook-page-setup/)。

這個 skill 透過 Meta Graph API 把內容發佈到使用者的 Facebook Page。支援：

- 純文字的 Page 貼文
- 相片／圖片貼文
- 影片貼文
- 使用者自訂的文案／說明文字
- 當使用者要求產生文案、或完全沒提供文案時，由 agent 自動產生
- 本機媒體路徑，以及透過聊天上傳、已存到硬碟的媒體檔

憑證會從 dotenv 檔讀取。預設位置是 `~/.hermes/.env`；可用 `--dotenv <path>` 覆寫指向其他位置（例如 `~/.config/facebook-page-post/.env`）。

## 必要的環境變數

把 skill 目錄裡的 `.env.example` 複製到你選定的 dotenv 路徑，並填入：

```env
FB_APP_ID=...
FB_APP_SECRET=...
FB_PAGE_ID=...
FB_PAGE_ACCESS_TOKEN=...
FB_LONG_LIVED_USER_TOKEN=...
# Optional
FB_GRAPH_VERSION=v25.0
FB_RESUMABLE_THRESHOLD=104857600   # 100 MB; videos >= this size use resumable upload
FB_RESUMABLE_CHUNK=8388608         # 8 MB per chunk
```

`FB_APP_SECRET` 用來計算 `appsecret_proof`。不要在聊天或 log 中印出 token 或 secret。如果某個指令的輸出含有 token 值，請以「有／缺」的方式摘要它們，不要直接揭露內容。

### 必要的 OAuth scopes

當你產生 `FB_LONG_LIVED_USER_TOKEN` 時（透過 Graph API Explorer 或你自己的 OAuth 流程），至少要授予下列權限：

- `pages_show_list` — 列出使用者管理的 Pages（呼叫 `/me/accounts` 時需要）
- `pages_read_engagement` — 讀取 Page metadata
- `pages_manage_posts` — 在 Page 上建立文字／相片貼文
- `publish_video` — 發佈 Page 影片

Graph API Explorer 給的 short-lived token 約 1 小時就會過期；請換成 long-lived user token（約 60 天），再從 `/me/accounts` 重新取得 Page token（見 Workflow §3）。

## 安全政策

發佈到 Facebook 是一種對外的副作用（side effect）。

- 如果使用者明確要求現在發出去，例如「發出去」「發布」「先發佈一則 test」，就直接執行，不用再問一次。
- 如果使用者只是要求打草稿、準備、預覽，或講得很模糊，就不要發佈；提供文案／預覽，並請對方給出明確的發佈指示。
- 產生文案時，語氣要貼合使用者的要求，以及他們記錄下來的個人偏好（例如寫在 CLAUDE.md）。不要預設某種固定風格。
- 如果使用者提供了確切的文案，就原樣保留。只有在使用者要求時才修正明顯的錯字。
- 不要發佈 secret、私人資料，或看起來並非有意要發的內容。

## 工作流程

### 1. 解析輸入

確認以下項目：

- 目標 Page：預設使用 `.env` 裡的 `FB_PAGE_ID`，除非使用者指名另一個已設定的 page。
- 媒體路徑：本機路徑、附加檔案，或純文字貼文時不帶任何媒體。
  - 如果使用者剛在同一個 session 產生了多種平台的輸出檔，請挑選符合 Facebook 版位的那一份：Page 動態時報貼文通常用已驗證的 4:5 feed 版本，而不是先前的 16:9 YouTube/TV 草稿版，除非使用者明確指定要那個版本。
- 文案：
  - 如果使用者提供了確切文案，就原樣使用。
  - 如果使用者要求一段介紹或文案，就產生一份。
  - 如果是在旅遊／影片流程後，使用者要求「簡單的文案」，預設用繁體中文寫得精簡：1～2 句溫暖的話，加上 3～5 個相關 hashtag。
  - 如果完全沒指定文案，就產生一段合適的短文案和 hashtag，但只有在使用者明確要求發佈時才發佈。
- 發佈模式：預設立即發佈。如果使用者要求排程，先確認 Graph API 支援該功能、也確認要求的時間無誤後，再使用 Graph API 的排程參數。

### 2. 上傳前先驗證媒體檔

對於本機媒體路徑，發文前先確認檔案存在並檢查基本 metadata：

```bash
python3 - <<'PY'
from pathlib import Path
p = Path('/path/to/media')
print({'exists': p.exists(), 'size': p.stat().st_size if p.exists() else None})
PY
```

影片的話，若有 `ffprobe` 可用，就用它來檢查長度和尺寸。如果要根據媒體內容產生文案，用 `ffmpeg` 擷取一張縮圖，再用 vision tool 檢視：

```bash
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,duration -of json /path/to/video.mp4
ffmpeg -y -ss 00:00:02 -i /path/to/video.mp4 -frames:v 1 /tmp/hermes_fb_thumb.jpg
```

### 3. 必要時刷新 Page token

如果 Page token 的呼叫出現權限或 token 錯誤，就用 `FB_LONG_LIVED_USER_TOKEN` 呼叫 `/me/accounts`，重新取得 `FB_PAGE_ID` 對應的 `FB_PAGE_ACCESS_TOKEN`。

務必帶上 `appsecret_proof`，並且要用該次請求實際使用的那個 token 來計算：

```python
import hmac, hashlib
proof = hmac.new(app_secret.encode(), access_token.encode(), hashlib.sha256).hexdigest()
```

### 4. 發佈

使用內附的腳本。先解析出 skill 目錄一次（不論這個 skill 是從 `~/.claude/skills/facebook-page-post`、本 repo、還是其他任何地方被呼叫，都能運作）：

```bash
SKILL_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"   # if running from a wrapper script
# or, if you already know the skill directory, set SKILL_DIR explicitly, e.g.
# SKILL_DIR="$HOME/.claude/skills/facebook-page-post"

python3 "$SKILL_DIR/scripts/facebook_page_publish.py" \
  --media /path/to/file.mp4 \
  --caption "caption text"
```

純文字：

```bash
python3 "$SKILL_DIR/scripts/facebook_page_publish.py" \
  --caption "Test 測試發文"
```

Dry run，在實際發文前很好用：

```bash
python3 "$SKILL_DIR/scripts/facebook_page_publish.py" \
  --media /path/to/file.mp4 \
  --caption "caption text" \
  --dry-run
```

腳本會依媒體類型選擇端點：

- 沒有媒體：`/{page_id}/feed`
- 圖片：`/{page_id}/photos`
- 影片：`/{page_id}/videos`
  - 影片 `< FB_RESUMABLE_THRESHOLD`（預設 100 MB）：單次 multipart 上傳
  - 影片 `>=` 門檻（或加上 `--force-resumable`）：使用 Meta Resumable Upload 協定（start → transfer → finish），從硬碟串流分塊上傳，讓大檔不會把記憶體吃光

### 5. 驗證並回報

發佈完成後，只回報安全的識別資訊和文案：

- Page 名稱（若已知）
- Post ID 或 Video ID／Photo ID
- 文案／說明文字
- API 回傳的任何警告

不要印出 access token、app secret 或 appsecret_proof。

## 文案撰寫指引

- 配合使用者的語言（未指定時用繁體中文）。
- 語氣貼合使用者的要求；不要預設某種特定風格。
- 如果使用者存有個人的文案偏好（例如寫在 CLAUDE.md 或某個 memory 檔），就照著做。
- 產生的文案要精簡：通常 2～4 個短段落，視情況可加 3～6 個 hashtag。
- 除非使用者明確要求那種風格，否則避免那種一聽就是 AI 寫的、很制式的推銷話術。

選用的參考風格（詩意的旅遊／自然範例）放在 [references/caption-styles.md](references/caption-styles.md)。只在使用者選擇採用該風格時才用。

## 疑難排解

- `API calls from the server require an appsecret_proof argument`：為所用的 token 計算並帶上 `appsecret_proof`。
- `requires pages_read_engagement`：重新產生／更新 user token 並授予 `pages_read_engagement`，再透過 `/me/accounts` 更新 Page token。
- 缺少 `pages_manage_posts`：重新產生帶有 `pages_manage_posts` 的 token，並更新 Page token。
- Graph API Explorer 的 token 每次都不一樣：這對 short-lived token 來說是正常的。請把 long-lived user token 和更新後的 page token 存進 `.env`。
- 如果直接用 Page token 讀取 `/{page_id}?fields=id,name` 失敗、但 `/me/accounts` 可以成功，就從 `/me/accounts` 更新 Page token 後再重試。
