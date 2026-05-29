# Meta Pages Token Flow Notes

設定 Hermes 透過 Meta Graph API 發文到 Facebook 粉專的簡潔參考。

## 固定值 vs 會輪替的值

固定值：

- Page ID
- App ID
- App Secret（除非重設）
- Page name（除非改名）

會輪替／衍生的值：

- 來自 Graph API Explorer 的 short-lived User Access Token
- long-lived User Access Token，最終會過期
- Page Access Token，從不同的 user token 重新產生時可能會改變
- `appsecret_proof`，由實際使用的 access token 加上 App Secret 推導而來

## 必要的環境變數值

```env
FB_APP_ID=...
FB_APP_SECRET=...
FB_PAGE_ID=...
FB_LONG_LIVED_USER_TOKEN=...
FB_PAGE_ACCESS_TOKEN=...
```

不要把機密資訊貼到對話裡。請存放在 `~/.hermes/.env`。

## 發文流程中觀察到的必要權限

最低需要的目標權限：

- `pages_show_list`
- `pages_read_engagement`
- `pages_manage_posts`

如果 `/me/permissions` 只顯示 `pages_show_list`、`business_management`、`public_profile`，那麼列出 Page 可能可以運作，但讀取 Page／發文可能會失敗。

## appsecret_proof

當 Meta App 要求 App Secret Proof 時，請用該次 API 呼叫所使用的 token 來計算：

```python
import hmac, hashlib
proof = hmac.new(key=app_secret.encode(), msg=token.encode(), digestmod=hashlib.sha256).hexdigest()
```

`/me/permissions` 和 `/me/accounts` 使用 User token 的 proof；`/{page_id}/feed` 或 `/{page_id}/videos` 使用 Page token 的 proof。

## 常見錯誤

### `Page access tokens cannot be generated: API calls from the server require an appsecret_proof argument`

Graph API Explorer 可能在沒有提供 proof 的情況下嘗試產生 Page token。可選做法：

1. 暫時關閉「Require app secret proof for server API calls」，產生 token 後再重新開啟；或
2. 自行進行帶有 `appsecret_proof` 的手動 API 呼叫。

### `(#100) Object does not exist... requires pages_read_engagement`

token 沒有 `pages_read_engagement`，或 app／審查模式不允許所請求的 Page 存取。請用帶有 `pages_read_engagement` 和 `pages_manage_posts` 的設定重新產生 user token，再從 `/me/accounts` 重新取得 Page Access Token。

## 驗證流程

1. 載入 `~/.hermes/.env`，過程中不要印出機密資訊。
2. 為 `FB_LONG_LIVED_USER_TOKEN` 計算 proof。
3. 呼叫 `/me/permissions`，檢視已授予的 scope。
4. 呼叫 `/me/accounts`；以 `FB_PAGE_ID` 選出對應的 page；確認有 `CREATE_CONTENT` task。
5. 從選出的 Page 紀錄更新 `FB_PAGE_ACCESS_TOKEN`。
6. 為 Page token 計算 proof，若權限允許，執行一次不發文的 Page metadata 檢查。
7. 除非使用者明確要求立即發佈，否則一律在使用者確認後才發佈。
