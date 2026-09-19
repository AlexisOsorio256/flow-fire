#!/usr/bin/env python3
"""Reconstruye los SEIS WAV de impacto de `assets/audio/` desde sus fuentes.

Por que existe: los impactos NO son foley heredada congelada. Cada uno sale de
una grabacion concreta (Sonniss #GameAudioGDC / Freesound CC0) cortada a mano en
su transitorio real, y esa receta tiene que ser reproducible y auditable: si
alguien cambia un WAV a mano, se vuelve a ejecutar esto y se sabe de donde sale
cada muestra. Las fuentes crudas viven en `downloads/` (gitignored) y sus URLs y
licencias estan en `CREDITS_AUDIO.md`.

Que hace con cada receta, en este orden:
  1. Decodifica la fuente a mono 44,1 kHz float con ffmpeg (acepta wav/mp3/flac).
  2. Alinea el ATAQUE: busca el primer tramo de 1 ms que esta a menos de 3 dB del
     maximo de la envolvente (`mode: peak3`) o usa un inicio explicito en segundos
     (`mode: explicit`) y deja el ataque a `pre_roll_ms` del comienzo.
  3. Recorta a `max_ms` y aplica un fade de salida de `fade_ms`.
  4. Quita el offset DC.
  5. Normaliza el PICO a `PEAK_TARGET_DBFS` (-1,2 dBFS), igual que los cinco
     `shot_*.wav`. Aqui NO se normaliza por media de ventana: la familia de
     impactos tiene factores de cresta de 13 a 28 dB (un "tick" seco de pladur y
     un zumbido de ricochet no pueden compartir pico Y media), y forzar la media
     obligaba a bajar el pico hasta 14 dB por debajo del techo y dejaba la
     familia descompensada. Con el pico fijo, el equilibrio perceptual se ajusta
     en la tabla `SOUNDS` de `scripts/GameAudio.gd`, que es donde vive la mezcla.
  6. Escribe PCM 16 bits mono 44,1 kHz.

NO hace EQ ni pitch-shift. Un material no se deriva de otro: si un impacto
necesita EQ para sonar a su material, la fuente es la equivocada y hay que
cambiarla por otra grabacion.

Uso:
    python3 tools/build_impacts.py                 # reconstruye los seis
    python3 tools/build_impacts.py --dry-run       # solo plan + medidas
    python3 tools/build_impacts.py --only impact_wood
    python3 tools/build_impacts.py --json informe.json
"""

import argparse
import json
import math
import os
import struct
import subprocess
import sys
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_DIR = os.path.join(ROOT, "assets", "audio")
DL = os.path.join(ROOT, "downloads")

# --- Normalizacion -----------------------------------------------------------
#
# Pico fijo para toda la familia: mismo techo que los `shot_*.wav`, asi que
# ningun impacto puede recortar y el reparto de niveles se decide en un solo
# sitio (`SOUNDS` en scripts/GameAudio.gd).
PEAK_TARGET_DBFS = -1.2
# Ventanas de ataque que se MIDEN (no se normalizan) para poder comparar la
# loudness percibida de la familia y compensarla en la tabla de mezcla.
ATTACK_WINDOWS_S = (0.04, 0.25)

# --- Recetas -----------------------------------------------------------------
#
# `src` es relativo a la raiz del repo. `mode`:
#   peak3    -> el ataque se detecta solo (primer tramo de 1 ms a <3 dB del pico
#               de la envolvente). Es el modo correcto cuando la grabacion trae
#               silencio o un riser delante del golpe.
#   explicit -> el ataque se corta en `start_s` (medido a mano sobre la
#               envolvente). Necesario cuando la fuente es una textura con varios
#               golpes y hay que elegir UNO.
#
# `what` es la descripcion HONESTA que va a CREDITS_AUDIO.md: que es realmente
# la fuente (bala real / proyectil real / foley de objeto golpeando el material).
RECIPES = {
    "impact_metal": {
        "src": "downloads/impacts_raw/gm_bullet_impact_metal_heavy_08.wav",
        "mode": "peak3",
        "pre_roll_ms": 2.0,
        "max_ms": 260.0,
        "fade_ms": 60.0,
        "what": "impacto de BALA REAL sobre placa de metal pesada",
    },
    "impact_concrete": {
        "src": "downloads/impacts_raw/gm_bullet_impact_concrete_brick_01.wav",
        "mode": "peak3",
        "pre_roll_ms": 2.0,
        "max_ms": 220.0,
        "fade_ms": 50.0,
        "what": "impacto de BALA REAL sobre ladrillo/hormigon",
    },
    "impact_aluminum": {
        "src": "downloads/impacts_raw/sonniss2019_air_sheet_metal_20gauge_complex.wav",
        # La fuente es una textura de chapa fina golpeada; el golpe elegido esta
        # a 1,690 s (medido con la envolvente de 1 ms).
        "mode": "explicit",
        "start_s": 1.688,
        "pre_roll_ms": 0.0,
        "max_ms": 160.0,
        "fade_ms": 45.0,
        "what": "FOLEY: chapa FINA (calibre 20) golpeada. La libreria no documenta la aleacion",
    },
    "impact_wood": {
        "src": "downloads/impacts_raw/sonniss2017_dt_wood_impact_soft_short_crack.wav",
        # El PRIMER crack de la toma (a ~11 ms). Cortar solo ese golpe y no la
        # toma entera baja el centroide de 2,7 kHz a 1,6 kHz: los cracks 2 y 3
        # (a 331 ms) son mas agudos y alargaban el corte hacia pladur.
        "mode": "peak3",
        "pre_roll_ms": 2.0,
        "max_ms": 100.0,
        "fade_ms": 30.0,
        "what": "FOLEY: tabla de madera golpeada/partida (crack seco)",
    },
    "impact_drywall": {
        "src": "downloads/audio/impact_arrow_in_something_thin_Sadiquecat.mp3",
        # Solo el pop de entrada; el desgarro de papel que sigue se corta a
        # 120 ms para que no se lea como una cola larga.
        "mode": "peak3",
        "pre_roll_ms": 2.0,
        "max_ms": 120.0,
        "fade_ms": 35.0,
        "what": "PROYECTIL REAL: flecha disparada contra un panel fino",
    },
    "ricochet": {
        "src": "downloads/audio/impact_bullet_ricochet_aust_paul.mp3",
        # El primer rebote (barrido Doppler de ~500 ms). El segundo empieza a 992 ms.
        "mode": "peak3",
        "pre_roll_ms": 2.0,
        "max_ms": 700.0,
        "fade_ms": 120.0,
        "what": "RICHOCHET de BALA REAL con barrido Doppler",
    },
}


def decode_mono(path, rate=44100):
    """Decodifica cualquier formato a float mono con ffmpeg (sin ficheros temporales)."""
    proc = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-acodec", "pcm_s16le",
         "-ac", "1", "-ar", str(rate), "-"],
        capture_output=True, check=True)
    n = len(proc.stdout) // 2
    return [v / 32768.0 for v in struct.unpack("<%dh" % n, proc.stdout[: n * 2])], rate


def db(x):
    return 20.0 * math.log10(x) if x > 1e-12 else -240.0


def envelope_1ms(samples, rate):
    n = max(1, int(round(rate / 1000.0)))
    out = []
    for i in range(0, len(samples) - n + 1, n):
        s = 0.0
        for v in samples[i:i + n]:
            s += v * v
        out.append(math.sqrt(s / n))
    return out


def peak3_onset(samples, rate):
    """Indice de muestra del primer tramo de 1 ms a menos de 3 dB del pico."""
    env = envelope_1ms(samples, rate)
    if not env:
        return 0
    top = max(env)
    if top <= 0.0:
        return 0
    thr = top * (10.0 ** (-3.0 / 20.0))
    step = max(1, int(round(rate / 1000.0)))
    for i, v in enumerate(env):
        if v >= thr:
            return i * step
    return 0


def attack_mean_dbfs(samples, rate, window):
    n = min(len(samples), int(window * rate))
    if n <= 0:
        return -240.0
    s = sum(v * v for v in samples[:n])
    return db(math.sqrt(s / n))


def process(name, recipe, dry_run=False):
    src = os.path.join(ROOT, recipe["src"])
    if not os.path.exists(src):
        raise FileNotFoundError("falta la fuente de %s: %s" % (name, recipe["src"]))
    samples, rate = decode_mono(src)

    if recipe["mode"] == "explicit":
        start = int(round(float(recipe["start_s"]) * rate))
    elif recipe["mode"] == "peak3":
        start = peak3_onset(samples, rate)
    else:
        raise ValueError("modo desconocido: %s" % recipe["mode"])
    start = max(0, start - int(round(float(recipe.get("pre_roll_ms", 0.0)) / 1000.0 * rate)))

    keep = int(round(float(recipe["max_ms"]) / 1000.0 * rate))
    seg = samples[start:start + keep]

    # Fade de salida: cierra el corte sin escalon.
    fade = int(round(float(recipe["fade_ms"]) / 1000.0 * rate))
    fade = min(fade, len(seg))
    if fade > 0:
        for i in range(fade):
            seg[len(seg) - fade + i] *= 0.5 * (1.0 + math.cos(math.pi * (i + 1) / fade))

    # Offset DC.
    if seg:
        dc = sum(seg) / len(seg)
        seg = [v - dc for v in seg]

    pre_peak = max((abs(v) for v in seg), default=0.0)
    gain = PEAK_TARGET_DBFS - db(pre_peak)
    scaled = [v * (10.0 ** (gain / 20.0)) for v in seg]

    info = {
        "name": name,
        "source": recipe["src"],
        "what": recipe["what"],
        "start_s": round(start / float(rate), 4),
        "duration_s": round(len(scaled) / float(rate), 4),
        "source_peak_dbfs": round(db(pre_peak), 2),
        "gain_db": round(gain, 2),
        "peak_dbfs": round(db(max((abs(v) for v in scaled), default=0.0)), 2),
    }
    for w in ATTACK_WINDOWS_S:
        info["attack_%dms_dbfs" % int(w * 1000)] = round(attack_mean_dbfs(scaled, rate, w), 2)
    if dry_run:
        return info, None
    out = os.path.join(AUDIO_DIR, name + ".wav")
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack("<%dh" % len(scaled),
                                  *[max(-32768, min(32767, int(round(v * 32767.0)))) for v in scaled]))
    return info, out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--only", help="reconstruye solo este nombre")
    ap.add_argument("--json", help="escribe el informe de procesado en este fichero")
    args = ap.parse_args()

    names = [args.only] if args.only else list(RECIPES)
    for n in names:
        if n not in RECIPES:
            print("receta desconocida: %s" % n, file=sys.stderr)
            return 2

    report = []
    for n in names:
        try:
            info, out = process(n, RECIPES[n], args.dry_run)
        except Exception as exc:
            print("%-18s ERROR %s" % (n, exc), file=sys.stderr)
            return 1
        report.append(info)
        print("%-18s %-46s inicio %6.3f s  dur %5.3f s  ganancia %+6.2f dB  "
              "pico %6.2f dBFS  ataque(40/250 ms) %6.2f / %6.2f dBFS"
              % (n, info["source"].split("/")[-1], info["start_s"], info["duration_s"],
                 info["gain_db"], info["peak_dbfs"],
                 info["attack_40ms_dbfs"], info["attack_250ms_dbfs"]))
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(report, fh, indent=2, ensure_ascii=False)
        print("informe ->", args.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
