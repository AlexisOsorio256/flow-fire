#!/usr/bin/env python3
"""Mide una familia de WAV con las MISMAS metricas y saca la tabla del informe.

Por que existe: el mix de impactos se juzga por PERCEPCION, y la percepcion de
"esto es otro material" se puede reducir a unas pocas cifras comparables. Este
script no decide nada por si solo: mide los seis WAV finales y los imprime en
una tabla para poder comprobar que no son el mismo sonido con otro nombre.

Metricas por archivo:
  dur      duracion total (s)
  onset    primer tramo de 1 ms a <3 dB del pico de la envolvente (ms). Es el
           criterio de alineacion: ~0 significa ataque pegado al inicio
  peakms   donde cae el maximo de la envolvente (ms); puede ir algo despues
  peak     pico de muestra (dBFS)
  rms      RMS de todo el archivo (dBFS)
  crest    peak - rms (dB): cuanta dinamica hay entre el golpe y su cola
  centroid centroide espectral ponderado por energia (Hz)
  <800     fraccion de energia por debajo de 800 Hz
  >2.5k    fraccion de energia por encima de 2500 Hz
  T20      tiempo desde el pico hasta que la envolvente RMS de 1 ms cae 20 dB
           y ya no vuelve a subir (ms): la cola REAL, no la del archivo
  T10      lo mismo con 10 dB (ms)

El centroide y el reparto de energia se calculan sobre la DFT del archivo
entero (Hann), normalizando por la energia total, asi que "fraccion" siempre
suma <= 1 y el resto es la banda 800 Hz - 2,5 kHz.

Uso:
    python3 tools/measure_impacts.py assets/audio/impact_*.wav assets/audio/ricochet.wav
    python3 tools/measure_impacts.py --json fichero.wav

Requiere numpy (solo para la FFT; el resto se puede leer con el modulo `wave`).
"""
import argparse
import json
import math
import struct
import sys
import wave


def read_wav_mono(path):
    """Devuelve (muestras float en [-1,1], sample_rate). Mezcla a mono."""
    with wave.open(path, "rb") as w:
        n_ch = w.getnchannels()
        width = w.getsampwidth()
        rate = w.getframerate()
        frames = w.getnframes()
        raw = w.readframes(frames)
    if width == 1:
        fmt, scale, off = "b", 128.0, 128
    elif width == 2:
        fmt, scale, off = "h", 32768.0, 0
    elif width == 3:
        # PCM 24-bit empaquetado: se desempaqueta a mano.
        out = []
        for i in range(0, len(raw) - 2, 3):
            v = raw[i] | (raw[i + 1] << 8) | (raw[i + 2] << 16)
            if v & 0x800000:
                v -= 0x1000000
            out.append(v / 8388608.0)
        if n_ch == 2:
            out = [(out[i] + out[i + 1]) * 0.5 for i in range(0, len(out) - 1, 2)]
        return out, rate
    elif width == 4:
        fmt, scale, off = "i", 2147483648.0, 0
    else:
        raise ValueError("ancho de muestra no soportado: %d" % width)
    n = len(raw) // width
    vals = struct.unpack("<%d%s" % (n, fmt), raw[: n * width])
    if n_ch == 1:
        return [v / scale for v in vals], rate
    acc = [0.0] * (n // n_ch)
    for i, v in enumerate(vals):
        acc[i // n_ch] += v / scale
    inv = 1.0 / n_ch
    return [v * inv for v in acc], rate


def db(x):
    return 20.0 * math.log10(x) if x > 1e-12 else -240.0


def envelope_1ms(samples, rate):
    """Envolvente RMS en tramas de 1 ms, en dBFS."""
    n = max(1, int(round(rate / 1000.0)))
    env = []
    for i in range(0, len(samples) - n + 1, n):
        s = 0.0
        for v in samples[i:i + n]:
            s += v * v
        env.append(db(math.sqrt(s / n)))
    return env


def decay_ms(env, drop_db):
    """ms desde el pico de la envolvente hasta la ULTIMA vez que sigue a menos
    de `drop_db` del pico.

    No sirve "el primer instante en que cae X dB": una resonancia de placa
    oscila alrededor del umbral y ese metodo devolvia 0 en el acero, que tarda
    cientos de ms en morir. Se busca el ultimo tramo que sigue dentro de la
    ventana, que es lo que se oye como cola.
    """
    if not env:
        return 0.0
    pk = max(env)
    pi = env.index(pk)
    thr = pk - drop_db
    last_above = pi
    for i in range(pi, len(env)):
        if env[i] > thr:
            last_above = i
    return float(last_above - pi)


def spectral(samples, rate):
    try:
        import numpy as np
    except ImportError:
        return None
    x = np.asarray(samples, dtype=np.float64)
    if x.size < 8:
        return {"centroid_hz": 0.0, "low_frac": 0.0, "high_frac": 0.0}
    x = x - x.mean()
    win = np.hanning(x.size)
    spec = np.fft.rfft(x * win)
    power = (spec.real ** 2 + spec.imag ** 2)
    freqs = np.fft.rfftfreq(x.size, 1.0 / rate)
    total = float(power.sum())
    if total <= 0.0:
        return {"centroid_hz": 0.0, "low_frac": 0.0, "high_frac": 0.0}
    centroid = float((freqs * power).sum() / total)
    low = float(power[freqs < 800.0].sum() / total)
    high = float(power[freqs > 2500.0].sum() / total)
    return {"centroid_hz": centroid, "low_frac": low, "high_frac": high}


def measure(path):
    samples, rate = read_wav_mono(path)
    # `wave` no acepta WAV extensibles; los maestros del repo son PCM estandar.
    peak = max((abs(v) for v in samples), default=0.0)
    rms = math.sqrt(sum(v * v for v in samples) / len(samples)) if samples else 0.0
    env = envelope_1ms(samples, rate)
    peak_env = max(env) if env else -240.0
    atk = env.index(peak_env) * 1.0 if env else 0.0
    # `onset_ms`: primer tramo de 1 ms a menos de 3 dB del pico de la envolvente.
    # Es el criterio con el que tools/build_impacts.py ALINEA el ataque, asi que
    # esta columna es la que prueba que la muestra empieza en su transitorio y no
    # 90 ms tarde. `peak_ms` es donde cae el maximo de la envolvente, que en un
    # golpe con cuerpo puede ser algo despues del onset (no es un defecto).
    onset = 0.0
    if env and peak_env > -240.0:
        thr = peak_env * (10.0 ** (-3.0 / 20.0))
        for i, v in enumerate(env):
            if v >= thr:
                onset = float(i)
                break
    out = {
        "file": path,
        "duration_s": round(len(samples) / float(rate), 4),
        "sample_rate": rate,
        "onset_ms": onset,
        "peak_ms": atk,
        "peak_dbfs": round(db(peak), 2),
        "rms_dbfs": round(db(rms), 2),
        "crest_db": round(db(peak) - db(rms), 2),
        "t20_ms": decay_ms(env, 20.0),
        "t10_ms": decay_ms(env, 10.0),
    }
    sp = spectral(samples, rate)
    if sp is None:
        out.update({"centroid_hz": None, "low_frac": None, "high_frac": None})
        out["_warn"] = "numpy no disponible: sin analisis espectral"
    else:
        out.update({
            "centroid_hz": round(sp["centroid_hz"], 1),
            "low_frac": round(sp["low_frac"], 4),
            "high_frac": round(sp["high_frac"], 4),
        })
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    rows = []
    for f in args.files:
        try:
            rows.append(measure(f))
        except Exception as exc:  # un WAV roto no debe tumbar la tabla entera
            rows.append({"file": f, "error": str(exc)})
    if args.json:
        print(json.dumps(rows, indent=2))
        return
    head = ("archivo", "dur", "onset", "peakms", "peak", "rms", "crest",
            "centroid", "<800", ">2.5k", "T20", "T10")
    print("%-34s %6s %6s %6s %7s %7s %6s %9s %6s %6s %6s %6s" % head)
    print("-" * 122)
    for r in rows:
        if "error" in r:
            print("%-34s  ERROR: %s" % (r["file"], r["error"]))
            continue
        print("%-34s %6.3f %6.1f %6.1f %7.2f %7.2f %6.2f %9.1f %6.3f %6.3f %6.0f %6.0f" % (
            r["file"].split("/")[-1], r["duration_s"], r["onset_ms"], r["peak_ms"],
            r["peak_dbfs"], r["rms_dbfs"], r["crest_db"], r["centroid_hz"],
            r["low_frac"], r["high_frac"], r["t20_ms"], r["t10_ms"]))


if __name__ == "__main__":
    main()
