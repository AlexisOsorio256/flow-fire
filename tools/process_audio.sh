#!/usr/bin/env bash
# Procesa los WAV de assets/audio para que el mix sea predecible:
#
#   1. Alinea cada one-shot con su ataque real (ver `start_offset`).
#   2. Iguala la loudness del ataque (primeros 250 ms) dentro de cada familia:
#      antes había hasta 27 dB entre variantes de disparo, así que cada disparo
#      sonaba a una distancia distinta.
#   3. Recorta la cola con fade: las colas largas se apilaban al disparar rápido
#      y enfangaban el mix.
#   4. Deja el pico por debajo del techo para que la suma de capas no sature.
#
# LOS 5 DISPAROS SE CORTAN DE LA GRABACIÓN ORIGINAL, no de recortes heredados.
# Ver `process_shot` y la tabla SHOT_CUTS: es la única forma de garantizar que
# cada variante empiece en su propio ataque y no contenga el disparo siguiente.
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
# Los disparos se recortan a su ataque y se suben hasta este techo. Antes el
# techo era -1.5 dBFS pero la ganancia se calculaba sobre una media de 250 ms
# que en shot_4/shot_5 medía material ANTERIOR al disparo: el "ataque" acababa
# en 0 dBFS y las muestras salían recortadas (86 muestras al ras en shot_2).
SHOT_PEAK_CEILING=-1.2
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

# envelope1ms <archivo> -> lineas "tiempo_segundos  nivel_dBFS_RMS(1 ms)"
# Lee el PCM crudo por stdout (sin filtros de ffmpeg cuyo reset este limitado al
# tamano de frame) y calcula la envolvente en awk muestra a muestra.
envelope1ms() {
    ffmpeg -v error -i "$1" -f s16le -acodec pcm_s16le -ac 1 -ar 44100 - \
        | awk -v n=44 '{
            for (i = 1; i <= NF; i++) {
                v = $i + 0
                s += v * v
                if (++c == n) {
                    printf "%.6f %.4f\n", idx / 44100.0, 10.0 * log(s / n + 1e-12) / log(10.0) - 90.31
                    idx++; s = 0; c = 0
                }
            }
        }'
}

# shot_window <archivo> <t_ataque> <tope_ms> -> "inicio fin" en segundos
#   inicio = t_ataque - 1 ms (margen para no comerse el primer flanco)
#   fin    = primer instante en que vuelve a entrar material fuerte DESPUES del
#            ataque, o el tope si no lo hay.
#
# Por que el fin no es simplemente el tope: los 6 disparos de la grabacion
# original son una rafaga real de Glock 18c (1100-1360 RPM), asi que los ultimos
# disparos tienen el SIGUIENTE disparo dentro de la misma ventana. Medido en la
# envolvente de 20 ms: tras el ataque el nivel cae monotonamente 25-35 dB y luego
# salta +15 dB de golpe. Ese salto es el disparo siguiente, no la cola del actual.
# Colarlo hacia que un solo clic del jugador sonara a dos disparos.
shot_window() {
    local file="$1" atk="$2" cap_ms="$3"
    envelope1ms "$file" | awk -v atk="$atk" -v cap="$cap_ms" -v sr=44100 '
        {
            # ventanas de 20 ms (20 tramas de 1 ms)
            acc += $2; n++
            if (n == 20) {
                t = $1
                w[++k] = t; lvl[k] = acc / 20.0; acc = 0; n = 0
            }
        }
        END {
            # ataque = ventana de 20 ms mas fuerte de los primeros 60 ms
            best = -999; bi = 0
            for (i = 1; i <= k; i++) {
                if (w[i] > atk + 0.060) break
                if (lvl[i] > best) { best = lvl[i]; bi = i }
            }
            s = atk - 0.001; if (s < 0) s = 0
            e = s + cap / 1000.0
            # primer salto sostenido hacia arriba tras el ataque
            for (i = bi + 2; i <= k - 2; i++) {
                if (lvl[i] - lvl[i - 1] >= 6.0 && lvl[i + 1] >= lvl[i] - 3.0 && lvl[i + 2] >= lvl[i] - 3.0) {
                    var = w[i] - 0.030
                    if (var < e) e = var
                    break
                }
            }
            printf "%.3f %.3f", s, e
        }'
}

# start_offset <archivo> <modo>
#   transient: primer instante en que la envolvente RMS de 1 ms supera
#              (pico de esa envolvente - 20 dB), menos 2 ms de margen. Es el
#              modo que alinea sonidos percusivos a su ataque REAL.
#   peak:      instante del pico de RMS, para un archivo cuyo golpe bueno no esta
#              al principio (slide.wav lo tiene a 0.4 s).
#
# Por que existe `transient`: el modo antiguo comparaba bloques de 20 ms de RMS
# contra el bloque mas fuerte con un margen de 12 dB. Un ruido de sala 30 dB por
# debajo del golpe no lo activaba, asi que el archivo se dejaba intacto y el
# evento sonaba tarde. Medido en los WAV que habia: impact_concrete tenia 54 ms de
# ruido de sala delante del golpe, empty_b 34 ms, y shot_1/shot_3 16 ms mientras
# shot_2/4/5 empezaban a 0 ms: dos de cada cinco disparos salian tarde.
#
# El umbral se mide sobre la ENVOLVENTE, no sobre el pico de muestra. Eso importa:
# un unico sample alto (o recortado) al principio del archivo hunde el umbral y el
# detector de silencio no ve nada. Ese fue justo el fallo de shot_2.wav.
#
# No se usa `astats` con reset pequeno para esto: su reset se queda en el tamano
# de frame (2048 muestras, ~46 ms), asi que la resolucion nunca baja de ahi.
# La envolvente se calcula en awk sobre las muestras crudas (ver `envelope1ms`).
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
    # transient: envolvente RMS de 1 ms, umbral = pico_envolvente - 20 dB.
    envelope1ms "$file" | awk -v thr=-20.0 '
        { t[NR] = $1; e[NR] = $2; if ($2 > pk) pk = $2 }
        END {
            lim = pk + thr
            for (i = 1; i <= NR; i++) {
                if (e[i] >= lim) { s = t[i] - 0.002; printf "%.3f", (s > 0 ? s : 0); exit }
            }
            print "0.000"
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

# process_shot <n> <t_ataque> <tope_ms> <fade>
#
# Corta el disparo `n` de la grabacion original en su ataque real, con la cola
# acotada al material que pertenece a ESE disparo, iguala su loudness de ataque
# con el resto de variantes y lo deja por debajo del techo.
#
# Por que no se reutiliza `process`: los shot_N.wav anteriores eran ventanas de
# 700 ms cortadas A MANO de esta misma rafaga, con offsets que no coincidian con
# ningun ataque. Medido: shot_2.wav empezaba 310 ms ANTES de su disparo, asi que
# el juego reproducia 310 ms de ruido de manejo y luego el estampido; shot_4 y
# shot_5 empezaban 39 y 44 ms antes. Un clic del jugador sonaba a dos eventos.
process_shot() {
    local n="$1" atk="$2" cap_ms="$3" fade="$4"
    local name="shot_$n"
    local file="$AUDIO_DIR/$name.wav"
    local master="$AUDIO_DIR/source/sonniss_gdc2016_glock18c_1m.wav"
    [ -f "$master" ] || { echo "  falta la grabacion original: $master"; return; }
    [ -f "$file" ] && [ ! -f "$BACKUP_DIR/$name.wav" ] && cp "$file" "$BACKUP_DIR/$name.wav"

    local win start stop
    win="$(shot_window "$master" "$atk" "$cap_ms")"
    start="$(echo "$win" | awk '{print $1}')"
    stop="$(echo "$win" | awk '{print $2}')"
    local keep
    keep="$(awk -v s="$start" -v e="$stop" 'BEGIN { printf "%.3f", e - s }')"

    local tmp="$BACKUP_DIR/$name.trim.wav"
    ffmpeg -v error -y -i "$master" -af "atrim=start=${start}:end=${stop},asetpts=PTS-STARTPTS" \
        -ac 1 -ar 44100 -c:a pcm_s16le "$tmp"

    local atk_rms gain fade_start
    atk_rms="$(level "$tmp" 0.25)"
    gain="$(awk -v t="$SHOT_ATTACK_TARGET" -v a="$atk_rms" 'BEGIN { printf "%.2f", t - a }')"
    fade_start="$(awk -v k="$keep" -v f="$fade" 'BEGIN { s = k - f; printf "%.3f", (s > 0 ? s : 0) }')"

    if [ "$DRY_RUN" = "--dry-run" ]; then
        printf "  %-8s maestro %.3f..%.3f s  keep=%.3f s  ataque=%s dB  ganancia=%s dB\n" \
            "$name" "$start" "$stop" "$keep" "$atk_rms" "$gain"
        return
    fi

    local chain="volume=${gain}dB,atrim=0:${keep}"
    if awk -v f="$fade" 'BEGIN { exit !(f > 0) }'; then
        chain="$chain,afade=t=out:st=${fade_start}:d=${fade}"
    fi
    ffmpeg -v error -y -i "$tmp" -af "$chain" -ac 1 -ar 44100 -c:a pcm_s16le "$file"

    # Techo de pico: si la ganancia lo paso, se baja lo justo y se comprueba que
    # no quede ninguna muestra al ras (recortada).
    local after_peak
    after_peak="$(peak "$file")"
    if awk -v p="$after_peak" -v c="$SHOT_PEAK_CEILING" 'BEGIN { exit !(p > c) }'; then
        local trim
        trim="$(awk -v p="$after_peak" -v c="$SHOT_PEAK_CEILING" 'BEGIN { printf "%.2f", c - p }')"
        ffmpeg -v error -y -i "$file" -af "volume=${trim}dB" -ac 1 -ar 44100 -c:a pcm_s16le "$file.peak.wav"
        mv "$file.peak.wav" "$file"
    fi

    printf "  %-8s maestro %.3f..%.3f s  dur %5.2f -> %5.2f  ataque %6s -> %6s  pico %5s -> %5s\n" \
        "$name" "$start" "$stop" "$cap_ms" "$(duration_of "$file")" \
        "$atk_rms" "$(level "$file" 0.25)" "$after_peak" "$(peak "$file")"
}

# Los 6 ataques de la grabacion original, medidos con la envolvente de 1 ms sobre
# assets/audio/source/sonniss_gdc2016_glock18c_1m.wav (ver CREDITS_AUDIO.md).
# El nombre del fichero de origen lo confirma: "...clean_Six_shots_x_1.wav".
#
# El tope de cada corte NO es estetico: es el hueco real hasta el disparo
# siguiente menos 35 ms de margen. La rafaga es 6 tiros a 1100-1360 RPM, asi que
# los tiros contiguos estan a 178-222 ms. Dejar la ventana mas larga que ese
# hueco mete el disparo vecino dentro de la muestra y un clic del jugador suena a
# dos disparos (era justo el defecto de los shot_N.wav anteriores).
#   n  t_ataque  hueco_al_siguiente  tope  fade
#   1  0.1190    222 ms              160   0.06
#   2  0.3410    439 ms              340   0.12
#   3  0.7800    206 ms              160   0.06
#   4  0.9860    178 ms              135   0.05
#   5  1.1640    183 ms              140   0.05
SHOT_CUTS=(
    "1 0.1190 160 0.06"
    "2 0.3410 340 0.12"
    "3 0.7800 160 0.06"
    "4 0.9860 135 0.05"
    "5 1.1640 140 0.05"
)

echo "== Disparos (cortados de la grabacion original en su ataque real) =="
for cut in "${SHOT_CUTS[@]}"; do process_shot $cut; done

echo "== Impactos =="
for s in impact_concrete impact_metal impact_wood ricochet; do process "$s" "$IMPACT_ATTACK_TARGET" 0.60 0.12 transient; done

echo "== Mecánica del arma =="
# slide.wav: su golpe bueno está a 0.4 s, así que se alinea al pico.
process slide "$MECH_ATTACK_TARGET" 0.18 0.05 peak
for s in empty_b magin magout; do process "$s" "$MECH_ATTACK_TARGET" 0.45 0.08 transient; done

echo "== Otros =="
for s in footstep shell_drop; do process "$s" "$SOFT_ATTACK_TARGET" 0.30 0.05 transient; done

echo "Listo. Originales en $BACKUP_DIR"
