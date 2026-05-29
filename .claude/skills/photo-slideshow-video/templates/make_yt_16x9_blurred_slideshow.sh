#!/usr/bin/env bash
# Template: YouTube/desktop 16:9 (1920x1080) slideshow with blurred background.
# Use when source photos are portrait but output must be horizontal (YouTube/TV/computer).
# Preserves the full image (no aggressive crop) by placing a centered-fit photo
# on top of a blurred enlarged version of itself.
#
# Requirements:
#   - ffmpeg + ffprobe
#   - python3 with Pillow (for EXIF orientation fix)
#   - bash 3.2+
set -euo pipefail

PHOTO_DIR="${PHOTO_DIR:-./photos}"
AUDIO="${AUDIO:-./music.mp3}"
OUTDIR="${OUTDIR:-./out}"
FINAL="$OUTDIR/yt_16x9_blurred_slideshow.mp4"
TMP="$OUTDIR/yt16x9_clips"
EXIF_DIR="$OUTDIR/yt16x9_exif"
FPS=24
PHOTO_SECONDS=6
FRAMES=$((FPS * PHOTO_SECONDS))
W=1920
H=1080
mkdir -p "$TMP" "$EXIF_DIR"
rm -f "$TMP"/*.mp4 "$EXIF_DIR"/* "$OUTDIR/concat_16x9.txt" "$FINAL" 2>/dev/null || true

photos=()
while IFS= read -r -d '' f; do
  photos+=("$f")
done < <(find "$PHOTO_DIR" -maxdepth 1 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
  -print0 | sort -z)

if [[ ${#photos[@]} -eq 0 ]]; then
  echo "No photos found in $PHOTO_DIR" >&2
  exit 1
fi

# --- EXIF preprocess ---
PHOTO_LIST_FILE="$EXIF_DIR/_paths.txt"
: > "$PHOTO_LIST_FILE"
for p in "${photos[@]}"; do
  printf '%s\n' "$p" >> "$PHOTO_LIST_FILE"
done

PATHS_FILE="$PHOTO_LIST_FILE" OUT_DIR="$EXIF_DIR" python3 - <<'PY'
import os, pathlib
from PIL import Image, ImageOps
paths_file = os.environ["PATHS_FILE"]
out_dir = pathlib.Path(os.environ["OUT_DIR"])
with open(paths_file) as fh:
    sources = [line.rstrip("\n") for line in fh if line.strip()]
for idx, src in enumerate(sources):
    img = ImageOps.exif_transpose(Image.open(src))
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")
    dst = out_dir / f"img_{idx:03d}.jpg"
    img.save(dst, "JPEG", quality=95)
PY

photos=()
while IFS= read -r -d '' f; do
  photos+=("$f")
done < <(find "$EXIF_DIR" -maxdepth 1 -type f -name 'img_*.jpg' -print0 | sort -z)

# Blurred background + centered photo composite per clip.
#   [bg] scale=1920x1080 cover crop, then heavy boxblur + slight darken.
#   [fg] scale to fit inside 1920x1080 (preserves full image, no crop).
#   overlay fg centered on bg, apply Ken Burns zoom to the composite,
#   then color grade + fades.
for i in "${!photos[@]}"; do
  p="${photos[$i]}"
  clip="$TMP/clip_$(printf '%02d' "$i").mp4"
  ffmpeg -hide_banner -loglevel error -y -loop 1 -i "$p" -frames:v "$FRAMES" \
    -filter_complex "
      [0:v]split=2[bgsrc][fgsrc];
      [bgsrc]scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},boxblur=24:2,eq=brightness=-0.08:saturation=0.85[bg];
      [fgsrc]scale=w='if(gt(a,${W}/${H}),${W},-1)':h='if(gt(a,${W}/${H}),-1,${H})':force_original_aspect_ratio=decrease[fg];
      [bg][fg]overlay=(W-w)/2:(H-h)/2,zoompan=z='1+0.035*on/($FRAMES-1)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=$FRAMES:s=${W}x${H}:fps=$FPS,eq=contrast=0.95:brightness=-0.01:saturation=1.05,vignette=PI/6,fade=t=in:st=0:d=0.7,fade=t=out:st=5.25:d=0.75,setsar=1,format=yuv420p
    " \
    -c:v libx264 -preset veryfast -crf 19 -r "$FPS" "$clip"
  printf "file '%s'\n" "$clip" >> "$OUTDIR/concat_16x9.txt"
done

SILENT="$OUTDIR/yt_16x9_silent.mp4"
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$OUTDIR/concat_16x9.txt" \
  -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p "$SILENT"

DUR=$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$SILENT")
if [[ -z "${DUR:-}" ]]; then
  echo "ffprobe failed to read duration from $SILENT" >&2
  exit 1
fi

FADEOUT=$(DUR="$DUR" python3 -c 'import os; print(max(0, float(os.environ["DUR"]) - 3))')

if [[ -f "$AUDIO" ]]; then
  ffmpeg -hide_banner -loglevel error -y -i "$SILENT" -stream_loop -1 -i "$AUDIO" -t "$DUR" \
    -filter:a "volume=0.40,afade=t=in:st=0:d=1.5,afade=t=out:st=$FADEOUT:d=3" \
    -c:v copy -c:a aac -b:a 192k -shortest "$FINAL"
else
  echo "AUDIO file '$AUDIO' not found — exporting silent video" >&2
  cp "$SILENT" "$FINAL"
fi

ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_type,codec_name,width,height,r_frame_rate -of json "$FINAL"
echo "$FINAL"
