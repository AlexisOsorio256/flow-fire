#!/usr/bin/env bash
# Procesa los WAV de assets/audio para que el mix sea predecible:
#
#   1. Alinea cada one-shot con su ataque real (ver `start_offset`).
#   2. Iguala la loudness del ataque (primeros 250 ms) dentro de cada familia:
#      antes había hasta 27 dB entre variantes de disparo, así que cada disparo
#      sonaba a una distancia distinta.
#   3. Deja el pico por debajo del techo.
#
# OJO: los cinco `shot_*.wav` NO pasan por aquí. Los corta
# `tools/build_shot_real.py` de una grabación real y ya fija su pico; volver a
# normalizarlos los desharía.
#
# OJO: los seis de impacto (`impact_*.wav`, `ricochet.wav`) tampoco. Los corta
# `tools/build_impacts.py`, cada uno de una grabación distinta, y se normalizan
# por PICO (no por media) porque su factor de cresta va de 14 a 29 dB. Aquí no
# se tocan.
#
# Uso: tools/process_audio.sh [--dry-run]
# Requiere ffmpeg/ffprobe.
#
# Los masters con licencia versionada viven en `assets/audio/source/` (PCM
# canonico 96 kHz / 16 bits: el editor de Godot NO importa WAV extensibles ni
# de 24 bits y los marca como error). Los cortes reproducibles (`shot_*`,
# `magin`, `magout`) salen siempre de ahi; el resto de la foley heredada esta
# congelada en sus WAV versionados (ver `process`).
#
# OJO: los tres WAV de foley del arma (`mag_drop`, `slide_release`,
# `mag_insert`) NO salen de los masters: son
# síntesis y los genera `tools/make_weapon_sounds.py`. Este script no los toca;
# si hay que cambiarlos, se cambian en el generador y se vuelve a ejecutar.
#
# Después de cambiar un WAV hay que reimportar el proyecto antes de ejecutarlo:
#   godot4 --headless --path . --editor --quit
# Un WAV sin importar hace fallar el preload del autoload de audio y el juego se
# queda sin sonido (y sin disparo: la señal sale antes de la balística).

set -euo pipefail

AUDIO_DIR="$(cd "$(dirname "$0")/.." && pwd)/assets/audio"
BACKUP_DIR="/tmp/audio_backup"
DRY_RUN="${1:-}"

IMPACT_ATTACK_TARGET=-12.0
MECH_ATTACK_TARGET=-14.0
SOFT_ATTACK_TARGET=-16.0
# Los disparos se recortan a su ataque y se suben hasta este techo. Antes el
# techo era -1.5 dBFS pero la ganancia se calculaba sobre una media de 250 ms
# que en shot_4/shot_5 medía material ANTERIOR al disparo: el "ataque" acababa
# en 0 dBFS y las muestras salían recortadas (86 muestras al ras en shot_2).
PEAK_CEILING=-1.5          # dBFS

# --- Forma del corte del disparo ---
#
# Aquí se hundía a -7 dB todo lo que venía después del estampido, desde los
# 25 ms, y luego a -3 dB. Las dos rampas sobraban: el corte ya termina dentro
# del hueco entre disparos, y el peso y la cola los pone la grabación original
# (que trae el estampido entero, no un recorte de 160 ms). Lo único que queda
# aquí es un fade corto para que el corte no acabe en un escalón.

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
#
# OJO: esta funcion SOLO trabaja desde el original guardado en $BACKUP_DIR y se
# NIEGA a adivinarlo: si falta el backup, avisa y salta el archivo (antes lo
# "respaldaba" del propio WAV procesado y una re-ejecucion lo procesaba DOS
# veces). Los originales de la foley heredada (Freesound) ya no existen como
# tales: sus WAV versionados SON los masters. Lo reproducible de verdad son los
# cortes con master versionado (`process_mag`, y los disparos en su propio builder).
process() {
    local name="$1" target="$2" max_dur="$3" fade="$4" mode="$5"
    local file="$AUDIO_DIR/$name.wav"
    [ -f "$file" ] || { echo "  falta $name.wav"; return; }
    if [ ! -f "$BACKUP_DIR/$name.wav" ]; then
        echo "  $name: sin original en $BACKUP_DIR, se salta (no se toca)"
        return
    fi

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

# Los cinco disparos NO se cortan aqui. Los construye
# `tools/build_shot_real.py` desde tomas reales de pistola con una cadena de
# dinamica/EQ (HPF, low-shelf y trim de ataque comun) y los mide
# `tools/measure_shots.py`. Antes este script tenia un `process_shot` que
# cortaba la rafaga de la Glock 18C de `assets/audio/source/`; ese maestro ya no
# existe y la funcion no se llamaba desde ningun sitio, asi que se retiro con su
# tabla `SHOT_CUTS`. Dejarla era documentar un camino que ya no produce nada.

# process_mag <nombre> <inicio> <fin> <pico_objetivo> <fade>
#
# Corta el cargador del extracto G36C (misma toma, mismo micro: pareja
# coherente) en su ataque real. A diferencia de `process`, normaliza por PICO
# y no por media de 250 ms: la extraccion es un evento disperso (clic +
# friccion en 180 ms) y la media alargaria +22 dB de ganancia bombeando el
# ruido de sala; el asiento es un golpe unico. Los objetivos conservan la
# dinamica natural (salir suena mas blando que asentar).
# Ventanas medidas con la envolvente de 1 ms sobre
# assets/audio/source/g36c_mag_in_out_excerpt.wav (recorte 11.28-11.70 s de la
# toma `..._mag_in_&_out.wav`; ciclo con 0 muestras al ras):
#   magout   0.105-0.210 clic del reten + friccion de extraccion (ataque a 0.110)
#   magin    0.210-0.400 insercion + asiento (el clack cae a 0.270, o sea ~60 ms
#            dentro de la muestra: Glock.gd dispara el evento 60 ms ANTES del
#            asiento para que el clack caiga en el contacto)
process_mag() {
    local name="$1" start="$2" stop="$3" peak_target="$4" fade="$5"
    local file="$AUDIO_DIR/$name.wav"
    local master="$AUDIO_DIR/source/g36c_mag_in_out_excerpt.wav"
    [ -f "$master" ] || { echo "  falta el extracto original: $master"; return; }
    [ -f "$file" ] && [ ! -f "$BACKUP_DIR/$name.wav" ] && cp "$file" "$BACKUP_DIR/$name.wav"

    local keep
    keep="$(awk -v s="$start" -v e="$stop" 'BEGIN { printf "%.3f", e - s }')"
    local tmp="$BACKUP_DIR/$name.trim.wav"
    ffmpeg -v error -y -i "$master" -af "atrim=start=${start}:end=${stop},asetpts=PTS-STARTPTS" \
        -ac 1 -ar 44100 -c:a pcm_s16le "$tmp"

    local raw_peak gain fade_start
    # Ojo: `peak` mide la global $file (el destino, aun sin escribir); aqui el
    # original es el temporal y se mide explicito.
    raw_peak="$(ffmpeg -hide_banner -i "$tmp" -af volumedetect -f null - 2>&1 | grep -m1 max_volume | awk '{print $(NF-1)}')"
    gain="$(awk -v t="$peak_target" -v p="$raw_peak" 'BEGIN { printf "%.2f", t - p }')"
    fade_start="$(awk -v k="$keep" -v f="$fade" 'BEGIN { s = k - f; printf "%.3f", (s > 0 ? s : 0) }')"

    if [ "$DRY_RUN" = "--dry-run" ]; then
        printf "  %-8s extracto %.3f..%.3f s  pico=%s dB  ganancia=%s dB\n" \
            "$name" "$start" "$stop" "$raw_peak" "$gain"
        return
    fi

    local chain="volume=${gain}dB,atrim=0:${keep},afade=t=out:st=${fade_start}:d=${fade}"
    ffmpeg -v error -y -i "$tmp" -af "$chain" -ac 1 -ar 44100 -c:a pcm_s16le "$file"

    local after_peak
    after_peak="$(peak "$file")"
    if awk -v p="$after_peak" -v c="$PEAK_CEILING" 'BEGIN { exit !(p > c) }'; then
        local trim
        trim="$(awk -v p="$after_peak" -v c="$PEAK_CEILING" 'BEGIN { printf "%.2f", c - p }')"
        ffmpeg -v error -y -i "$file" -af "volume=${trim}dB" -ac 1 -ar 44100 -c:a pcm_s16le "$file.peak.wav"
        mv "$file.peak.wav" "$file"
    fi

    printf "  %-8s extracto %.3f..%.3f s  pico %5s -> %5s\n" \
        "$name" "$start" "$stop" "$raw_peak" "$(peak "$file")"
}

echo "== Cargador (extracto G36C close-up, misma toma) =="
process_mag magout 0.105 0.210 -8.0 0.03
process_mag magin 0.210 0.400 -1.5 0.05

echo "== Disparos =="
# Los cinco disparos NO los toca este script. No son WAV de partida grabados
# aparte que haya que normalizar por familia: son CORTES de una grabacion real,
# y quien los corta es `tools/build_shot_real.py`, que ademas elige que
# transitorios son disparos y cuales son clics de mecanica (por factor de
# cresta) y les fija el pico a -1 dBFS. Volver a pasarlos por aqui los
# normalizaria dos veces y desharia esa seleccion.
#
# El montaje por sintesis sobre un corte prestado (`tools/build_shot.py`) se
# retiro: los cinco WAV que producia eran el mismo archivo copiado cinco veces.
echo "   (los cinco shot_*.wav los genera tools/build_shot_real.py; no se tocan)"

echo "== Impactos =="
# Los SEIS impactos los corta `tools/build_impacts.py` desde sus fuentes
# (Sonniss #GameAudioGDC y Freesound CC0), no desde $BACKUP_DIR: cada uno sale de
# una grabacion distinta y con una receta propia (inicio, cola y fade medidos).
# Este script ya no los toca. Normalizarlos aqui otra vez los desharía: `process`
# alinea a un ataque y una media comunes, y la familia de impactos tiene crestas
# de 14 a 29 dB, asi que la media comun los dejaba descompensados.
#
#   impact_metal / impact_concrete   impacto de bala real (Gamemaster Audio)
#   impact_aluminum                  chapa fina golpeada (Airborne Sound)
#   impact_wood                      tabla de madera partida (Double Trouble)
#   impact_drywall                   flecha real contra panel fino (Freesound CC0)
#   ricochet                         rebote de bala real con Doppler (Freesound CC0)
#
# Procedencia, autor y licencia de cada uno: CREDITS_AUDIO.md.
echo "   (los seis impact_*.wav y ricochet.wav los genera tools/build_impacts.py; no se tocan)"
echo "   (IMPORTANTE: antes impact_drywall copiaba el master de impact_concrete y"
echo "    impact_aluminum era un EQ de impact_metal; ya no.)"

echo "== Mecánica del arma =="
# Los dos golpes de la corredera son DOS eventos físicos distintos (tope trasero
# a ~12 ms y vuelta a batería a ~54 ms) y suenan distinto: el trasero es un
# chasquido de acero agudo y el de batería un golpe más sordo y con cuerpo. Antes
# los dos usaban slide.wav con distinto volumen y pitch, que es lo que hacía que
# el disparo se percibiera como BANG + otro golpe.
#
#   slide_rear.wav     Glock 19 real: pico -0.85 dBFS, 85% de energía >2,5 kHz.
#   slide_battery.wav  Sig P229 real: pico -9,82 dBFS, 75% de energía <800 Hz.
#
# Los dos vienen ya recortados a su ataque (ver CREDITS_AUDIO.md), así que se
# alinean por transitorio como el resto de la foley. Se igualan al mismo target
# de familia porque su reparto DENTRO del disparo lo fija GameAudio
# (slide_rear 2 dB por encima de slide_battery: ver su comentario medido).
for s in slide_rear slide_battery; do process "$s" "$MECH_ATTACK_TARGET" 0.12 0.05 transient; done
for s in empty_b trigger_reset; do process "$s" "$MECH_ATTACK_TARGET" 0.45 0.08 transient; done

echo "== Otros =="
for s in footstep shell_drop; do process "$s" "$SOFT_ATTACK_TARGET" 0.30 0.05 transient; done

echo "Listo. Originales en $BACKUP_DIR"
