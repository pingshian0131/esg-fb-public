# Social Aspect Ratios for Photo Slideshow Videos

## Core rule

在選輸出比例之前，先檢查照片尺寸。輸出比例越接近來源照片，需要的 crop 或 padding 就越少。

一次成功 session 的範例：

- 來源照片：`960x1280`，aspect `0.75` = 3:4 直式。
- 16:9 輸出：`1920x1080`，aspect `1.7778` = 若 full-bleed 會嚴重 crop。
- 4:5 輸出：`1080x1350`，aspect `0.8` = 小幅 crop，且很適合 Facebook feed。

如果使用者在從直式照片做 16:9 render 後說影片「被壓到」，要說明問題出在 crop/aspect 不符，然後產出更好的比例，而不是只解釋。

## Platform recommendations

### Facebook general feed post

建議：`1080x1350` (4:5)

理由：

- 比 1:1 或 16:9 用掉更多垂直的 mobile feed 空間。
- 很適合直式照片組。
- 沒有 9:16 那麼激進，所以仍像一則精緻的 feed 貼文，而不是 Reel。

### Facebook/Instagram Reels, Stories, TikTok, YouTube Shorts

建議：`1080x1920` (9:16)

理由：

- 原生的全螢幕直式格式。
- 若使用者預期是短影音的 mobile 觀看，最適合。

### YouTube, TV, desktop playback

建議：`1920x1080` (16:9)

只有橫式照片、或使用者接受 crop 時才用 full-bleed。對直式來源照片，若輸出必須是橫式，優先用模糊／壓暗的背景搭配置中的完整照片。

### Square social fallback

建議：`1080x1080` (1:1)

通用但較不沉浸；當使用者要廣泛相容、又想盡量少做平台專屬選擇時使用。

## Crop-handling options

1. **Full-bleed cover crop**
   - 最有電影感，但可能裁掉內容。
   - 適合來源與輸出比例相近時。

2. **Blurred background + centered photo**
   - 保留完整照片內容。
   - 適合橫式 16:9 影片裡的直式照片。

3. **Framed/postcard layout**
   - 完整圖片加上刻意的邊框或色塊 matte。
   - 適合相簿／日記風格。

## Suggested response when user asks what ratio to use for Facebook

「Facebook 一般動態貼文我建議用 4:5（`1080x1350`）。Reels/Stories 則用 9:16（`1080x1920`）。因為你的來源照片是直式，4:5 會比 16:9 保留更多畫面，在 feed 裡通常看起來也更好。」
