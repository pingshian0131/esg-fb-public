# Mixed photo + video pipeline

如何把 still 照片與短影片片段合成一支精緻的 slideshow，又不出現 timestamp 破圖或 audio 抽吸。

## Detection

對每個檔案跑 `ffprobe`：

```bash
ffprobe -v error -count_frames -select_streams v:0 \
  -show_entries stream=nb_read_frames -of default=nk=1:nw=1 "$f"
```

- `1` → still image（PNG/JPG）
- `>1` → video clip

`-count_frames` 精確但會讀整條 stream；檔案非常長時改用 `-show_entries stream=duration,r_frame_rate` 來推算。

是否有 audio：

```bash
ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$f"
```

為空 → 沒有 audio stream。

## Normalize step (required before concat)

concat demuxer 對一致性**非常嚴格**。即使是小小的不符也會讓播放壞掉。把每段輸出 clip 正規化成：

- Resolution：目標 W×H
- `fps=24`（強制，不管來源是 30/60/240 fps）
- `setsar=1`（square pixels）
- `format=yuv420p`
- Codec：`libx264 -crf 19 -preset veryfast`
- Audio（若有）：`aac -ar 44100 -ac 2 -b:a 192k`

連 still-image clip 也需要一條無聲 stereo audio 軌（透過 `-f lavfi -i anullsrc=...`），這樣當其他 clip 有 audio 時，concat 才不會卡住。

## Per-type render strategy

### Still image clip

- 在任何 ffmpeg 步驟前用 `ImageOps.exif_transpose` 做 EXIF 預處理。
- 預先放大比目標多 13%，留給 Ken Burns zoom 的餘裕。
- 依索引交替 pan 方向（垂直飄移／水平飄移）。
- 加上無聲 stereo audio 軌以符合 concat 一致性。
- Duration：預設 `PHOTO_SECONDS=6`（4–8 合理）。

### Video clip

- 預設：同時保留原始 duration 與原始 audio。
- 選用 `TRIM_VIDEO_TO=N` 來限制 duration。
- 選用 `STRIP_VIDEO_AUDIO=1` 來丟棄原始聲音。
- Scale ＋ crop 到目標 W×H（cover crop 可接受；使用者已經接受了影片的取景）。
- 強制 `fps=24` 和 `setsar=1`。
- 若來源沒有 audio stream，視為無聲（不要加 anullsrc；ducking 自然就沒有觸發來源）。

## Background music ducking

目標：背景音樂在無聲（still-image）段落正常播放，但在影片片段的原始 audio 下方 duck。

ffmpeg filter chain（當至少有一段影片 clip 保留了原始 audio 時）：

```text
[1:a]volume=0.55,afade=t=in:st=0:d=1.5,afade=t=out:st=$FADEOUT:d=3[bgmraw];
[0:a]asplit=2[trig][orig];
[bgmraw][trig]sidechaincompress=threshold=0.05:ratio=8:attack=20:release=400[bgmducked];
[orig][bgmducked]amix=inputs=2:duration=first:dropout_transition=0:weights=1.3 0.9[aout]
```

調校：

- `threshold=0.05` — 在語音音量的輸入時觸發。如果輕微的背景環境聲就會觸發，提高到 `0.1`。
- `ratio=8` — 中等壓縮。要更強的 ducking 就提高到 `12-20`。
- `attack=20:release=400`（ms）— 快 attack 避免「ducking 延遲」；慢 release 防止字與字之間的抽吸。
- `weights=1.3 0.9` — 在最終混音中，原始 audio 略高於被 duck 的音樂。

當沒有任何影片 clip 有 audio 時，完全跳過 ducking，只要把合併後的無聲 audio 與背景音樂 `amix` 即可。仍然需要 `amix`，因為合併後的 audio 軌確實存在（still clip 帶有無聲 stereo）。

## Common failure modes

- **Concat 破圖／卡頓**：SAR 或 fps 不符。normalize 步驟可解決；在每段 clip 的 filter chain 加上 `setsar=1` 和 `fps=24`。
- **concat 後 audio sync 飄移**：來源影片是 VFR（variable frame rate）。normalize 步驟的 `fps=24` 會重打時間戳；若仍飄移，用 `-vsync cfr` 重新編碼。
- **音樂被提早切掉**：`-shortest` 沒問題，但 `-t "$DUR"` 必須用實際合併後的影片 duration，而非估計值。concat 後務必重新 `ffprobe`。
- **音樂抽吸**：release 太短。試試 `release=600` 或 `800`。
- **音樂蓋過語音**：把背景的 `volume=0.55` 調低，或提高 `ratio`。
- **過長的來源影片主導節奏**：當來源 > 30 秒且未設 `TRIM_VIDEO_TO` 時發出 stderr 警告；讓使用者決定。

## Why not crossfade?

concat demuxer 做的是直接硬切。clip 之間要 crossfade 需要 `xfade` filter chain，而那需要複雜的 `filter_complex` graph，超過 5–6 個 clip 後就難以擴展。對 10 個以上的混合素材，硬切加上每段 clip 的 `fade in/out` 看起來可接受，又好維護。
