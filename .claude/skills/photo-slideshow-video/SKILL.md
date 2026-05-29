---
name: photo-slideshow-video
description: "Use when the user wants to turn photos or short video clips into a polished video slideshow: travel recap, Facebook/Instagram/Reels post, YouTube montage, cinematic slow video, cute photo video, Ken Burns motion, music, titles, SRT subtitles, aspect-ratio/cropping advice, and export verification. Especially use this when photos or short clips are uploaded in chat or the user asks why a slideshow looks cropped or compressed."
license: MIT
metadata:
  hermes:
    tags: [video, photos, slideshow, ffmpeg, social-media, travel, subtitles]
    related_skills: [youtube-content, ascii-video]
---

# Photo Slideshow Video Production

## 何時使用

當使用者想把照片（或加上短影片片段）做成影片時使用，例如：旅遊回憶、家庭／相片相簿、電影感 slideshow、社群 reels、慢節奏旅遊影片、相片 montage，或以照片為主的音樂 MV。

Trigger phrases (Chinese / English)：

- 「做成影片」「做個 slideshow」「旅遊回顧」「電影感」「上字幕」「燒字幕」
- "make a slideshow", "turn into a video", "cinematic", "burn subtitles", "add SRT"
- 「被壓到」「被切掉」"looks squished", "looks cropped" — 通常是 aspect-ratio 不合的問題

如果使用者已經在對話中附上圖片或影片片段，請立即把這些附件當作可直接使用的素材。除非還需要更多素材，或使用者明確表示要用本機資料夾，否則不要再問資料夾路徑。

## 旅遊／自然照片的預設創意方向

對於沉靜的旅遊、公園、自然、校園、動物或池塘照片，一個很穩的預設方向是：

- Style：cinematic 慢節奏的旅遊回憶
- Aspect：依來源照片比例＋目標平台來選；不要盲目預設成 16:9
- YouTube/TV/desktop：1920x1080 (16:9)
- Facebook 一般動態貼文：1080x1350 (4:5)，尤其是直式照片
- Reels/Stories/Shorts/TikTok：1080x1920 (9:16)
- Frame rate：24 fps
- 每張照片時長：4–6 秒
- Motion：緩慢的 Ken Burns zoom/pan，方向交替
- Transitions：柔和的 fade in/out 或 crossfade
- Grade：略暖、低對比、輕微飽和、淡淡的 vignette
- Letterbox：適合的話加上 cinematic 黑邊，但在直式／社群版本要把黑邊縮小
- 開場：簡單的 title card，例如地點／日期／氛圍
- Audio：搭配照片氛圍的音樂；如果使用者要求可愛／輕快風格，就選歡快的音樂，而非 cinematic 氛圍音樂

### Aspect-ratio 規則

在推薦格式之前，先檢查來源尺寸。如果所有照片都是直式，full-bleed 的 16:9 會嚴重裁切，使用者可能會形容成「被壓到」或「被切掉」／"squished"／"cropped"。這種情況下，建議：

1. Facebook feed／一般貼文用 4:5。
2. Reels/Stories/Shorts 用 9:16。
3. 只有在必須是橫式時，才用 16:9 搭配模糊／壓暗的背景並把完整照片置中（使用 `templates/make_yt_16x9_blurred_slideshow.sh`）。

一組 `960x1280` 的照片是 3:4 直式；轉成 4:5 只需要小幅 crop，但轉成 16:9 full-bleed 則需要嚴重 crop。

## 使用者體驗規則

當使用者上傳圖片並要求做影片時，請明確表示這些上傳的圖片已經足夠，然後直接進行。避免使用任何暗示「忽略了上傳圖片」的措辭。如果使用者問「所以我傳的照片沒用嗎？」，要立刻安撫對方，說明這些附件是可用的，並盡可能驗證本機 cache 路徑。

## Skill 使用紀律

只要請求符合上述觸發條件，在製作或修改照片／影片 slideshow 之前，就必須先載入這個 skill。不要先憑一般影片剪輯知識動手，等使用者問了才去看 skill。如果使用者之後問是否用了這個 skill，要誠實回答；如果漏掉了，就坦白說明，然後對照這個 skill 的 checklist 驗證產出，必要時主動提供／執行修正後的版本。

## 實務工作流

1. 收集輸入
   - 優先使用對話中已經存在的圖片／影片附件路徑。
   - 否則才詢問照片資料夾路徑。
   - 判斷這組素材是純照片、純影片，還是混合的。混合素材請見 [混合照片＋影片素材](#混合照片影片素材)。
   - 只詢問會實質影響產出的選項：aspect ratio、大概時長、要不要音樂、title 文字、字幕。
   - 如果使用者說「給 Facebook 用」或其他平台，要問清楚／決定是 feed 貼文還是 Reels/Stories，因為比例不同。
   - 如果下一步要發佈到 Facebook Page，先 render 並驗證 Facebook 專用版本（通常是 4:5 feed，除非使用者說要 Reels/Stories），再把驗證過的 media 路徑交接給 `facebook-page-post`。

2. 檢查輸入的尺寸與類型
   - 在任何 ffmpeg 步驟之前先套用 EXIF orientation（見 [EXIF orientation（方向）](#exif-orientation方向)）。
   - 在 render 之前先列出有代表性的寬／高／aspect ratio。
   - 對混合輸入，對每個檔案跑 `ffprobe`，分辨是 still 還是 video（still = 1 個 video frame，video > 1）。
   - 根據這些尺寸決定要用 crop、blurred-background，還是直式／社群版本。
   - 當某個要求的輸出比例會嚴重裁切圖片時，要明確點出來。

3. 確認工具
   - 用 `ffmpeg`/`ffprobe` 來 render 和驗證。
   - 用 Pillow/Python 做 title card 或簡單合成。
   - 要 burn-in SRT 時，確認 ffmpeg 有 `subtitles` filter（libass）。見 [Burn SRT 字幕](#burn-srt-字幕)。
   - 一般 slideshow 避免用吃重的 per-frame Python rendering；盡量用 ffmpeg 原生 filter。

4. 準備音樂
   - 如果使用者要求「YouTube 無版權音樂」，盡量使用授權／標示清楚的來源。
   - 用 `yt-dlp` 另外下載，再 trim/loop 以對齊影片時長（見 [音樂來源](#音樂來源)）。
   - 音量放輕，通常 `volume=0.25–0.45`，再加上 `afade` in/out。
   - 當素材中含有保留原始 audio 的影片片段時，背景音樂必須在它下方 duck（見 [混合照片＋影片素材](#混合照片影片素材)）。

5. Render 片段
   - 每張照片做成一段短 clip，方便 debug 和重 render。
   - 用 ffmpeg filter 做 cover crop、zoompan、調色、vignette、黑邊和 fade。
   - 用 concat demuxer 把片段串接起來，再加上 audio。
   - 選用：在完成的 mp4 上以後處理步驟 burn 字幕。

6. 驗證產出
   - 跑 `ffprobe` 確認：duration、video stream、audio stream、resolution、codec、檔案大小。
   - 用 `MEDIA:/absolute/path.mp4` 交付最終 MP4。

## 穩健的 ffmpeg patterns

### Title cards（標題卡）

不要假設 ffmpeg 一定有 `drawtext` 可用。先 probe 一下，或採用穩健的預設做法：用 Pillow 產生一張 title card 圖片，再把它當成一般 clip 放進去。

Pillow title card 的好處：

- 即使 ffmpeg 缺少 `drawtext`/fontconfig 也能用。
- 更容易控制陰影、字體排版、blur 和 letterbox。
- 避免 shell filtergraph 裡的跳脫字元問題。

### Ken Burns 靜態圖片 clip

用 `-frames:v` 來強制精確的 clip 長度。不要只靠 `zoompan` 搭配 `-t`，因為 filtergraph 計時不對時可能產生意外過長的 clip。

範例（16:9；4:5 請見 `templates/make_fb_4x5_slideshow.sh`）：

```bash
ffmpeg -y -loop 1 -i "$photo" -frames:v 144 \
  -vf "scale=2200:1240:force_original_aspect_ratio=increase,crop=2200:1240,zoompan=z='1+0.065*on/143':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=144:s=1920x1080:fps=24,eq=contrast=0.93:brightness=-0.015:saturation=1.08,vignette=PI/5,drawbox=x=0:y=0:w=iw:h=76:color=black@1:t=fill,drawbox=x=0:y=ih-76:w=iw:h=76:color=black@1:t=fill,fade=t=in:st=0:d=0.7,fade=t=out:st=5.25:d=0.75,format=yuv420p" \
  -c:v libx264 -preset veryfast -crf 19 -r 24 "$clip"
```

24 fps 下 6 秒用 `-frames:v 144`，5 秒用 `120`。

### 串接片段並加上 audio

注意這裡的 env-var heredoc 寫法 — 千萬不要把 `$DUR` 放進未加引號的 heredoc，否則一旦 `ffprobe` 失敗（`$DUR` 為空）就會讓 `float('')` 崩潰：

```bash
ffmpeg -y -f concat -safe 0 -i concat.txt \
  -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p silent.mp4

DUR=$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 silent.mp4)
[[ -z "$DUR" ]] && { echo "ffprobe failed to read duration" >&2; exit 1; }
FADEOUT=$(DUR="$DUR" python3 -c 'import os; print(max(0, float(os.environ["DUR"]) - 4))')

ffmpeg -y -i silent.mp4 -stream_loop -1 -i music.mp3 -t "$DUR" \
  -filter:a "volume=0.35,afade=t=in:st=0:d=3,afade=t=out:st=$FADEOUT:d=4" \
  -c:v copy -c:a aac -b:a 192k -shortest final.mp4
```

## 混合照片＋影片素材

當使用者上傳或指定一組照片與短影片片段的混合素材時，把它們一起處理，並使用 `templates/make_mixed_media_slideshow.sh`。

預設行為（符合多數使用者的期待）：

- **照片** → Ken Burns clips（與純照片路徑相同）。
- **影片** → 正規化到目標 resolution/fps/codec，**但保留原始 duration 和原始 audio**。
- **背景音樂** → 透過 `sidechaincompress` 自動在影片片段的原始 audio 下方 duck（典型值：`threshold=0.05:ratio=8:attack=20:release=400`）。
- 所有 clip 在 concat 前都強制成 `fps=24` 和 `setsar=1`，以避免 demuxer 的 timestamp 不一致。

偵測方式：`ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of default=nk=1:nw=1 "$f"` 對 still image 回傳 `1`，對 video 回傳 `>1`。

透過 env vars 覆寫：

- `TRIM_VIDEO_TO=6` — 強制每段影片 clip 為 N 秒。
- `STRIP_VIDEO_AUDIO=1` — 丟棄原始影片 audio；背景音樂不 duck 直接播放。

要發出的警告（stderr，不阻擋流程）：

- 影片片段超過 30 秒 → 「會主導整支 slideshow 的節奏」。
- 16:9 輸出中混合 orientation（直式＋橫式）→ 建議每段 clip 改用 blurred-bg template。

## Burn SRT 字幕

把 `templates/burn_srt_subtitles.sh` 當作完成 mp4 後首選的**後處理步驟**。這個 skill 針對的是 **burned-in** 字幕（依使用者選擇，sidecar/soft sub 不在範圍內）。

Pipeline：

1. **Preflight** — 對 ffmpeg probe `subtitles` filter（libass）。要用真正的 filter 檢查，例如 `ffmpeg -hide_banner -filters | grep -w subtitles`；太寬鬆的 grep 可能會誤判。
2. **Encoding** — 用 `file --mime-encoding` 偵測 SRT 編碼；用 `iconv` 加上 BOM strip，自動把 Big5/CP950/UTF-16/UTF-8-with-BOM 轉成 UTF-8（無 BOM）。
3. **Font** — 透過 `force_style` 預設用 `PingFang TC`（macOS）。可用 `SLIDESHOW_FONT` env var 覆寫。見 [繁體中文字型](#繁體中文字型)。
4. **Burn** — `ffmpeg -i in.mp4 -vf "subtitles='clean.srt':force_style='FontName=PingFang TC,Fontsize=22,Outline=2,Shadow=1,Alignment=2'" -c:a copy out.mp4`。
5. **libass 不可用時的 fallback** — 如果 ffmpeg 缺少 `subtitles` 而使用者現在就要完成的影片，與其卡在環境設定上，不如用 Pillow/rawvideo 的 burn-in fallback。用 ffmpeg 把 frames 解碼成 RGB，用 CJK 字型（macOS 上的 PingFang TC）畫上當前的 SRT cue，再把 frames 餵回 ffmpeg 同時 copy audio。有 libass 時優先用它，但這個 fallback 對簡單的繁體中文旅遊字幕已經夠用。見 `references/pillow-burned-subtitles-fallback.md`。

常見失敗模式與該怎麼說：

- `No such filter: subtitles` → ffmpeg 編譯時沒有 libass；重新安裝 ffmpeg。
- `font ... not found` → 安裝字型，或把 `SLIDESHOW_FONT` 設成系統上存在的 CJK 字型。
- 字幕變成方框（tofu）→ 字型缺少中文 glyph；改用 PingFang TC 或 Noto Sans CJK TC。
- 字幕完全消失 → 很可能是 SRT 編碼不符；確認 `clean.srt` 是 UTF-8。

## 繁體中文字型

- 預設：`/System/Library/Fonts/PingFang.ttc`（macOS，近期版本都有內建）。
- 覆寫：執行 template 前設定 `SLIDESHOW_FONT=/path/to/font.ttc` env var。
- 跨平台 fallback：Noto Sans CJK TC（`brew install --cask font-noto-sans-cjk-tc` 或 apt 對應指令）。
- 偵測：`fc-list :lang=zh-tw` 應至少列出一個字型；若為空，先安裝再執行。
- 缺字型的徵兆：文字 render 成方框／tofu（`☐☐☐`）。

## EXIF orientation（方向）

手機照片常把 orientation 存在 EXIF 裡，而不是真的旋轉像素。ffmpeg 的 `transpose` filter **不會**讀 EXIF，所以一張 `Orientation=6` 的直式照片，若沒先預處理就會 render 成橫躺的。

在任何 ffmpeg 步驟之前，務必先用 Pillow 預處理：

```bash
python3 - <<'PY'
from PIL import Image, ImageOps
import sys, pathlib
for p in sys.argv[1:]:
    img = ImageOps.exif_transpose(Image.open(p))
    img.save(p, quality=95)
PY photos/*.jpg
```

這已內建在 template 裡。如果使用者回報「有些照片是橫躺的」，幾乎都是 EXIF 問題 — 預處理後重新 render 即可。

## 音樂來源

另外下載，再透過 template 帶入。`yt-dlp` 是推薦的工具：

```bash
yt-dlp -x --audio-format mp3 -o "music.%(ext)s" "<YouTube URL>"
```

提醒事項：

- 確認授權（Creative Commons／YouTube Audio Library／藝人授權）。
- 對於「無版權音樂」的需求，優先用 YouTube 的 Audio Library 或 Free Music Archive。
- Template 不會自動下載 — 來源／授權的決定權留在你手上。

## Portability notes

- macOS 預設 bash 是 3.2 — template 採用可攜的 `while IFS= read -r` ＋ `find -print0`，而非 `mapfile`（bash 4+）。
- SRT burn-in 需要編譯時帶 libass 的 ffmpeg；Homebrew 預設的 build 已包含。
- EXIF 預處理需要 Pillow ＋ Python 3。
- SRT 編碼自動轉換需要 `iconv`（BSD/GNU 都可以）。

## 疑難排解心得

- 如果 ffmpeg 說 `No such filter: drawtext`，改用 Pillow 產生 title/subtitle frames，不要硬逼 ffmpeg 做文字 rendering。
- 如果 slideshow 意外變成好幾小時長，用 `ffprobe` 檢查每段 clip；確認 still-image 指令有用 `-frames:v`，並理解 `zoompan` 的 duration 語意。
- 如果 Python 的 per-frame rendering 很慢，一般 slideshow 就改用 ffmpeg filtergraph。把 per-frame Python 留給自訂的生成式／藝術效果。
- 長時間 render 時把 ffmpeg log 導向或抑制，但保留足夠的錯誤訊息以便 debug 失敗的 filter。
- 如果 concat demuxer 出現破圖或卡頓，檢查各 clip 的 `fps` 和 `SAR` 是否一致 — 在 concat 前先正規化。
- 如果混合素材 slideshow 中背景音樂蓋過影片原始 audio，提高 `sidechaincompress` 的 ratio，或調低基礎 `volume`。

## 參考文件

- `references/cinematic-travel-slideshow.md` — 一次 Telegram 上傳照片做旅遊 slideshow 的筆記，含精確的輸出規格、可行技術與踩雷紀錄。
- `references/social-aspect-ratios.md` — 平台 aspect-ratio 指引，以及直式照片組的 crop 決策。
- `references/mixed-media-pipeline.md` — 混合照片＋影片素材的 normalize-then-concat 策略、ducking、fps 統一。
- `references/srt-subtitles.md` — SRT burn-in 細節、編碼處理、libass styling、zh-TW 字型選擇。
- `references/pillow-burned-subtitles-fallback.md` — 當 ffmpeg 缺少 libass 的 `subtitles` filter 時，用 Pillow/rawvideo burn 繁體中文 SRT 字幕的 fallback。
- `references/telegram-mixed-media-facebook-handoff.md` — 混合照片／影片的 Telegram 附件工作流、Facebook 4:5 輸出、簡潔的 zh-TW 文案，以及交接給 `facebook-page-post`。

## 範本

- `templates/make_fb_4x5_slideshow.sh` — 帶音樂的 Facebook feed 4:5 (1080x1350) 照片 slideshow。Facebook 上直式照片組的預設。
- `templates/make_yt_16x9_blurred_slideshow.sh` — YouTube/desktop 16:9 (1920x1080)，帶模糊背景＋置中照片。當來源是直式但輸出必須是橫式時使用。
- `templates/make_mixed_media_slideshow.sh` — 混合照片＋短影片片段，背景音樂帶 sidechain ducking。
- `templates/burn_srt_subtitles.sh` — 對完成的 mp4 做後處理，用 libass ＋ zh-TW 字型 burn 上 SRT 字幕軌。

## 產出檢查清單

在最終回覆之前，驗證：

- 最終檔案存在且大小不為零。
- `ffprobe` 顯示預期的 duration。
- video stream 存在，且 resolution 與 frame rate 符合預期。
- 若有要求音樂，audio stream 存在。
- 若有要求字幕，目視確認字幕有出現（或跑 `ffmpeg ... -t 5 -frames:v 1 sample.png` 來檢查）。
- 在通訊平台上，檔案透過 `MEDIA:/absolute/path.mp4` 交付。
