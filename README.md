# esg-fb · Facebook 粉專發文 AI Agent Skills

一組 [Claude Code](https://claude.com/claude-code) / hermes agent 用的 skill，協助設定並透過 Meta Graph API 發文到 Facebook 粉專，另含照片轉影片的 slideshow 工具。

## 內含 skills

| Skill | 用途 |
|-------|------|
| [`facebook-page-setup`](.claude/skills/facebook-page-setup/) | 一次性設定：建立 Meta App、OAuth 權限、token 交換、privacy policy / ToS 範本、Live Mode |
| [`facebook-page-post`](.claude/skills/facebook-page-post/) | 設定完成後，發佈文字 / 相片 / 影片 / 排程貼文到粉專 |
| [`photo-slideshow-video`](.claude/skills/photo-slideshow-video/) | 把照片或短片組成 slideshow 影片（Ken Burns、字幕、配樂） |

文件以繁體中文為主，專有名詞（API、權限名、欄位名）保留原文。

## 快速開始：設定 token

`facebook-page-setup` 內附 `scripts/setup.py`，自動完成 token 交換並寫入 `~/.hermes/.env`。

### 前置動作（在 Meta 後台手動完成）

1. 在 [Meta for Developers](https://developers.facebook.com/) 建立 App，記下 `App ID` / `App Secret`
2. 將你的 FB 帳號設成該 App 的 Tester 或 Admin
3. 確認你的 FB 帳號是目標粉專的管理員
4. 到 [Graph API Explorer](https://developers.facebook.com/tools/explorer/) 抓一張 Short-Lived User Token
   - 選擇剛建立的 App
   - 勾權限：`pages_show_list`、`pages_read_engagement`、`pages_manage_posts`

> 詳細視覺化流程請開 `fb-app-setup.html`。

### 執行 setup.py

```bash
cd .claude/skills/facebook-page-setup

# 互動模式（推薦）
python3 scripts/setup.py

# 非互動模式（直接帶 short-lived token）
python3 scripts/setup.py --token "<short_lived_token>"

# 檢查現有 token 的類型與剩餘有效期
python3 scripts/setup.py --check
```

腳本會把結果**合併**進 `~/.hermes/.env`（保留既有其他 key，不覆蓋整檔），以 `600` 權限寫入，且不會印出完整 token 值。

## .env 內容

寫入 `~/.hermes/.env`，由 `facebook-page-post` 與 hermes agent 讀取。

| 欄位 | 來源 | 有效期 |
|------|------|--------|
| `FB_APP_ID` | Meta 後台 → App 設定 | 永久 |
| `FB_APP_SECRET` | Meta 後台 → App 設定 | 永久（可 reset） |
| `FB_PAGE_ID` | FB 粉專 → 關於 → 粉專編號 | 永久 |
| `FB_LONG_LIVED_USER_TOKEN` | `setup.py` 自動換取 | ~60 天 |
| `FB_PAGE_ACCESS_TOKEN` | `setup.py` 自動換取 | 不過期（配合 long-lived user token 取得時） |
| `FB_GRAPH_VERSION` | 預設 `v25.0` | — |

## Token 過期了怎麼辦

Long-lived User token 約 60 天過期，遇到 `OAuthException` code `190` 時，重新抓一張 short-lived token 再跑一次 `scripts/setup.py` 即可。可用 `--check` 隨時查看剩餘天數。

## 檔案結構

```
.
├── .claude/skills/
│   ├── facebook-page-setup/    # 設定 skill（含 scripts/setup.py、privacy policy / ToS 範本）
│   ├── facebook-page-post/     # 發文 skill
│   └── photo-slideshow-video/  # slideshow 影片 skill
├── .env.example                # .env 範本
├── .gitignore
├── README.md
└── fb-app-setup.html           # FB App 設定完整視覺化流程
```

## 安全注意

- `.env` 已列入 `.gitignore`，**禁止** commit 進 repo
- `FB_APP_SECRET` 是高權限機密，外洩要立刻到 Meta 後台 reset
- 本 repo 的所有範例值皆為佔位符，不含任何真實憑證
