#!/usr/bin/env bash
# Arma el material de revisión de la timeline: una hoja de contacto (PNG) con
# todos los frames y un vídeo mp4 a la velocidad de captura.
#
# Uso: tools/make_timeline_media.sh [capturas/timeline]
# Requiere ffmpeg e ImageMagick.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${1:-$ROOT/captures/timeline}"
OUT_DIR="$ROOT/captures"
FPS=10

[ -d "$DIR" ] || { echo "No existe $DIR: corre antes --timeline"; exit 1; }

montage "$DIR"/frame_*.png -tile 5x -geometry 300x158+3+3 -background '#101418' \
    "$OUT_DIR/timeline_contacto.png"
echo "contacto: $OUT_DIR/timeline_contacto.png"

ffmpeg -v error -y -framerate "$FPS" -i "$DIR/frame_%03d.png" \
    -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p "$OUT_DIR/timeline.mp4"
echo "vídeo:    $OUT_DIR/timeline.mp4"
