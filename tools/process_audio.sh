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
#   lead: primer instante audible comparado con el pico (quita silencio inicial)
#   peak: instante del pico de RMS (alinea el golpe a t=0)
start_offset() {
    ffmpeg -hide_banner -i "$1" \
        -af "astats=metadata=1:reset=882,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-" \
        -f null - 2>/dev/null \
        | grep -E "pts_time|RMS_level" | paste - - \
        | awk -v mode="$2" 'BEGIN { best = -999; n = 0 }
            {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^pts_time:/) { gsub("pts_time:", "", $i); t = $i + 0 }
                    if ($i ~ /^lavfi\.astats\.Overall\.RMS_level=/) { split($i, a, "="); v = a[2] + 0 }
                }
                n++; times[n] = t; vals[n] = v
                if (v > best) { best = v; bt = t }
            }
            END {
                if (mode == "peak") { s = bt - 0.012; printf "%.3f", (s > 0 ? s : 0); exit }
                thr = best - 12.0
                for (i = 1; i <= n; i++) {
                    if (vals[i] >= thr) { s = times[i] - 0.010; printf "%.3f", (s > 0 ? s : 0); exit }
                }
                printf "0.000"
            }'
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
for s in shot_1 shot_2 shot_3 shot_4 shot_5; do process "$s" "$SHOT_ATTACK_TARGET" 0.55 0.15 lead; done

echo "== Impactos =="
for s in impact_concrete impact_metal impact_wood ricochet; do process "$s" "$IMPACT_ATTACK_TARGET" 0.60 0.12 lead; done

echo "== Mecánica del arma =="
# slide.wav: su golpe bueno está a 0.4 s, así que se alinea al pico.
process slide "$MECH_ATTACK_TARGET" 0.18 0.05 peak
for s in empty_b magin magout; do process "$s" "$MECH_ATTACK_TARGET" 0.45 0.08 lead; done

echo "== Otros =="
for s in footstep shell_drop; do process "$s" "$SOFT_ATTACK_TARGET" 0.30 0.05 lead; done

echo "Listo. Originales en $BACKUP_DIR"
