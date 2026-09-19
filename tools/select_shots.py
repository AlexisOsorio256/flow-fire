#!/usr/bin/env python3
"""Elige los DISPAROS reales dentro del set mecanico del PPQ 9 mm (CC0).

El set X_0..X_28 trae de todo (cargador, corredera, gatillo, disparos), asi que
no vale cortar por "hay un transitorio": hay que separar un DISPARO de un CLIC
mecanico con una medida. Un disparo de 9 mm tiene ataque abrupto y COLA LARGA
(el estampido se deshace en el aire); un clic de acero es ataque abrupto y cola
corta. La medida es la energia que queda 120-300 ms despues del pico,
normalizada contra la energia del propio ataque.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[1]
SRC = REPO / "downloads" / "audio" / "oga_raw_walther_ppq_9mm"
SR = 48000
ONSET = 0.30
# Energia RMS de la ventana 120-320 ms despues del pico contra la del ataque
# (0-25 ms). Un disparo de 9 mm en interior supera 0.02 de sobra; un clic de
# corredera se queda una o dos decadas por debajo.
TAIL_MIN = 0.020


def decode(path: Path) -> np.ndarray:
    p = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
        capture_output=True, check=True)
    return np.frombuffer(p.stdout, dtype=np.float32).astype(np.float64)


def candidates(x: np.ndarray):
    step = SR // 200
    env = np.array([np.abs(x[i:i + step]).max() for i in range(0, len(x) - step, step)])
    loud = env >= ONSET
    rising = np.flatnonzero(np.diff(loud.astype(np.int8)) == 1)
    idx = [int(s * step + step) for s in rising]
    if len(env) and loud[0]:
        idx.insert(0, 0)
    out = []
    for i in idx:
        if out and i - out[-1] < int(0.10 * SR):
            continue
        out.append(i)
    return out


def tail_ratio(x: np.ndarray, peak: int) -> float:
    attack = x[peak:peak + int(0.025 * SR)]
    tail = x[peak + int(0.120 * SR):peak + int(0.320 * SR)]
    a = float(np.sqrt((attack ** 2).mean())) if len(attack) else 0.0
    t = float(np.sqrt((tail ** 2).mean())) if len(tail) else 0.0
    return t / max(a, 1e-12)


def main() -> int:
    rows = []
    for path in sorted(SRC.glob("X_*.wav")):
        x = decode(path)
        for peak in candidates(x):
            ratio = tail_ratio(x, peak)
            rows.append((ratio, path.name, peak / SR, float(np.abs(x[peak:peak + int(0.05 * SR)]).max())))
    rows.sort(reverse=True)
    print("ratio_cola  fichero    t(s)    pico_ataque")
    for ratio, name, t, peak in rows[:14]:
        mark = "DISPARO" if ratio >= TAIL_MIN else "   clic"
        print("%s %9.4f  %-9s %6.3f  %.3f" % (mark, ratio, name, t, peak))
    shots = [r for r in rows if r[0] >= TAIL_MIN]
    print("\ncandidatos a disparo: %d" % len(shots))
    return 0 if len(shots) >= 3 else 1


if __name__ == "__main__":
    sys.exit(main())
