#!/usr/bin/env bash
# Template: Burn SRT subtitles into an existing mp4 (post-processing step).
#
# Usage:
#   IN=video.mp4 SRT=subs.srt OUT=video_subbed.mp4 ./burn_srt_subtitles.sh
#
# Optional env overrides:
#   SLIDESHOW_FONT=PingFang\ TC      font NAME (must be installed; see fc-list)
#   SUB_FONT_SIZE=22
#   SUB_OUTLINE=2
#   SUB_SHADOW=1
#   SUB_ALIGNMENT=2                  ASS alignment (2 = bottom-center)
#   SUB_MARGIN_V=40
#
# Requirements:
#   - ffmpeg built with libass (Homebrew default; verify with: ffmpeg -filters | grep subtitles)
#   - iconv + file (POSIX)
#   - A CJK font installed and visible to libass (PingFang TC on macOS by default).
#
# Failure modes are explicit (no silent fallback to drawtext/Pillow).
set -euo pipefail

IN="${IN:?Set IN=path/to/video.mp4}"
SRT="${SRT:?Set SRT=path/to/subs.srt}"
OUT="${OUT:-${IN%.mp4}_subbed.mp4}"

FONT_NAME="${SLIDESHOW_FONT:-PingFang TC}"
FONT_SIZE="${SUB_FONT_SIZE:-22}"
OUTLINE="${SUB_OUTLINE:-2}"
SHADOW="${SUB_SHADOW:-1}"
ALIGNMENT="${SUB_ALIGNMENT:-2}"
MARGIN_V="${SUB_MARGIN_V:-40}"

[[ -f "$IN" ]]  || { echo "IN file not found: $IN"   >&2; exit 1; }
[[ -f "$SRT" ]] || { echo "SRT file not found: $SRT" >&2; exit 1; }

# --- Preflight: libass / subtitles filter present? ---
if ! ffmpeg -hide_banner -filters 2>/dev/null | grep -qE '^[[:space:]]*[A-Z\.]+[[:space:]]+subtitles[[:space:]]'; then
  cat >&2 <<'EOM'
ERROR: this ffmpeg build lacks the 'subtitles' filter (libass).

Install / reinstall ffmpeg with libass:
  macOS:  brew reinstall ffmpeg
  Debian: sudo apt install ffmpeg libass-dev
  Other:  build ffmpeg with --enable-libass

This template intentionally does NOT fall back to drawtext or Pillow overlays —
the visual quality difference is large and silent fallback would be misleading.
EOM
  exit 2
fi

# --- Preflight: CJK font installed? ---
if command -v fc-list >/dev/null 2>&1; then
  if ! fc-list :lang=zh-tw | grep -qi -E "$(printf '%s' "$FONT_NAME" | sed 's/[][\\.*^$(){}|+?/]/\\&/g')"; then
    echo "WARN: font '$FONT_NAME' not found via fc-list. Subtitles may render as boxes (tofu)." >&2
    echo "      Install: brew install --cask font-noto-sans-cjk-tc   (or set SLIDESHOW_FONT=...)" >&2
  fi
fi

# --- Normalize SRT encoding to UTF-8 (no BOM) ---
TMPDIR_=$(mktemp -d -t srtburn.XXXXXX)
trap 'rm -rf "$TMPDIR_"' EXIT
CLEAN_SRT="$TMPDIR_/clean.srt"

detect_encoding() {
  local mime
  mime=$(file --mime-encoding -b "$1" 2>/dev/null | tr -d '\r\n' | tr '[:upper:]' '[:lower:]')
  case "$mime" in
    utf-8|us-ascii) echo "UTF-8" ;;
    utf-16le)       echo "UTF-16LE" ;;
    utf-16be)       echo "UTF-16BE" ;;
    iso-8859-1|unknown-8bit|binary) echo "BIG5" ;;  # best-effort guess for Windows zh-TW
    *)              echo "$mime" ;;
  esac
}

ENC=$(detect_encoding "$SRT")
echo "SRT detected encoding: $ENC" >&2

if [[ "$ENC" == "UTF-8" ]]; then
  cp "$SRT" "$CLEAN_SRT"
else
  if ! iconv -f "$ENC" -t UTF-8 "$SRT" > "$CLEAN_SRT" 2>/dev/null; then
    echo "ERROR: failed to convert SRT from $ENC to UTF-8. Re-save as UTF-8 manually." >&2
    exit 3
  fi
fi

# Strip UTF-8 BOM if present (libass tolerates it but some builds get cranky).
if head -c 3 "$CLEAN_SRT" | od -An -tx1 | tr -d ' \n' | grep -qi '^efbbbf'; then
  tail -c +4 "$CLEAN_SRT" > "$CLEAN_SRT.nobom" && mv "$CLEAN_SRT.nobom" "$CLEAN_SRT"
fi

# Sanity check: SRT contains '-->'
if ! grep -q -- '-->' "$CLEAN_SRT"; then
  echo "ERROR: '$SRT' does not look like a valid SRT (no '-->' arrow found after decode)." >&2
  exit 4
fi

# --- Burn subtitles ---
# Note: subtitles filter requires the SRT path inline. Quote with ':' carefully.
STYLE="FontName=${FONT_NAME},Fontsize=${FONT_SIZE},Outline=${OUTLINE},Shadow=${SHADOW},Alignment=${ALIGNMENT},MarginV=${MARGIN_V},BorderStyle=1"

ffmpeg -hide_banner -loglevel error -y -i "$IN" \
  -vf "subtitles='${CLEAN_SRT}':force_style='${STYLE}'" \
  -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p \
  -c:a copy \
  "$OUT"

ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_type,codec_name,width,height -of json "$OUT"
echo "$OUT"
