# Telegram mixed-media travel video → Facebook handoff

這是從一次 Telegram 工作流擷取的 session 模式：使用者上傳多張照片與短影片，要求做旅遊 slideshow，接著要求發佈 Facebook 版本。

## Durable lessons

- 如果使用者在對話裡上傳很多圖片／影片，把 cache 的附件路徑當作第一順位的素材。除非驗證顯示有檔案遺失，否則不要叫他們重新上傳。
- 旅遊回憶的序列，一個不錯的敘事順序是：出發／飛機 → 抵達／城市 → 飯店／休息 → 移動 → 市場／美食 → 傍晚／夜晚收尾。
- 對 Facebook feed，要 render 一個獨立的 4:5 版本（`1080x1350`），而不是沿用 16:9 的 YouTube/TV 版本。用模糊／壓暗背景保留置中的主體，不要硬裁直式來源素材。
- 如果使用者要 Facebook 的「簡單文案」，預設保持簡短、溫暖、繁體中文：1–2 行短句加上幾個 hashtag。
- 做好 Facebook 用的版本後，當使用者明確要求發佈時（包含 slash 風格的說法，例如「發到 /facebook-page-post」），交接給 `facebook-page-post`。上傳前先驗證 media 是否存在與其 metadata。

## Example concise caption style

```text
首爾小旅行的一天。
從窗邊的雲，到城市的燈光，慢慢把這些片刻收進回憶裡。

#韓國旅行 #首爾 #旅行日記 #生活紀錄
```

## Verification checklist before posting

- `ffprobe` 確認預期的 Facebook feed 尺寸（`1080x1350`）、duration、video stream 與 audio stream。
- 抓一個 frame 確認 burn 上的繁體中文字幕清晰可讀。
- 使用 Facebook 專用的輸出檔，而非先前的 16:9 草稿，除非使用者明確要求那個版本。
