#!/usr/bin/env bash
# captura.sh: captura frames REALES del juego para mirarlos.
#
#   tools/captura.sh downrange
#   tools/captura.sh empty --warmup=20 --total=14 --stride=3 --time-scale=0.2
#
# Los argumentos van en forma --clave=valor: Godot parte su
# get_cmdline_user_args() por espacios, asi que "--out X" llega como dos
# elementos y el parser lo ignora en silencio.
#
# Display por defecto :0 (GPU real del usuario). ESO ABRE VENTANA: es la unica
# forma de capturar a su resolucion. En :77 (Xvfb) no abre nada pero renderiza
# con llvmpipe.
set -u
cd "$(dirname "$0")/.."
ACTION="${1:-downrange}"; shift || true
DISP="${SHOT_DISPLAY:-:0}"
RES="${SHOT_RES:-1920x1080}"
OUT="captures/shot/$ACTION"
rm -rf "$OUT"; mkdir -p "$OUT"
DISPLAY="$DISP" timeout 900 godot4 --path . --resolution "$RES" tools/shot.tscn -- \
  "--action=$ACTION" "--out=$OUT" "$@" 2>&1 \
  | grep -E "^SHOT|^RANGE|^ARMA|SCRIPT ERROR|Parse Error" || true
echo "frames -> $OUT ($(ls "$OUT" 2>/dev/null | wc -l))"
