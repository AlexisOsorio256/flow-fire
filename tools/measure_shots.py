#!/usr/bin/env python3
"""Mide la familia de disparos `assets/audio/shot_*.wav` contra los criterios.

Por que existe: el defecto que se arreglo era de DINAMICA, no de gusto, y una
medida es la unica forma de no volver a el. Un disparo de 9 mm es transitorio +
cuerpo + cola; si el RMS se hunde, se oye un chasquido fino aunque el pico este
a tope. Este script imprime las cifras con las que se decide si una toma entra:

  dur      duracion (ms)                      criterio: 250-450
  pico     pico de muestra (dBFS)             criterio: <= -0,5 y 0 muestras al ras
  rms      RMS de todo el archivo (dBFS)      criterio: >= -18
  crest    pico - RMS (dB)                    criterio: 12-18
  atk40    RMS de los primeros 40 ms (dBFS)   criterio: las cinco dentro de 1,5 dB
  cola     nivel RMS de los ultimos 100 ms relativo al ataque: si no baja, el
           archivo no decae (una cola que no decae suena a lazo, no a disparo)
  <120 .. >2.5k   reparto de energia por bandas: un disparo tiene que tener
           cuerpo en 120-400 Hz y 400-1000 Hz, no solo agudos

Uso:
    python3 tools/measure_shots.py
    python3 tools/measure_shots.py --json
"""
import argparse
import json
import math
import struct
import sys
import wave
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SR_EXPECTED = 48000
LOW_BANDS = [("<120", 0.0, 120.0), ("120-400", 120.0, 400.0),
             ("400-1k", 400.0, 1000.0), ("1-2.5k", 1000.0, 2500.0)]
CRITERIA = {"dur_ms": (250.0, 450.0), "peak_dbfs": (-60.0, -0.5),
            "rms_dbfs": (-18.0, 0.0), "crest_db": (12.0, 18.0)}


def read_wav_mono(path):
    with wave.open(str(path), "rb") as w:
        n_ch, width, rate, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(frames)
    if width != 2:
        raise ValueError("se esperaba PCM 16 bits, hay %d bytes/muestra" % width)
    n = len(raw) // 2
    vals = struct.unpack("<%dh" % n, raw[: n * 2])
    if n_ch == 1:
        return [v / 32768.0 for v in vals], rate
    acc = [0.0] * (n // n_ch)
    for i, v in enumerate(vals):
        acc[i // n_ch] += v / 32768.0
    return [v / n_ch for v in acc], rate


def db(v):
    return 20.0 * math.log10(v) if v > 1e-12 else -240.0


def band_split(samples, rate):
    try:
        import numpy as np
    except ImportError:
        return None
    x = np.asarray(samples, dtype=np.float64)
    x = x - x.mean()
    spec = np.fft.rfft(x * np.hanning(x.size))
    power = spec.real ** 2 + spec.imag ** 2
    freqs = np.fft.rfftfreq(x.size, 1.0 / rate)
    total = float(power.sum()) or 1e-30
    out = {name: float(power[(freqs >= lo) & (freqs < hi)].sum() / total)
           for name, lo, hi in LOW_BANDS}
    out[">2.5k"] = float(power[freqs >= 2500.0].sum() / total)
    return out


def measure(path):
    samples, rate = read_wav_mono(path)
    peak = max((abs(v) for v in samples), default=0.0)
    rms = math.sqrt(sum(v * v for v in samples) / len(samples)) if samples else 0.0
    a40 = math.sqrt(sum(v * v for v in samples[: int(0.04 * rate)]) / max(1, int(0.04 * rate)))
    tail = math.sqrt(sum(v * v for v in samples[-int(0.10 * rate):]) / max(1, int(0.10 * rate)))
    rail = sum(1 for v in samples if abs(v) >= 32767.0 / 32768.0)
    row = {
        "file": Path(path).name,
        "dur_ms": round(len(samples) / float(rate) * 1000.0, 1),
        "sample_rate": rate,
        "peak_dbfs": round(db(peak), 2),
        "rms_dbfs": round(db(rms), 2),
        "crest_db": round(db(peak) - db(rms), 2),
        "attack40_dbfs": round(db(a40), 2),
        "tail100_dbfs": round(db(tail), 2),
        "tail_below_attack_db": round(db(a40) - db(tail), 2),
        "samples_at_rail": rail,
    }
    b = band_split(samples, rate)
    if b:
        row["bands"] = {k: round(v, 4) for k, v in b.items()}
    return row


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--dir", default=str(REPO / "assets" / "audio"))
    args = ap.parse_args()
    files = sorted(Path(args.dir).glob("shot_*.wav"))
    if not files:
        print("no hay shot_*.wav en %s" % args.dir, file=sys.stderr)
        return 1
    rows = [measure(f) for f in files]
    if args.json:
        print(json.dumps(rows, indent=2))
        return 0

    print("%-12s %7s %7s %7s %7s %9s %9s %7s %6s" % (
        "archivo", "dur_ms", "pico", "rms", "cresta", "atk40", "cola100", "cola_db", "al_ras"))
    print("-" * 84)
    for r in rows:
        print("%-12s %7.1f %7.2f %7.2f %7.2f %9.2f %9.2f %7.1f %6d" % (
            r["file"], r["dur_ms"], r["peak_dbfs"], r["rms_dbfs"], r["crest_db"],
            r["attack40_dbfs"], r["tail100_dbfs"], r["tail_below_attack_db"], r["samples_at_rail"]))
    print()
    keys = ["<120", "120-400", "400-1k", "1-2.5k", ">2.5k"]
    print("%-12s %8s %9s %8s %8s %8s" % ("archivo", *keys))
    print("-" * 62)
    for r in rows:
        if "bands" in r:
            print("%-12s %8.3f %9.3f %8.3f %8.3f %8.3f" % (r["file"], *[r["bands"][k] for k in keys]))
    print()
    fails = []
    for r in rows:
        for key, (lo, hi) in CRITERIA.items():
            if not (lo <= r[key] <= hi):
                fails.append("%s: %s = %.2f fuera de [%.2f, %.2f]" % (r["file"], key, r[key], lo, hi))
        if r["samples_at_rail"]:
            fails.append("%s: %d muestras al ras" % (r["file"], r["samples_at_rail"]))
    atk = [r["attack40_dbfs"] for r in rows]
    spread = max(atk) - min(atk)
    print("dispersion del ataque (40 ms) entre las %d variantes: %.2f dB  (criterio <= 1,5 dB) %s"
          % (len(rows), spread, "OK" if spread <= 1.5 else "FALLA"))
    for r in rows:
        if r["sample_rate"] != SR_EXPECTED:
            fails.append("%s: sample rate %d != %d" % (r["file"], r["sample_rate"], SR_EXPECTED))
    if fails:
        print("\nFALLOS:")
        for f in fails:
            print("  -", f)
        return 1
    print("todos los criterios se cumplen")
    return 0


if __name__ == "__main__":
    sys.exit(main())
