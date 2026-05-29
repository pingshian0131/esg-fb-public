#!/usr/bin/env bash
# Template: Facebook feed 4:5 photo slideshow with music.
# Copy this file and edit PHOTO_DIR / AUDIO / OUTDIR / title text as needed.
#
# Requirements:
#   - ffmpeg + ffprobe
#   - python3 with Pillow (for EXIF orientation fix)
#   - bash 3.2+ (macOS default supported)
set -euo pipefail

PHOTO_DIR="${PHOTO_DIR:-./photos}"
AUDIO="${AUDIO:-./music.mp3}"
OUTDIR="${OUTDIR:-./out}"
FINAL="$OUTDIR/fb_post_4x5_slideshow.mp4"
TMP="$OUTDIR/fb4x5_clips"
EXIF_DIR="$OUTDIR/fb4x5_exif"
FPS=24
PHOTO_SECONDS=6
FRAMES=$((FPS * PHOTO_SECONDS))
mkdir -p "$TMP" "$EXIF_DIR"
rm -f "$TMP"/*.mp4 "$EXIF_DIR"/* "$OUTDIR/concat_4x5.txt" "$FINAL" 2>/dev/null || true

# Collect common image extensions. Portable across macOS bash 3.2 (no mapfile).
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

# --- EXIF preprocess: copy each photo into $EXIF_DIR with EXIF orientation applied. ---
# ffmpeg's transpose does NOT read EXIF, so phone photos with Orientation tag 3/6/8
# would render rotated. ImageOps.exif_transpose handles all 8 EXIF orientations.
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

# Rebuild photos array from EXIF-corrected files.
photos=()
while IFS= read -r -d '' f; do
  photos+=("$f")
done < <(find "$EXIF_DIR" -maxdepth 1 -type f -name 'img_*.jpg' -print0 | sort -z)

for i in "${!photos[@]}"; do
  p="${photos[$i]}"
  clip="$TMP/clip_$(printf '%02d' "$i").mp4"
  if (( i % 2 == 0 )); then
    xpos="iw/2-(iw/zoom/2)"
    ypos="ih/2-(ih/zoom/2)-((ih-ih/zoom)/9)*(on/($FRAMES-1)-0.5)"
  else
    xpos="iw/2-(iw/zoom/2)+((iw-iw/zoom)/9)*(on/($FRAMES-1)-0.5)"
    ypos="ih/2-(ih/zoom/2)"
  fi
  ffmpeg -hide_banner -loglevel error -y -loop 1 -i "$p" -frames:v "$FRAMES" \
    -vf "scale=1220:1525:force_original_aspect_ratio=increase,crop=1220:1525,zoompan=z='1+0.045*on/($FRAMES-1)':x='$xpos':y='$ypos':d=$FRAMES:s=1080x1350:fps=$FPS,eq=contrast=0.94:brightness=-0.012:saturation=1.07:gamma_r=1.025:gamma_b=0.97,vignette=PI/6,fade=t=in:st=0:d=0.65,fade=t=out:st=5.30:d=0.70,setsar=1,format=yuv420p" \
    -c:v libx264 -preset veryfast -crf 19 -r "$FPS" "$clip"
  printf "file '%s'\n" "$clip" >> "$OUTDIR/concat_4x5.txt"
done

SILENT="$OUTDIR/fb_post_4x5_silent.mp4"
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$OUTDIR/concat_4x5.txt" \
  -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p "$SILENT"

DUR=$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$SILENT")
if [[ -z "${DUR:-}" ]]; then
  echo "ffprobe failed to read duration from $SILENT" >&2
  exit 1
fi

# Safe env-var passing — never embed $DUR inside an unquoted heredoc.
FADEOUT=$(DUR="$DUR" python3 -c 'import os; print(max(0, float(os.environ["DUR"]) - 3))')

if [[ -f "$AUDIO" ]]; then
  ffmpeg -hide_banner -loglevel error -y -i "$SILENT" -stream_loop -1 -i "$AUDIO" -t "$DUR" \
    -filter:a "volume=0.42,afade=t=in:st=0:d=1.5,afade=t=out:st=$FADEOUT:d=3" \
    -c:v copy -c:a aac -b:a 192k -shortest "$FINAL"
else
  echo "AUDIO file '$AUDIO' not found — exporting silent video" >&2
  cp "$SILENT" "$FINAL"
fi

ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_type,codec_name,width,height,r_frame_rate -of json "$FINAL"
echo "$FINAL"
