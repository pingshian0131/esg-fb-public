# Session notes: cinematic travel slideshow from uploaded images

這些筆記記錄了形塑 `photo-slideshow-video` skill 的任務細節。

## Context

- 使用者透過 Telegram 上傳 10 張照片，並預期直接拿來用。
- 想要的風格：`電影感慢節奏`（cinematic slow-paced）。
- 想要的比例：橫式 16:9，供 YouTube/TV/電腦觀看。
- 使用者要求一首隨機的 YouTube 無版權音樂。

## Successful output spec

- 1920x1080，24 fps
- 10 張圖片加 title card 約 64 秒
- H.264 video ＋ AAC audio
- 緩慢的 Ken Burns motion、暖色低對比調色、vignette、cinematic 黑邊、fade in/out
- 以 `MEDIA:/absolute/path.mp4` 交付

## Technique that worked

- 直接使用附件的 image-cache 路徑。
- 用 Pillow 產生 title card，而不是依賴 ffmpeg 的 `drawtext`。
- 用 `-frames:v` 為每張照片 render 一段長度精確的 ffmpeg clip。
- 串接片段，再加上 loop/trim/fade 過的背景 audio。
- 交付前用 `ffprobe` 驗證。

## Pitfalls encountered

- 一般 slideshow 用 per-frame Python rendering 太慢。它比較適合留給自訂的生成式效果。
- ffmpeg 的 `drawtext` 視 build 而定可能不存在；Pillow title card 比較可攜。
- 如果 duration 控制不當，still-image 的 `zoompan` 指令可能不小心產生很長的 clip。用 `-frames:v` 強制 clip 長度，duration 不對時逐段檢查 clip。

## v2 lessons (mixed media + subtitles)

在把 skill 擴充到能處理影片片段和 SRT 字幕之後，又冒出一些雷：

- **不安全的 `$DUR` heredoc**：原本的 template 用了 `<<PY`（未加引號），會在 shell 裡展開 `$DUR`。如果 `ffprobe` 失敗，heredoc 就會把 `float('')` 傳給 Python，在 `set -euo pipefail` 下整條 pipeline 掛掉。修法是改用 `DUR="$DUR" python3 -c '...'` 的 env-var 傳遞方式，並在 `ffprobe` 後加上明確的空字串防護。
- **macOS bash 3.2 上的 bash 4 `mapfile`**：原本用 `mapfile -t`；為了可攜性改成 `while IFS= read -r -d ''` ＋ `find -print0`。
- **EXIF orientation**：ffmpeg 的 `transpose` 不會讀 EXIF。`Orientation=6` 的手機照片 render 成橫躺。現在所有 template 都會在任何 ffmpeg 步驟前用 `ImageOps.exif_transpose` 做 Pillow 預處理。
- **來源影片 fps 不一**：手機片段是 30/60 fps。concat demuxer 遇到 fps 不符會無聲地失敗；在每個 normalize 步驟強制 `fps=24` ＋ `setsar=1`。
- **Still clip 的無聲 audio 軌**：把照片 Ken Burns clip 與真正的影片 clip 混在一起時，若有些有 audio、有些沒有，concat demuxer 會壞掉。解法：still clip 加上一條同 sample rate 的 `-f lavfi -i anullsrc=channel_layout=stereo` 無聲 stereo 軌。
- **Ducking 抽吸感**：`sidechaincompress` 的 release time 太短會在字與字之間造成可聽見的抽吸（pumping）。`attack=20:release=400`（ms）對慢節奏旅遊旁白是不錯的平衡；音樂為主的內容把 release 提高到 600–800。
- **缺少 libass**：與其無聲地 fallback 到 `drawtext` 或 Pillow PNG overlay（明顯較差），`burn_srt_subtitles.sh` 會直接失敗並給出明確的安裝說明。
- **Big5 SRT 編碼**：來自 Windows 的 zh-TW SRT 仍很常見。用 `file --mime-encoding` 自動偵測，對未知的 8-bit 退而假設為 Big5，再用 `iconv` 轉成 UTF-8。
