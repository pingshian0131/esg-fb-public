---
name: facebook-page-setup
description: One-time setup reference for Facebook Page publishing via Meta Graph API. Covers Meta App creation, OAuth scopes (pages_show_list / pages_read_engagement / pages_manage_posts / publish_video), short-lived to long-lived User Access Token exchange, Page Access Token refresh via /me/accounts, appsecret_proof HMAC formula, privacy policy and terms of service templates for Meta review, and Live Mode prerequisites. Use this skill when the user is configuring credentials, troubleshooting token / permission / app-review issues, preparing privacy policy or ToS URLs, or migrating an app from Development Mode to Live Mode. Triggers include「設定 FB 粉專」、「申請 Meta App」、「token 過期」、「申請 publish_video 權限」、「privacy policy 範本」、「app live mode」、「appsecret_proof」、「permission denied」. DOES NOT publish posts — for actual posting use the facebook-page-post skill.
version: 1.2.0
author: Hermes Agent
license: MIT
platforms: [macos, linux, windows]
metadata:
  hermes:
    tags: [facebook, meta, graph-api, pages, setup, oauth, token, privacy-policy]
---

# Facebook Page Setup (Meta App / OAuth / Tokens / Privacy Policy)

> **這是設定用的 skill。** 設定完成後若要實際發文，請改用 [`facebook-page-post`](../facebook-page-post/) skill。

當使用者要**設定** Facebook 粉專發文流程時使用這個 skill，包括：建立 Meta App、授予 OAuth 權限、交換 token、計算 `appsecret_proof`、準備供 Meta 審查用的 privacy policy / terms of service，或是把 app 切換到 Live Mode。日常發文則由 [`facebook-page-post`](../facebook-page-post/) 負責。

## 使用者預設工作流程

針對這位使用者，請優先採用安全的審核流程：

1. 在可行的情況下，直接接收使用者從目前平台上傳的影片或媒體檔。
2. 若使用者需要文案協助，幫忙草擬繁體中文的貼文文案與 hashtag。
3. 除非使用者明確表示要立即發佈，否則在發佈前先秀出最終文案和目標 Page 的名稱／ID。
4. 不要要求使用者把機密資訊貼到對話裡。改用 `~/.hermes/.env`，或引導使用者在本機自行編輯。
5. 絕對不要印出 access token、app secret，或任何含有 token 的完整 API 回應。

## 必要的 Meta 資產

把以下內容存到 `~/.hermes/.env`：

```env
FB_APP_ID=...
FB_APP_SECRET=...
FB_PAGE_ID=...
FB_LONG_LIVED_USER_TOKEN=...
FB_PAGE_ACCESS_TOKEN=...
FB_GRAPH_VERSION=v25.0
```

說明：

- `FB_PAGE_ID` 對同一個 Page 而言是固定的。
- `FB_APP_ID` 對同一個 Meta app 而言是固定的。
- `FB_APP_SECRET` 在未重設前是固定的。
- access token 可能會輪替或過期。long-lived User Access Token 通常 60 天後過期。
- `appsecret_proof` 是根據每個 token 推導出來的，應該在呼叫當下計算，不要存起來。
- `FB_GRAPH_VERSION` — 當 Meta 淘汰舊版時，更新成當前的 Graph API 版本（請查閱 [Meta API Changelog](https://developers.facebook.com/docs/graph-api/changelog)）。

## 權限

要發文到粉專，user token 通常需要：

- `pages_show_list`
- `pages_read_engagement`
- `pages_manage_posts`

視流程需要，可能會用到的額外權限：

- `business_management`（若有用到 Business Manager／資產時）

用以下方式驗證 token 權限：

```bash
GET /me/permissions
```

只有 `pages_show_list`、`business_management`、`public_profile` 的 token 可以列出 Page，但不足以讀取 Page 資料或發文。

## Meta app Live Mode 前置條件

當你要把 Meta app 從 Development Mode 切到 Live Mode 以進行粉專發文時，Meta 可能會要求提供以下公開 URL：

- Privacy Policy URL（通常為必填）
- Terms of Service URL（有時必填，強烈建議提供）

這些**不需要**自架伺服器。任何 Meta 審查人員能開啟、且不需登入的公開 URL 都可以，例如 Google Sites、GitHub Pages、Carrd/Wix/WordPress，或使用者自己的網站。對於輕量的個人粉專發文自動化 app，建議用 Google Sites 或 GitHub Pages 並包含：

- 一個簡短的首頁，說明這個 app 是什麼、用途為何；
- `/privacy-policy`，說明 Facebook 資料的使用方式、Page ID／token、上傳的媒體／貼文內容、保留／刪除的聯絡方式，以及不販售個人資料；
- `/terms-of-service`，說明可接受的使用方式、上傳內容的權利歸屬、遵守 Meta 政策、服務可用性免責聲明，以及終止／刪除條款。

可用 `templates/meta-privacy-policy.md` 和 `templates/meta-terms-of-service.md` 作為初始範本。為了 Meta 審查請以英文為主，下方可選擇性附上繁體中文供使用者的受眾閱讀。

## appsecret_proof

如果 Meta app 開啟了 **Require app secret proof for server API calls**，那麼每一次伺服器端的 Graph API 呼叫都必須帶上 `appsecret_proof`。

公式：

```text
appsecret_proof = HMAC-SHA256(key=app_secret, msg=access_token)
```

Python:

```python
import hmac, hashlib

proof = hmac.new(
    key=app_secret.encode("utf-8"),
    msg=access_token.encode("utf-8"),
    digestmod=hashlib.sha256,
).hexdigest()
```

重要：請用該次 API 呼叫實際使用的那個 token 來計算 proof。User token 和 Page token 算出來的 proof 是不同的。

## 快速設定腳本（建議）

這個 skill 內附 `scripts/setup.py`，可端到端自動完成設定中關於 token 的那一半：它會把 short-lived User token 換成 long-lived token、計算 `appsecret_proof`、透過 `/me/accounts` 取得對應的 Page Access Token，並把所有內容寫入 `~/.hermes/.env`（`facebook-page-post` 讀取的就是同一個路徑）。

前置條件（需在 Meta 手動完成，詳見下方各節）：一個 Meta App（`FB_APP_ID` / `FB_APP_SECRET`）、目標 `FB_PAGE_ID`，以及一個從 Graph API Explorer 取得、帶有 `pages_show_list`、`pages_read_engagement`、`pages_manage_posts` 的 short-lived User token。

請在這個 skill 的目錄底下執行（以下指令假設你人在 `.../facebook-page-setup/` 裡）：

```bash
cd <path-to>/.claude/skills/facebook-page-setup

# Interactive — prompts for any missing APP_ID / APP_SECRET / PAGE_ID / short-lived token
python3 scripts/setup.py

# Non-interactive — pass the short-lived token directly (other values read from ~/.hermes/.env)
python3 scripts/setup.py --token "$SHORT_LIVED_USER_TOKEN"

# Check existing tokens — prints type, validity, and days remaining via /debug_token
python3 scripts/setup.py --check
```

這個腳本可以安全地重複執行：它會把結果**合併**進 `~/.hermes/.env`（既有的 key 會保留，只更新 token 相關欄位），以 `600` 權限寫入檔案，而且絕不會印出完整的 token 值（只會印出遮罩後的 `abcd...wxyz`）。注意：合併時，既有 `.env` 裡的註解行不會被保留，但所有 `KEY=value` 項目都會保留。取得 token 後，它還會檢查已授予的 scope，若缺少任何必要權限就會發出警告。

請定期執行 `--check`：long-lived User token 約 60 天後過期，遇到 `OAuthException` code `190` 時，只要重跑上面的流程刷新即可。

下方的手動 `curl` 流程是備援方案，也是腳本在背後實際動作的參考說明。

## 取得 Page Access Token

建議的正式環境做法：

1. 在 Graph API Explorer 產生一個帶有必要權限的 short-lived User Access Token。
2. 把它換成 long-lived User Access Token：

```bash
curl "https://graph.facebook.com/$FB_GRAPH_VERSION/oauth/access_token?grant_type=fb_exchange_token&client_id=$FB_APP_ID&client_secret=$FB_APP_SECRET&fb_exchange_token=$SHORT_LIVED_USER_TOKEN"
```

3. 用 long-lived User token 查詢 Pages：

```bash
curl "https://graph.facebook.com/$FB_GRAPH_VERSION/me/accounts?access_token=$FB_LONG_LIVED_USER_TOKEN&appsecret_proof=$USER_TOKEN_PROOF"
```

4. 挑出符合 `FB_PAGE_ID` 的 Page，把它的 `access_token` 存成 `FB_PAGE_ACCESS_TOKEN`。

如果 Graph API Explorer 顯示：

```text
Page access tokens cannot be generated: API calls from the server require an appsecret_proof argument
```

那就採取以下其中一種做法：

- 在產生 token 期間，暫時關閉 app 的「Require app secret proof for server API calls」設定，產完後在正式環境再重新開啟；或
- 如上所述，手動帶上 `appsecret_proof` 來產生／呼叫。

## 安全驗證檢查

發文前，先在不實際發佈的情況下驗證：

1. 從 `~/.hermes/.env` 載入環境變數。
2. 為 `FB_LONG_LIVED_USER_TOKEN` 計算 proof。
3. 呼叫 `/me/permissions`，確認必要權限都已授予。
4. 呼叫 `/me/accounts`，確認目標 Page 有列在裡面，且 `tasks` 中含有 `CREATE_CONTENT`。
5. 為 `FB_PAGE_ACCESS_TOKEN` 計算 proof。
6. 可選擇用 Page token 搭配 `fields=id,name` 查詢 Page metadata，但要注意 Meta 可能會要求 `pages_read_engagement`。

切勿在 log 或最終回應中顯示 token 的值。

## 發佈純文字貼文

```bash
curl -X POST "https://graph.facebook.com/$FB_GRAPH_VERSION/$FB_PAGE_ID/feed" \
  -F "message=貼文文案" \
  -F "access_token=$FB_PAGE_ACCESS_TOKEN" \
  -F "appsecret_proof=$PAGE_TOKEN_PROOF"
```

## 發佈相片

```bash
curl -X POST "https://graph.facebook.com/$FB_GRAPH_VERSION/$FB_PAGE_ID/photos" \
  -F "source=@/absolute/path/to/image.jpg" \
  -F "message=貼文文案" \
  -F "access_token=$FB_PAGE_ACCESS_TOKEN" \
  -F "appsecret_proof=$PAGE_TOKEN_PROOF"
```

成功時，Meta 會回傳 `{ "id": "...", "post_id": "..." }`。

## 發佈影片

```bash
curl -X POST "https://graph.facebook.com/$FB_GRAPH_VERSION/$FB_PAGE_ID/videos" \
  -F "source=@/absolute/path/to/video.mp4" \
  -F "description=貼文文案" \
  -F "access_token=$FB_PAGE_ACCESS_TOKEN" \
  -F "appsecret_proof=$PAGE_TOKEN_PROOF"
```

成功時，Meta 會回傳一個含有 video/post ID 的物件。若權限允許，可透過抓取該物件或 Page feed 來驗證。

對於大型檔案（大於 1 GB，或在慢速連線下上傳），請改用 [Resumable Video Upload API](https://developers.facebook.com/docs/video-api/guides/reels-publishing)，把上傳切成多個 chunk，避免逾時失敗。

## 發佈排程貼文

若要排程貼文於未來發佈，請設定 `published=false`，並在 `scheduled_publish_time` 提供一個 Unix timestamp。時間必須落在現在的 10 分鐘到 30 天之間。

```bash
# Compute Unix timestamp (e.g. publish in 2 hours)
PUBLISH_AT=$(date -v+2H +%s)   # macOS
# PUBLISH_AT=$(date -d "+2 hours" +%s)  # Linux

curl -X POST "https://graph.facebook.com/$FB_GRAPH_VERSION/$FB_PAGE_ID/feed" \
  -F "message=貼文文案" \
  -F "published=false" \
  -F "scheduled_publish_time=$PUBLISH_AT" \
  -F "access_token=$FB_PAGE_ACCESS_TOKEN" \
  -F "appsecret_proof=$PAGE_TOKEN_PROOF"
```

排程貼文需要 `pages_manage_posts` 權限。它們會出現在 Page 的 Publishing Tools 裡，並可在正式發佈前取消。

## 疑難排解

- `Object does not exist... requires pages_read_engagement`：token 缺少 `pages_read_engagement`，或 app 不具備所需的 access／review 狀態。
- `/me/accounts` 可以用，但 Page metadata／發文失敗：Page token 可能衍生自一個權限不足的 user token。請用必要的 scope 重新產生 user token，再重新取得 Page token。
- 透過 Graph API 建立的貼文，Page／admin 帳號看得到，但第二個一般 Facebook 帳號看不到：懷疑是 app 處於 Development Mode／權限未通過審核／app 尚未 Live，尤其當兩篇測試貼文都有相同的可見性問題時更是如此。可把第二個帳號加為 app Tester 來驗證；如果這樣它就看得到貼文，那就在產生正式 token 前，把 app 切到 Live Mode 並完成必要的審查／商業設定。
- Page token 在 `/me/permissions` 上有 `pages_read_engagement`，但 `/{page-id}/feed` 仍回傳 `(#10) requires pages_read_engagement or Page Public Content Access`：這應視為 app 的 access／review 狀態問題，而不只是 token 打錯。請檢查 app 模式、權限的存取層級，以及 Page Public Content Access／App Review 的相關要求。
- 在 Graph Explorer 裡每次 token 都不一樣：short-lived token 本來就會這樣。請改用 long-lived User token，並從它刷新 Page token。
- token 改變時 `appsecret_proof` 也跟著改變：這是正常的，因為它是由 token + app secret 推導而來。
- Error code `190` / `OAuthException`：User Access Token 已過期（long-lived token 通常維持 60 天）。請重跑「取得 Page Access Token」中的 short-lived → long-lived 交換流程，再重新取得 Page Access Token 並更新 `~/.hermes/.env`。

## 機密資訊衛生

如果使用者把 App Secret 或 Access Token 貼到對話裡，請建議他到 Meta Developers 輪替／重設該機密，並把新的機密存到 `~/.hermes/.env`，而不是放在對話中。

另請參閱：`references/meta-pages-token-flow.md`，裡面有從一次實際設定過程整理出的簡潔 token／權限流程與錯誤判讀。
