#!/usr/bin/env python3
"""Convierte un video de gameplay en evidencia revisable por IA.

Uso:
    python3 tools/review_video.py video.mp4 --out /tmp/rev [--shots 4]
        [--reload 38.0,52.0] [--crop 1710:945:105:70]

Hace, sin ver el video:
  1. Extrae el audio y detecta disparos (onsets por umbral + refractory).
  2. Por cada disparo: rafaga densa a fps nativo +- ventana (contact sheet).
  3. Anatomia de audio por disparo (envolvente 5 ms + bandas grave/medio/agudo
     si hay numpy) para separar estampido / mecanica / cola.
  4. Segmentos manuales (p. ej. recargas) con --reload t0,t1,...

Es la forma honesta de "ver" un video para una IA: imagenes fijas a
resolucion temporal completa + datos de audio, no muestreo disperso.
Sin dependencias salvo ffmpeg (numpy opcional, solo para espectro).
"""
import argparse
import os
import struct
import subprocess
import sys
import wave

try:
    import numpy as np

    HAVE_NP = True
except ImportError:
    HAVE_NP = False


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print("FFMPEG fallo:", " ".join(cmd), "\n", r.stderr[-2000:], file=sys.stderr)
        sys.exit(1)
    return r


def extract_wav(src, dst):
    run(["ffmpeg", "-v", "error", "-y", "-i", src, "-vn",
         "-ac", "1", "-ar", "44100", dst])


def read_mono(path):
    w = wave.open(path, "rb")
    sr = w.getframerate()
    n = w.getnframes()
    raw = w.readframes(n)
    w.close()
    fmt = "<i2" if w.getsampwidth() == 2 else "<i4"
    import array
    a = array.array("h" if w.getsampwidth() == 2 else "i", raw)
    peak = float(2 ** (8 * w.getsampwidth() - 1))
    data = [x / peak for x in a]
    return sr, data


def onsets(data, sr, thr=0.25, refractory=0.4):
    times = []
    i = 0
    n = len(data)
    step = int(refractory * sr)
    while i < n:
        if abs(data[i]) > thr:
            times.append(i / sr)
            i += step
        else:
            i += 1
    return times


def burst_sheet(src, t0, pre, post, out, crop=None, tile_cols=6, fps=60):
    nframes = int((pre + post) * fps)
    rows = (nframes + tile_cols - 1) // tile_cols
    vf = f"fps={fps},scale=344:190,tile={tile_cols}x{rows}"
    if crop:
        vf = f"crop={crop}," + vf
    run(["ffmpeg", "-v", "error", "-y", "-ss", str(max(0.0, t0 - pre)),
         "-i", src, "-frames:v", str(nframes), "-vf", vf,
         "-frames:v", "1", out])


def envelope(data, sr, t0, window=0.25, step=0.005):
    base = int(t0 * sr)
    out = []
    t = 0.0
    while t < window:
        a = base + int(t * sr)
        b = base + int((t + step) * sr)
        seg = data[a:b]
        if not seg:
            break
        rms = (sum(x * x for x in seg) / len(seg)) ** 0.5
        out.append((t, rms, max(abs(x) for x in seg)))
        t += step
    return out


def bands(data, sr, t0, spans):
    if not HAVE_NP:
        return None
    arr = np.array(data, dtype=float)
    res = []
    for a, b, label in spans:
        s = arr[int((t0 + a) * sr):int((t0 + b) * sr)]
        if len(s) < 16:
            res.append((label, 0.0, (0, 0, 0)))
            continue
        S = np.fft.rfft(s * np.hanning(len(s)))
        f = np.fft.rfftfreq(len(s), 1 / sr)
        lo = float(np.sum(np.abs(S[(f >= 80) & (f < 800)]) ** 2))
        mid = float(np.sum(np.abs(S[(f >= 800) & (f < 2500)]) ** 2))
        hi = float(np.sum(np.abs(S[(f >= 2500) & (f < 16000)]) ** 2))
        tot = max(1e-9, lo + mid + hi)
        res.append((label, float(np.sqrt(np.mean(s ** 2))),
                    (lo / tot, mid / tot, hi / tot)))
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--out", required=True)
    ap.add_argument("--shots", type=int, default=4)
    ap.add_argument("--pre", type=float, default=0.15)
    ap.add_argument("--post", type=float, default=0.45)
    ap.add_argument("--thr", type=float, default=0.25)
    ap.add_argument("--reload", default="")
    ap.add_argument("--crop", default="")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    wav = os.path.join(args.out, "audio.wav")
    extract_wav(args.video, wav)
    sr, data = read_mono(wav)
    peak = max(abs(x) for x in data)
    print(f"AUDIO dur={len(data)/sr:.1f}s pico={peak:.3f} numpy={'si' if HAVE_NP else 'no'}")

    shots = onsets(data, sr, thr=args.thr)
    print(f"DISPAROS detectados: {len(shots)}")
    print("  " + ", ".join(f"{t:.1f}" for t in shots[:20]))

    spans = [(0, 0.015, "blast"), (0.015, 0.030, "trasera?"),
             (0.035, 0.060, "bateria?"), (0.060, 0.120, "cola")]
    for k, t0 in enumerate(shots[:args.shots]):
        tag = f"shot_{k:02d}_{t0:.1f}s"
        burst_sheet(args.video, t0, args.pre, args.post,
                    os.path.join(args.out, tag + ".jpg"), crop=args.crop or None)
        print(f"--- {tag}")
        for t, rms, pk in envelope(data, sr, t0 - 0.01)[:44]:
            bar = "#" * min(40, int(rms * 120))
            print(f"  +{t*1000:5.0f}ms rms={rms:.3f} pk={pk:.3f} {bar}")
        bd = bands(data, sr, t0, spans)
        if bd:
            for label, e, (lo, mid, hi) in bd:
                print(f"  {label:8s} E={e:.3f} grave={lo:.0%} medio={mid:.0%} agudo={hi:.0%}")

    for seg in args.reload.split():
        t0, t1 = seg.split(",")
        out = os.path.join(args.out, f"reload_{float(t0):.0f}s.jpg")
        vf = f"fps=12,scale=480:266,tile=6x99"
        if args.crop:
            vf = f"crop={args.crop}," + vf
        run(["ffmpeg", "-v", "error", "-y", "-ss", t0, "-i", args.video,
             "-t", str(float(t1) - float(t0)), "-vf", vf, "-frames:v", "1", out])
        print("RELOAD", seg, "->", out)
    print("LISTO", args.out)


if __name__ == "__main__":
    main()
