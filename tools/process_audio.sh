#!/usr/bin/env bash
# Procesa los WAV CC0 de assets/audio para que el mix sea predecible:
#
#   1. Alinea cada one-shot con su ataque: quita el silencio/ruido inicial
#      (regla: primer instante a menos de 12 dB del pico). magin.wav tenía
#      0.45 s de nada delante, así que sonaba medio segundo tarde respecto a la
#      animación; slide.wav tenía su golpe bueno a 0.4 s (modo "peak").
#   2. Iguala la loudness del ataque (primeros 250 ms) dentro de cada familia:
#      antes había hasta 27 dB entre variantes de disparo, así que cada disparo
#      sonaba a una distancia distinta.
#   3. Recorta la cola con fade: las colas largas se apilaban al disparar rápido
#      y enfangaban el mix.
#   4. Deja el pico por debajo de -1.5 dBFS para que la suma de capas no sature.
#
# Uso: tools/process_audio.sh [--dry-run]
# Requiere ffmpeg/ffprobe. Los originales se guardan en /tmp/audio_backup.
#
# Después de cambiar un WAV hay que reimportar el proyecto antes de ejecutarlo:
#   godot4 --headless --path . --editor --quit
# Un WAV sin importar hace fallar el preload del autoload de audio y el juego se
# queda sin sonido (y sin disparo: la señal sale antes de la balística).

set -euo pipefail

AUDIO_DIR="$(cd "$(dirname "$0")/.." && pwd)/assets/audio"
BACKUP_DIR="/tmp/audio_backup"
DRY_RUN="${1:-}"

SHOT_ATTACK_TARGET=-10.0   # dB de media en 0-250 ms
IMPACT_ATTACK_TARGET=-12.0
MECH_ATTACK_TARGET=-14.0
SOFT_ATTACK_TARGET=-16.0
PEAK_CEILING=-1.5          # dBFS

mkdir -p "$BACKUP_DIR"

# level <archivo> [ventana] -> media en dB (de la ventana o del archivo entero)
level() {
    local file="$1" window="${2:-}"
    local filter="volumedetect"
    [ -n "$window" ] && filter="atrim=0:${window},volumedetect"
    ffmpeg -hide_banner -i "$file" -af "$filter" -f null - 2>&1 \
        | grep -m1 mean_volume | awk '{print $(NF-1)}'
}

peak() {
    ffmpeg -hide_banner -i "$file" -af volumedetect -f null - 2>&1 \
        | grep -m1 max_volume | awk '{print $(NF-1)}'
}

duration_of() {
    ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"
}

# start_offset <archivo> <modo>
#   transient: instante en que el nivel sube por encima de (pico - 20 dB), menos
#              2 ms de margen. Es el modo que alinea sonidos percusivos
#              (disparos, impactos, clics) a su ataque REAL.
#   peak:      instante del pico de RMS, para un archivo cuyo golpe bueno no esta
#              al principio (slide.wav lo tiene a 0.4 s).
#
# Por que existe `transient`: el modo antiguo comparaba bloques de 20 ms de RMS
# contra el bloque mas fuerte con un margen de 12 dB. Un ruido de sala 30 dB por
# debajo del golpe no lo activaba, asi que el archivo se dejaba intacto y el
# evento sonaba tarde. Medido en los WAV que habia: impact_concrete tenia 54 ms
# de ruido de sala delante del golpe, empty_b 34 ms, y shot_1/shot_3 16 ms
# mientras shot_2/4/5 empezaban a 0 ms: dos de cada cinco disparos salian tarde.
#
# No se usa `astats` con reset pequeno para esto: su reset se queda en el tamano
# de frame (2048 muestras, ~46 ms), asi que la resolucion nunca baja de ahi.
# `silencedetect` si trabaja a nivel de muestra, y su umbral se fija relativo al
# pico del propio archivo, que es lo que hace falta.
start_offset() {
    local file="$1" mode="$2"
    if [ "$mode" = "peak" ]; then
        ffmpeg -hide_banner -i "$file" \
            -af "astats=metadata=1:reset=882,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-" \
            -f null - 2>/dev/null \
            | grep -E "pts_time|RMS_level" | paste - - \
            | awk 'BEGIN { best = -999; n = 0 }
                {
                    for (i = 1; i <= NF; i++) {
                        if ($i ~ /^pts_time:/) { gsub("pts_time:", "", $i); t = $i + 0 }
                        if ($i ~ /^lavfi\.astats\.Overall\.RMS_level=/) { split($i, a, "="); v = a[2] + 0 }
                    }
                    n++; times[n] = t; vals[n] = v
                    if (v > best) { best = v; bt = t }
                }
                END { s = bt - 0.012; printf "%.3f", (s > 0 ? s : 0) }'
        return
    fi
    local pk thr end
    pk="$(peak "$file")"
    thr="$(awk -v p="$pk" 'BEGIN { printf "%.1f", p - 20.0 }')"
    end="$(ffmpeg -hide_banner -i "$file" -af "silencedetect=noise=${thr}dB:d=0.002" -f null - 2>&1 \
        | grep -o 'silence_end: [0-9.]*' | head -1 | awk '{ print $2 }')"
    [ -z "$end" ] && end="0"
    awk -v e="$end" 'BEGIN { s = e - 0.002; printf "%.3f", (s > 0 ? s : 0) }'
}

# process <archivo> <ataque_objetivo> <duracion_max> <fade> <modo>
process() {
    local name="$1" target="$2" max_dur="$3" fade="$4" mode="$5"
    local file="$AUDIO_DIR/$name.wav"
    [ -f "$file" ] || { echo "  falta $name.wav"; return; }
    [ -f "$BACKUP_DIR/$name.wav" ] || cp "$file" "$BACKUP_DIR/$name.wav"

    local before_attack before_peak duration start
    before_attack="$(level "$file" 0.25)"
    before_peak="$(peak "$file")"
    duration="$(duration_of "$file")"
    start="$(start_offset "$BACKUP_DIR/$name.wav" "$mode")"

    # Pasada 1: recorte al ataque real.
    local tmp="$BACKUP_DIR/$name.trim.wav"
    ffmpeg -v error -y -i "$BACKUP_DIR/$name.wav" \
        -af "atrim=start=${start},asetpts=PTS-STARTPTS" \
        -ac 1 -ar 44100 -c:a pcm_s16le "$tmp"

    local trimmed_attack trimmed_duration gain keep fade_start
    trimmed_attack="$(level "$tmp" 0.25)"
    trimmed_duration="$(duration_of "$tmp")"
    gain="$(awk -v t="$target" -v a="$trimmed_attack" 'BEGIN { printf "%.2f", t - a }')"
    keep="$(awk -v d="$trimmed_duration" -v m="$max_dur" 'BEGIN { printf "%.3f", (d < m ? d : m) }')"
    fade_start="$(awk -v k="$keep" -v f="$fade" 'BEGIN { s = k - f; printf "%.3f", (s > 0 ? s : 0) }')"

    if [ "$DRY_RUN" = "--dry-run" ]; then
        printf "  %-16s dur=%-5.2f ataque=%-7s inicio=%-5s ataque_limpio=%-7s -> %s dB (%s dB) keep=%s\n" \
            "$name" "$duration" "$before_attack" "$start" "$trimmed_attack" "$target" "$gain" "$keep"
        return
    fi

    # Pasada 2: ganancia + recorte de cola + fade.
    local chain="volume=${gain}dB,atrim=0:${keep}"
    if awk -v f="$fade" 'BEGIN { exit !(f > 0) }'; then
        chain="$chain,afade=t=out:st=${fade_start}:d=${fade}"
    fi
    ffmpeg -v error -y -i "$tmp" -af "$chain" -ac 1 -ar 44100 -c:a pcm_s16le "$file"

    # Techo de pico: si la ganancia pasó el techo, se baja lo justo.
    # (El temporal necesita extensión .wav o ffmpeg no sabe el formato.)
    local after_peak
    after_peak="$(peak "$file")"
    if awk -v p="$after_peak" -v c="$PEAK_CEILING" 'BEGIN { exit !(p > c) }'; then
        local trim
        trim="$(awk -v p="$after_peak" -v c="$PEAK_CEILING" 'BEGIN { printf "%.2f", c - p }')"
        ffmpeg -v error -y -i "$file" -af "volume=${trim}dB" -ac 1 -ar 44100 -c:a pcm_s16le "$file.peak.wav"
        mv "$file.peak.wav" "$file"
    fi

    printf "  %-16s dur %5.2f -> %5.2f  ataque %6s -> %6s  pico %5s -> %5s  cola %s\n" \
        "$name" "$duration" "$(duration_of "$file")" \
        "$before_attack" "$(level "$file" 0.25)" "$before_peak" "$(peak "$file")" \
        "$(level "$file" 0.35)"
}

echo "== Disparos (misma loudness de ataque, cola corta) =="
for s in shot_1 shot_2 shot_3 shot_4 shot_5; do process "$s" "$SHOT_ATTACK_TARGET" 0.55 0.15 transient; done

echo "== Impactos =="
for s in impact_concrete impact_metal impact_wood ricochet; do process "$s" "$IMPACT_ATTACK_TARGET" 0.60 0.12 transient; done

echo "== Mecánica del arma =="
# slide.wav: su golpe bueno está a 0.4 s, así que se alinea al pico.
process slide "$MECH_ATTACK_TARGET" 0.18 0.05 peak
for s in empty_b magin magout; do process "$s" "$MECH_ATTACK_TARGET" 0.45 0.08 transient; done

echo "== Otros =="
for s in footstep shell_drop; do process "$s" "$SOFT_ATTACK_TARGET" 0.30 0.05 transient; done

echo "Listo. Originales en $BACKUP_DIR"
