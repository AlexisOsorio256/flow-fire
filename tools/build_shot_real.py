#!/usr/bin/env python3
"""Corta los DISPAROS REALES de 9 mm de la biblioteca CC0 y escribe shot_*.wav.

FUENTE
------
"The Free Firearm Sound Effects Library" (Still North Media, 2013), licencia
CC0, recuperada via OpenGameArt y archive.org. Maestros crudos de una
**Walther PPQ 9 mm** grabada cerca del tirador a 192 kHz / 24 bits estereo.
URL, autor y licencia exactos en `downloads/AUDIO_SOURCES.md`; la procedencia
publicada, en `CREDITS_AUDIO.md`.

QUE SUSTITUYE Y POR QUE
-----------------------
Antes `shot_1..5.wav` eran **el mismo archivo copiado cinco veces** (31.830
bytes identicos los cinco) y salian de un montaje por sintesis sobre un corte
prestado (`tools/build_shot.py`, retirado). El resultado se percibia como arma
de juguete. Aqui NO se sintetiza ni se mezcla nada: se recorta la grabacion.

COMO SE SEPARA UN DISPARO DE UN CLIC
------------------------------------
El material de un arma trae disparos Y mecanica (cargador, corredera, gatillo).
Cortar por "hay un transitorio" mete clics como si fueran tiros. La medida que
los separa es el FACTOR DE CRESTA sobre la propia toma: un disparo de 9 mm
tiene ataque abrupto pero tambien cuerpo (cresta 27-31 dB medidos), mientras un
clic de acero es todo pico y nada de media (32-34 dB medidos). Se acepta por
debajo de 31.0 dB.

Cada toma se corta con 2 ms de pre-roll (no perder el ataque) y 420 ms de cola:
el estampido de una 9 mm en interior no dura mas, y la cola larga la pone la
reverberacion del bus Range, no el WAV.

Uso:
    python3 tools/build_shot_real.py
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "assets" / "audio"
SOURCE_DIR = REPO / "downloads" / "audio" / "oga_raw_walther_ppq_9mm"
SR = 48000
PRE_ROLL_S = 0.002
TAIL_S = 0.42
FADE_S = 0.025
CEILING_DB = -1.0
ONSET = 0.30
# Frontera medida: disparos 27,5-30,6 dB; clics 32-34 dB.
MAX_CREST_DB = 31.0
# Un disparo tiene que ser FUERTE. Sin esta puerta el ruido de fondo de la sala
# (que tambien tiene cresta baja) entraba como si fuera un tiro: la primera
# pasada acepto 54 tomas de 31 ficheros, que es imposible.
MIN_PEAK = 0.90
TARGET_SHOTS = 5


def decode(path: Path) -> np.ndarray:
    p = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
        capture_output=True, check=True)
    return np.frombuffer(p.stdout, dtype=np.float32).astype(np.float64)


def save(path: Path, x: np.ndarray) -> None:
    x = np.clip(x, -1.0, 1.0)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1",
         "-i", "-", "-c:a", "pcm_s16le", str(path), "-y"],
        input=(x * 32767.0).astype(np.int16).tobytes(), capture_output=True, check=True)


def onsets(x: np.ndarray) -> list[int]:
    step = SR // 200
    env = np.array([np.abs(x[i:i + step]).max() for i in range(0, len(x) - step, step)])
    loud = env >= ONSET
    rising = np.flatnonzero(np.diff(loud.astype(np.int8)) == 1)
    found = [int(s * step + step) for s in rising]
    if len(env) and loud[0]:
        found.insert(0, 0)
    dedup: list[int] = []
    for index in found:
        if not dedup or index - dedup[-1] > int(0.10 * SR):
            dedup.append(index)
    return dedup


def crest_db(x: np.ndarray) -> float:
    return (20.0 * np.log10(np.abs(x).max() + 1e-12)
            - 20.0 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12))


def low_share(x: np.ndarray, n: int = 2048, hop: int = 512) -> float:
    window = np.hanning(n)
    freq = np.fft.rfftfreq(n, 1.0 / SR)
    num = den = 0.0
    for i in range(0, max(1, len(x) - n), hop):
        power = np.abs(np.fft.rfft(x[i:i + n] * window)) ** 2
        num += power[freq < 150.0].sum()
        den += power.sum()
    return 100.0 * num / max(den, 1e-12)


def main() -> int:
    accepted: list[tuple[float, np.ndarray, str]] = []
    rejected = 0
    for master in sorted(SOURCE_DIR.glob("X_*.wav")):
        x = decode(master)
        for index in onsets(x):
            # El detector da el flanco de subida de la ENVOLVENTE (bloques de
            # 5 ms), asi que el pico real cae unas decenas de ms despues. Se
            # re-ancla en el maximo absoluto de la ventana: asi el ataque queda
            # pegado al inicio del WAV (medido antes: con el ancla de envolvente
            # el pico caia a 20-40 ms y el tiro sonaba blando).
            search_lo = max(0, index - int(PRE_ROLL_S * SR))
            search_hi = min(len(x), index + int(0.06 * SR))
            anchor = search_lo + int(np.argmax(np.abs(x[search_lo:search_hi]))) if search_hi > search_lo else index
            start = max(0, anchor - int(0.0005 * SR))
            end = min(len(x), anchor + int(TAIL_S * SR))
            clip = x[start:end].copy()
            if len(clip) < int(0.30 * SR):
                continue
            crest = crest_db(clip)
            if crest > MAX_CREST_DB or float(np.abs(clip).max()) < MIN_PEAK:
                rejected += 1
                continue
            accepted.append((crest, clip, master.name))

    print("tomas aceptadas=%d  clics descartados=%d" % (len(accepted), rejected))
    if len(accepted) < 3:
        print("ERROR: menos de 3 disparos reales", file=sys.stderr)
        return 1

    # Diversidad: UNA toma por fichero. Varias tomas del mismo maestro son el
    # mismo disparo repetido, y un pool con el mismo tiro cinco veces vuelve a
    # sonar a sample unico aunque cada WAV sea distinto.
    by_file: dict[str, tuple[float, np.ndarray]] = {}
    for crest, clip, name in accepted:
        best = by_file.get(name)
        if best is None or crest < best[0]:
            by_file[name] = (crest, clip)
    # Ordenar por factor de cresta: las de mas cuerpo primero, que son las que
    # mejor venden el golpe de presion.
    chosen = sorted(by_file.values(), key=lambda pair: pair[0])[:TARGET_SHOTS]
    length = max(len(clip) for _, clip in chosen)
    for i, (crest, clip) in enumerate(chosen):
        padded = np.zeros(length)
        padded[:len(clip)] = clip
        padded *= 10.0 ** (CEILING_DB / 20.0) / max(np.abs(padded).max(), 1e-9)
        fade = min(int(FADE_S * SR), length)
        padded[-fade:] *= np.linspace(1.0, 0.0, fade)
        save(OUT / ("shot_%d.wav" % (i + 1)), padded)
        head = padded[:int(0.004 * SR)]
        print("shot_%d.wav  %.0f ms  cresta %.1fdB  grave %.1f%%  pico_en=%d ms"
              % (i + 1, length / SR * 1000.0, crest_db(padded), low_share(padded),
                 int(np.argmax(np.abs(padded)) / SR * 1000.0)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
