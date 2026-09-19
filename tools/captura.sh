#!/usr/bin/env bash
# captura.sh: captura frames REALES del juego para mirarlos.
#
#   tools/captura.sh downrange
#   tools/captura.sh empty --warmup=20 --total=14 --stride=3 --time-scale=0.2
#   tools/captura.sh evidencia     <- TODA la lista de evidencia, de una vez
#
# Los argumentos van en forma --clave=valor: Godot parte su
# get_cmdline_user_args() por espacios, asi que "--out X" llega como dos
# elementos y el parser lo ignora en silencio.
#
# `SHOT_OUT=... tools/captura.sh accion` escribe en otra carpeta. Hace falta para
# capturar la MISMA accion dos veces con parametros distintos (disparo normal y
# disparo a camara lenta), que es lo que pide la lista de evidencia.
#
# Display por defecto :0 (GPU real del usuario). ESO ABRE VENTANA: es la unica
# forma de capturar a su resolucion. En :77 (Xvfb) no abre nada pero renderiza
# con llvmpipe.
set -u
cd "$(dirname "$0")/.."
ACTION="${1:-downrange}"; shift || true
DISP="${SHOT_DISPLAY:-:0}"
RES="${SHOT_RES:-1920x1080}"

run() {
  local action="$1"; shift
  local out="${SHOT_OUT:-captures/shot/$action}"
  rm -rf "$out"; mkdir -p "$out"
  DISPLAY="$DISP" timeout 1800 godot4 --path . --resolution "$RES" tools/shot.tscn -- \
    "--action=$action" "--out=$out" "$@" 2>&1 \
    | grep -E "^SHOT|^RANGE|^ARMA|SCRIPT ERROR|Parse Error" || true
  echo "frames -> $out ($(ls "$out" 2>/dev/null | wc -l))"
}

# LA LISTA DE EVIDENCIA COMPLETA, en un solo comando. No es una comodidad: es la
# diferencia entre "el asset se exporto" y "mire lo que dibuja el juego". Cada
# entrada esta aqui porque hubo una pasada que declaro algo sin mirarlo.
if [ "$ACTION" = "evidencia" ]; then
  run downrange --warmup=40 --total=2                                  # HIP
  run ads       --warmup=40 --total=2                                  # ADS
  run fire      --warmup=40 --total=48 --stride=2 --time-scale=1.0     # disparo normal
  # En SUBSHELL: `SHOT_OUT=x run ...` sobre una funcion deja la variable puesta
  # en el shell actual y la siguiente accion escribiria en la carpeta equivocada.
  ( SHOT_OUT=captures/shot/fire_slow \
    run fire    --warmup=40 --total=8  --time-scale=0.06 )             # fogonazo/humo/casquillo
  run empty     --warmup=20 --total=24 --stride=6 --time-scale=1.0     # ultimo tiro, bloqueo
  run reload    --warmup=40 --total=140 --stride=7 --time-scale=1.0    # recarga
  run reload_empty --warmup=40 --total=150 --stride=8 --time-scale=1.0 # recarga en seco
  run inspect   --warmup=40 --total=126 --stride=6 --time-scale=1.0    # recamara
  run steel     --warmup=40 --total=18 --stride=3 --time-scale=0.5     # impactos por material
  run aluminum  --warmup=40 --total=18 --stride=3 --time-scale=0.5
  run wood      --warmup=40 --total=18 --stride=3 --time-scale=0.5
  run drywall   --warmup=40 --total=18 --stride=3 --time-scale=0.5
  echo
  echo "Ahora MIRALAS. Una captura que nadie abre no es evidencia."
  exit 0
fi

run "$ACTION" "$@"
