# Pillow burned-subtitles fallback for mixed travel slideshow

## Context

一支混合直式照片＋直式影片的旅遊回顧，需要一個帶音樂與繁體中文 burned 字幕的橫式 16:9 MP4。當下 session 的 Homebrew ffmpeg 有 `libx264` 但沒有 `subtitles`/libass filter，所以正常的 SRT burn-in 路徑跑不起來。

## Durable technique

當使用者現在就要完成的影片、而 ffmpeg 又缺少 `subtitles` filter 時，一個實用的 fallback 是用 Pillow 透過 pipe raw frames 來 burn 字幕：

1. 先 render 不含字幕的 silent/video+music MP4。
2. 在 Python 裡 parse SRT。
3. 用 ffmpeg 解碼 video frames：
   ```bash
   ffmpeg -hide_banner -loglevel error -i input.mp4 -an -f rawvideo -pix_fmt rgb24 -
   ```
4. 對每個 RGB frame，計算 `t = frame_index / fps`，找出當前的 SRT cue，再用 Pillow 畫上文字：
   - 使用繁體中文字型，例如 macOS 上的 `/System/Library/Fonts/PingFang.ttc`。
   - 在靠近底部的文字後方畫一個半透明圓角矩形。
   - 用白色文字加黑色 stroke 以利閱讀。
   - 過長的繁體中文行依量測到的 pixel 寬度斷行，而非依字數。
5. 把 raw frames 餵回 ffmpeg，並從原始影片 map audio：
   ```bash
   ffmpeg -y -f rawvideo -pix_fmt rgb24 -s 1920x1080 -r 24 -i - \
     -i input.mp4 -map 0:v:0 -map 1:a:0 \
     -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
     -c:a copy -shortest output_subtitled.mp4
   ```
6. 用 `ffprobe` 驗證，再從某個字幕時間點抽出一個 frame 來目視檢查。

## Notes

- 有 libass 的 `subtitles` 時優先用它；品質與 shaping 較好。
- 對簡單的單行或短的繁體中文字幕，Pillow fallback 是可接受的，而且能避免讓使用者卡在 ffmpeg 重建／設定上。
- 保持 log 安靜，但長時間 render 時每隔約 10 秒回報一次 frame 進度。
- 這是交付用的 fallback，不是標準 libass 工作流的替代品。

## Verification checklist from the session

- `ffprobe` 顯示 1920x1080、24 fps、H.264 video、AAC audio，約 100 秒。
- 在某個字幕 timestamp 抽出的 frame 確認：橫式 16:9、保留的直式來源置中並帶模糊背景、下三分之一處有清楚可讀的繁體中文字幕。
