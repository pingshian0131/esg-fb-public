# Burning SRT subtitles into a finished video

這個 skill 透過 ffmpeg 的 `subtitles` filter（以 libass 為後端）來 burn 字幕（hard sub）。我們不做 soft sub（sidecar 軌）或每張照片的 caption overlay。

## Why burn-in only

- burn-in 到處都能用 — Facebook、Instagram、TikTok、Reels、LINE — 因為文字是畫面的一部分。
- soft sub（sidecar）需要播放器支援 `mov_text` 或外部 `.srt`，而大多數社群平台會把它剝掉。
- 每張照片的 Pillow caption overlay 是另一回事（每段 clip 的持續文字），不在這個 skill 版本的範圍內。

## Pipeline at a glance

1. Pre-flight 檢查：ffmpeg 有沒有提供 `subtitles` filter？沒有就明確失敗並附上安裝說明。
2. 偵測 SRT 編碼；正規化成 UTF-8（無 BOM）。
3. 合理性檢查：檔案是否含有 `-->`？
4. 用 `subtitles=clean.srt:force_style='...'` 跑 ffmpeg。
5. ffprobe 輸出；透過 `MEDIA:` 交付。

## Encoding handling

較舊的 zh-TW 工作流常產出 Windows Big5/CP950 的 SRT。UTF-16（含 BOM）則常見於 Notepad 匯出。template 的做法：

```bash
ENC=$(file --mime-encoding -b "$SRT")
iconv -f "$ENC" -t UTF-8 "$SRT" > clean.srt
```

`file --mime-encoding` 回傳小寫的 MIME 標籤（`utf-8`、`utf-16le`、`iso-8859-1`、`unknown-8bit` 等）。對於含中文、看起來像 Latin-1 或未知的檔案，template 會退而假設為 Big5 — 對主流 zh-TW 邊角情況的盡力處理。

BOM strip：用 `head -c 3 | od -An -tx1` 檢查是否為 `EF BB BF`，再用 `tail -c +4` 修掉。

## libass styling cheat-sheet

Style 透過 `subtitles=...:force_style='K1=V1,K2=V2,...'` 傳入。最常用的 key：

| Key            | 意義                                           | template 預設       |
| -------------- | ---------------------------------------------- | ------------------- |
| `FontName`     | 字型家族名稱（必須已安裝）                      | `PingFang TC`       |
| `Fontsize`     | 相對於 PlayResY 的點數大小                      | `22`                |
| `PrimaryColour`| 文字顏色 `&HAABBGGRR`                          | white               |
| `OutlineColour`| Outline 顏色                                   | black               |
| `BackColour`   | 陰影顏色                                        | black               |
| `Outline`      | Outline 粗細（px）                             | `2`                 |
| `Shadow`       | 陰影距離（px）                                 | `1`                 |
| `BorderStyle`  | `1` = outline+shadow，`3` = boxed 背景         | `1`                 |
| `Alignment`    | 數字鍵盤排列：`2`=底部置中，`8`=頂部           | `2`                 |
| `MarginV`      | 距頂／底的垂直邊距（px）                        | `40`                |

要做出一個顯眼、難以忽略、黑色方塊背景的黃色字幕：

```
FontName=PingFang TC,Fontsize=26,PrimaryColour=&H00FFFF,BorderStyle=3,Outline=8,BackColour=&H80000000,Alignment=2,MarginV=60
```

## Traditional Chinese font choices

- **macOS 預設**：`PingFang TC` 隨作業系統內建 — 首選。
- **跨平台**：`Noto Sans CJK TC`（`brew install --cask font-noto-sans-cjk-tc` 或 apt 對應指令）。
- **變體**：`Heiti TC`、`STHeiti`、`Source Han Sans TC` 都可用；以**家族名稱**指定，不要用檔案路徑。
- 查看已安裝的字型：`fc-list :lang=zh-tw | head`。

如果 `force_style` 裡的字型名稱對不上任何已安裝的家族，libass 會無聲地 fallback 到通常缺 CJK glyph 的預設字型 — 結果就是方框（tofu）。template 的 preflight 會對此提出警告。

## Failure modes & remedies

- **`No such filter: subtitles`** — ffmpeg 編譯時沒有 libass。重新安裝（`brew reinstall ffmpeg`）。
- **Tofu（`☐☐☐`）** — 字型缺失或名稱錯誤。用 `fc-list :lang=zh-tw` 驗證；設定 `SLIDESHOW_FONT="Noto Sans CJK TC"`。
- **字幕看不見** — 很可能是編碼不符（libass 嘗試以 UTF-8 讀取，但檔案其實是 Big5）。用 `head` 檢查 `clean.srt`，確認字元看起來正確。
- **跑到畫面外／位置錯誤** — `Alignment` 不符，或 `MarginV` 相對影片 resolution 太大。
- **字幕太大／太小** — `Fontsize` 是相對於 libass 內部 `PlayResY`（預設 288）縮放。1080p 影片 `Fontsize=22-30` 看起來平衡；4:5 1350 高的影片試 `24-28`。

## Why no fallback to drawtext / Pillow

如果缺少 libass，template 會**明確失敗**而不 fallback。理由：

- drawtext 缺乏適當的斷行、編碼容錯與 styling。
- Pillow PNG-overlay 的路徑要對 SRT 精準計時很複雜，且產出明顯不同，會誤導使用者以為環境裝好了。
- 跟使用者說「安裝 libass」只要一句話；無聲地產出較差的字幕更糟。

## SRT format reminders

- 索引從 1 開始。
- 時間格式：`HH:MM:SS,mmm`（毫秒前是逗號，不是句點）。
- 每個 cue 以一個空行結尾。
- 長行應手動斷行；必要時 libass 支援用 `\N` 做明確換行。

最小範例：

```
1
00:00:01,000 --> 00:00:04,500
日月潭的晨霧緩緩散開

2
00:00:05,000 --> 00:00:08,000
湖面像是被光輕輕喚醒
```
