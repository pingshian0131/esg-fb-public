#!/usr/bin/env bash
# Template: Mixed photo + video slideshow.
# Accepts both still images and short video clips in $MEDIA_DIR; concatenates
# them into one polished slideshow with background music that ducks under
# the original audio of video clips.
#
# Default behavior:
#   - Photos → Ken Burns clips ($PHOTO_SECONDS seconds each).
#   - Videos → normalized to target resolution/fps; original duration AND
#     original audio are preserved.
#   - Background music auto-ducks under video original audio (sidechaincompress).
#
# Overrides via env vars:
#   ASPECT=4x5|16x9|9x16    (default 4x5)
#   TRIM_VIDEO_TO=6         force every video clip to N seconds
#   STRIP_VIDEO_AUDIO=1     discard original video audio (no ducking needed)
#   PHOTO_SECONDS=6
#   FPS=24
#
# Requirements: ffmpeg, ffprobe, python3+Pillow, bash 3.2+.
set -euo pipefail

MEDIA_DIR="${MEDIA_DIR:-./media}"
AUDIO="${AUDIO:-./music.mp3}"
OUTDIR="${OUTDIR:-./out}"
ASPECT="${ASPECT:-4x5}"
PHOTO_SECONDS="${PHOTO_SECONDS:-6}"
FPS="${FPS:-24}"
TRIM_VIDEO_TO="${TRIM_VIDEO_TO:-}"
STRIP_VIDEO_AUDIO="${STRIP_VIDEO_AUDIO:-0}"

case "$ASPECT" in
  4x5)  W=1080; H=1350 ;;
  16x9) W=1920; H=1080 ;;
  9x16) W=1080; H=1920 ;;
  *) echo "Unsupported ASPECT='$ASPECT'. Use 4x5, 16x9, or 9x16." >&2; exit 1 ;;
esac

FINAL="$OUTDIR/mixed_${ASPECT}_slideshow.mp4"
TMP="$OUTDIR/mixed_${ASPECT}_clips"
EXIF_DIR="$OUTDIR/mixed_${ASPECT}_exif"
FRAMES=$((FPS * PHOTO_SECONDS))
mkdir -p "$TMP" "$EXIF_DIR"
rm -f "$TMP"/*.mp4 "$EXIF_DIR"/* "$OUTDIR/concat_mixed.txt" "$FINAL" 2>/dev/null || true

# Collect media files (images + videos) in directory order.
media=()
while IFS= read -r -d '' f; do
  media+=("$f")
done < <(find "$MEDIA_DIR" -maxdepth 1 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
     -o -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' \) \
  -print0 | sort -z)

if [[ ${#media[@]} -eq 0 ]]; then
  echo "No media found in $MEDIA_DIR" >&2
  exit 1
fi

is_video() {
  # Still images have nb_read_frames == 1; videos have many.
  local frames
  frames=$(ffprobe -v error -count_frames -select_streams v:0 \
    -show_entries stream=nb_read_frames -of default=nk=1:nw=1 "$1" 2>/dev/null || echo "0")
  [[ "$frames" =~ ^[0-9]+$ ]] && (( frames > 1 ))
}

has_audio_stream() {
  local count
  count=$(ffprobe -v error -select_streams a -show_entries stream=index \
    -of csv=p=0 "$1" 2>/dev/null | wc -l | tr -d ' ')
  [[ "$count" -gt 0 ]]
}

# Track which output clips contain original audio (used later for ducking).
clips_with_audio=()

idx=0
for src in "${media[@]}"; do
  clip="$TMP/clip_$(printf '%03d' "$idx").mp4"
  if is_video "$src"; then
    # ---------- VIDEO branch ----------
    dur=$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$src" 2>/dev/null || echo "0")
    dur_int=${dur%.*}
    if [[ -n "$TRIM_VIDEO_TO" ]]; then
      tflag=(-t "$TRIM_VIDEO_TO")
    else
      tflag=()
      if [[ "${dur_int:-0}" -gt 30 ]]; then
        echo "WARN: video clip '$src' is ${dur}s (>30s) and will dominate pacing. Set TRIM_VIDEO_TO=N to limit." >&2
      fi
    fi
    keep_audio=1
    [[ "$STRIP_VIDEO_AUDIO" == "1" ]] && keep_audio=0
    has_audio_stream "$src" || keep_audio=0

    if [[ "$keep_audio" == "1" ]]; then
      ffmpeg -hide_banner -loglevel error -y -i "$src" "${tflag[@]}" \
        -vf "scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},fps=${FPS},setsar=1,format=yuv420p" \
        -c:v libx264 -preset veryfast -crf 19 -r "$FPS" \
        -c:a aac -b:a 192k -ar 44100 -ac 2 \
        "$clip"
      clips_with_audio+=("$clip")
    else
      ffmpeg -hide_banner -loglevel error -y -i "$src" "${tflag[@]}" \
        -an \
        -vf "scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},fps=${FPS},setsar=1,format=yuv420p" \
        -c:v libx264 -preset veryfast -crf 19 -r "$FPS" \
        "$clip"
    fi
  else
    # ---------- STILL branch ----------
    exif_src="$EXIF_DIR/img_$(printf '%03d' "$idx").jpg"
    SRC="$src" DST="$exif_src" python3 - <<'PY'
import os
from PIL import Image, ImageOps
img = ImageOps.exif_transpose(Image.open(os.environ["SRC"]))
if img.mode not in ("RGB", "L"):
    img = img.convert("RGB")
img.save(os.environ["DST"], "JPEG", quality=95)
PY
    # Alternating Ken Burns direction.
    if (( idx % 2 == 0 )); then
      xpos="iw/2-(iw/zoom/2)"
      ypos="ih/2-(ih/zoom/2)-((ih-ih/zoom)/9)*(on/($FRAMES-1)-0.5)"
    else
      xpos="iw/2-(iw/zoom/2)+((iw-iw/zoom)/9)*(on/($FRAMES-1)-0.5)"
      ypos="ih/2-(ih/zoom/2)"
    fi
    # Pre-scale wider than target so zoompan has crop room.
    pre_w=$((W * 113 / 100))
    pre_h=$((H * 113 / 100))
    fadeout_start=$(awk "BEGIN{printf \"%.2f\", $PHOTO_SECONDS - 0.7}")
    ffmpeg -hide_banner -loglevel error -y -loop 1 -i "$exif_src" -frames:v "$FRAMES" \
      -vf "scale=${pre_w}:${pre_h}:force_original_aspect_ratio=increase,crop=${pre_w}:${pre_h},zoompan=z='1+0.045*on/($FRAMES-1)':x='$xpos':y='$ypos':d=$FRAMES:s=${W}x${H}:fps=$FPS,eq=contrast=0.94:brightness=-0.012:saturation=1.07,vignette=PI/6,fade=t=in:st=0:d=0.65,fade=t=out:st=${fadeout_start}:d=0.70,setsar=1,format=yuv420p" \
      -c:v libx264 -preset veryfast -crf 19 -r "$FPS" \
      -f lavfi -t "$PHOTO_SECONDS" -i anullsrc=channel_layout=stereo:sample_rate=44100 \
      -c:a aac -b:a 192k -shortest "$clip"
  fi
  printf "file '%s'\n" "$clip" >> "$OUTDIR/concat_mixed.txt"
  idx=$((idx + 1))
done

# Concat. All clips already have audio (still clips have silent stereo, video
# clips have either kept original or silent), so concat-demuxer works uniformly.
COMBINED="$OUTDIR/mixed_${ASPECT}_combined.mp4"
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$OUTDIR/concat_mixed.txt" \
  -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p \
  -c:a aac -b:a 192k \
  "$COMBINED"

DUR=$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$COMBINED")
if [[ -z "${DUR:-}" ]]; then
  echo "ffprobe failed to read duration from $COMBINED" >&2
  exit 1
fi
FADEOUT=$(DUR="$DUR" python3 -c 'import os; print(max(0, float(os.environ["DUR"]) - 3))')

if [[ ! -f "$AUDIO" ]]; then
  echo "AUDIO file '$AUDIO' not found — exporting without background music" >&2
  cp "$COMBINED" "$FINAL"
elif [[ ${#clips_with_audio[@]} -eq 0 ]]; then
  # No video original audio anywhere — simple background music mix.
  ffmpeg -hide_banner -loglevel error -y -i "$COMBINED" -stream_loop -1 -i "$AUDIO" -t "$DUR" \
    -filter_complex "[1:a]volume=0.40,afade=t=in:st=0:d=1.5,afade=t=out:st=$FADEOUT:d=3[bgm];[0:a][bgm]amix=inputs=2:duration=first:dropout_transition=0[aout]" \
    -map 0:v -map "[aout]" \
    -c:v copy -c:a aac -b:a 192k -shortest "$FINAL"
else
  # Mix background music with combined audio AND duck background under combined.
  # sidechaincompress: [bgm] is compressed using [0:a] as the trigger signal.
  ffmpeg -hide_banner -loglevel error -y -i "$COMBINED" -stream_loop -1 -i "$AUDIO" -t "$DUR" \
    -filter_complex "
      [1:a]volume=0.55,afade=t=in:st=0:d=1.5,afade=t=out:st=$FADEOUT:d=3[bgmraw];
      [0:a]asplit=2[trig][orig];
      [bgmraw][trig]sidechaincompress=threshold=0.05:ratio=8:attack=20:release=400[bgmducked];
      [orig][bgmducked]amix=inputs=2:duration=first:dropout_transition=0:weights=1.3 0.9[aout]
    " \
    -map 0:v -map "[aout]" \
    -c:v copy -c:a aac -b:a 192k -shortest "$FINAL"
fi

ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_type,codec_name,width,height,r_frame_rate -of json "$FINAL"
echo "$FINAL"
