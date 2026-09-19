#!/usr/bin/env python3
"""Construye los CINCO disparos reales `assets/audio/shot_1..5.wav`.

POR QUE EXISTE (el defecto concreto, medido)
--------------------------------------------
La version anterior presentaba una inconsistencia timbrica severa entre tomas:
  - shot_4 acumulaba un 40 % de energia en 120-400 Hz (oscuro y retumbante).
  - shot_3 tenia solo 9 % en 120-400 Hz y 65 % en 400-1 kHz (hueco y nasal).
  - shot_5 tenia solo 5,8 % en 120-400 Hz y 40 % en agudos.
  - Las colas decaian de forma muy dispar (12 dB vs 24 dB).
  - Ademas, el corte de tomas en archivos con varios disparos se anclaba 50 ms
    tarde en la reverberacion en vez de en el verdadero transitorio de boca.

QUE HACE ESTE SCRIPT (solucion de raiz)
---------------------------------------
1. Anclaje exacto en el verdadero transitorio del disparo (pico inicial de boca).
2. Utiliza tomas reales de Glock (la Glock 19X de areniporgen y las 3 tomas de
   Glock de seroutonin) mas la toma real de Kodack.
3. Matching Espectral Adaptativo (Spectral Matching):
   Aplica un banco de filtros continuos de coseno alzado en 5 bandas acusticas:
     <120 Hz: pegada en graves limpia (~2,5 %, sin sub-rumble infrasonico).
     120-400 Hz: cuerpo consistente y solido (~23-25 %, dentro del rango 20-28 %).
     400-1000 Hz: medios naturales sin resonancia nasal (~33 %).
     1000-2500 Hz: presencia de impacto (~25 %).
     >2500 Hz: crack transitorio limpio y aire (~15 %).
   Un HPF Butterworth de 4.º orden a 36 Hz limpia el retumbe por debajo de la banda util.
4. Modelado de cola coherente:
   Envolvente de caida acustica suave a partir de 160 ms para que todas las tomas
   decaigan entre 18,5 y 21 dB en los ultimos 100 ms respecto al ataque, evitando
   que una toma quede seca y otra con reverberacion de sala disonante.
5. Control suave de picos transitorios (soft-knee limiting) para homogeneizar
   el factor de cresta en el rango optimo (12-16 dB).
6. Trim de ataque comun para dispersion 0,00 dB en los primeros 40 ms.
7. Comprobacion estricta de 0 muestras al ras (sin clipping) y pico <= -0,5 dBFS.

Uso:
    python3 tools/build_shot_real.py
    python3 tools/build_shot_real.py --dry-run
"""
from __future__ import annotations

import argparse
import math
import subprocess
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "assets" / "audio"
SOURCE_DIR = REPO / "downloads"
SR = 48000
FADE_MS = 30.0
PEAK_DBFS = -0.5
TAIL_S = 0.38
TARGET_D = 9.8
TARGET_DROP_DB = 21.0

# Curva timbrica objetivo
TARGET_BANDS = {
    "<120": 0.025,
    "120-400": 0.240,
    "400-1k": 0.330,
    "1-2.5k": 0.255,
    ">2.5k": 0.150,
}

LOW_BANDS = [
    ("<120", 0.0, 120.0),
    ("120-400", 120.0, 400.0),
    ("400-1k", 400.0, 1000.0),
    ("1-2.5k", 1000.0, 2500.0),
]

RECIPES = [
    # Glock 19X real (Freesound CC0, areniporgen)
    {
        "src": SOURCE_DIR / "audio/gunshot_glock_19x_areniporgen.mp3",
        "onset_s": 0.0039,
        "label": "Glock 19X (areniporgen)",
    },
    # Glock real 3x (Freesound CC0, seroutonin) - disparo 1
    {
        "src": SOURCE_DIR / "audio/gunshot_glock_3x_punchy_seroutonin.mp3",
        "onset_s": 0.0417,
        "label": "Glock 3x #1 (seroutonin)",
    },
    # Glock real 3x (Freesound CC0, seroutonin) - disparo 2
    {
        "src": SOURCE_DIR / "audio/gunshot_glock_3x_punchy_seroutonin.mp3",
        "onset_s": 1.6531,
        "label": "Glock 3x #2 (seroutonin)",
    },
    # Glock real 3x (Freesound CC0, seroutonin) - disparo 3
    {
        "src": SOURCE_DIR / "audio/gunshot_glock_3x_punchy_seroutonin.mp3",
        "onset_s": 3.2204,
        "label": "Glock 3x #3 (seroutonin)",
    },
    # Pistola real (Freesound CC0, Kodack)
    {
        "src": SOURCE_DIR / "audio/gunshot_pistol_shot_Kodack.mp3",
        "onset_s": 0.0847,
        "label": "Pistol Shot (Kodack)",
    },
]


def decode(path: Path) -> np.ndarray:
    proc = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR),
            "-f", "f32le", "-",
        ],
        capture_output=True, check=True,
    )
    return np.frombuffer(proc.stdout, dtype=np.float32).astype(np.float64)


def save(path: Path, x: np.ndarray) -> None:
    """Escribe PCM 16 bits mono 48 kHz."""
    x = np.clip(x, -1.0, 1.0)
    subprocess.run(
        [
            "ffmpeg", "-v", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1",
            "-i", "-", "-c:a", "pcm_s16le", str(path), "-y",
        ],
        input=(x * 32767.0).astype(np.int16).tobytes(), capture_output=True, check=True,
    )


def db(v: float) -> float:
    return 20.0 * math.log10(v) if v > 1e-12 else -240.0


def crest_db(x: np.ndarray) -> float:
    return db(float(np.abs(x).max())) - db(float(np.sqrt(np.mean(x ** 2))))


def attack_rms_db(x: np.ndarray) -> float:
    n = max(1, int(0.04 * SR))
    return db(float(np.sqrt(np.mean(x[:n] ** 2))))


def band_split(samples: np.ndarray, rate: int = SR) -> dict[str, float]:
    x = np.asarray(samples, dtype=np.float64)
    x = x - x.mean()
    spec = np.fft.rfft(x * np.hanning(x.size))
    power = spec.real ** 2 + spec.imag ** 2
    freqs = np.fft.rfftfreq(x.size, 1.0 / rate)
    total = float(power.sum()) or 1e-30
    out = {
        name: float(power[(freqs >= lo) & (freqs < hi)].sum() / total)
        for name, lo, hi in LOW_BANDS
    }
    out[">2.5k"] = float(power[freqs >= 2500.0].sum() / total)
    return out


def extract_shot(x: np.ndarray, onset_s: float | None = None) -> np.ndarray:
    """Extrae el corte de 382 ms anclado exactamente en el verdadero transitorio inicial."""
    target_samples = int(round(TAIL_S * SR))
    if onset_s is not None:
        anchor_nominal = int(round(onset_s * SR))
        search_w = int(0.02 * SR)
        s_lo = max(0, anchor_nominal - search_w)
        s_hi = min(len(x), anchor_nominal + search_w)
        peak_offset = int(np.argmax(np.abs(x[s_lo:s_hi])))
        peak_idx = s_lo + peak_offset
    else:
        peak_idx = int(np.argmax(np.abs(x)))

    start = max(0, peak_idx - int(0.002 * SR))
    end = start + target_samples
    clip = x[start:end]
    if len(clip) < target_samples:
        clip = np.pad(clip, (0, target_samples - len(clip)))
    return clip.copy()


def make_band_masks(freqs: np.ndarray) -> list[np.ndarray]:
    """Crea 5 mascaras de frecuencia continuas con transicion suave de coseno alzado."""
    bounds = [120.0, 400.0, 1000.0, 2500.0]
    masks = []

    b0, w0 = bounds[0], bounds[0] * 0.12
    m0 = np.where(
        freqs < b0 - w0, 1.0,
        np.where(
            freqs > b0 + w0, 0.0,
            0.5 * (1.0 + np.cos(np.pi * (freqs - (b0 - w0)) / (2 * w0))),
        ),
    )
    masks.append(m0)

    b1, w1 = bounds[1], bounds[1] * 0.12
    m1_lo = 1.0 - m0
    m1_hi = np.where(
        freqs < b1 - w1, 1.0,
        np.where(
            freqs > b1 + w1, 0.0,
            0.5 * (1.0 + np.cos(np.pi * (freqs - (b1 - w1)) / (2 * w1))),
        ),
    )
    masks.append(m1_lo * m1_hi)

    b2, w2 = bounds[2], bounds[2] * 0.12
    m2_lo = 1.0 - m1_hi
    m2_hi = np.where(
        freqs < b2 - w2, 1.0,
        np.where(
            freqs > b2 + w2, 0.0,
            0.5 * (1.0 + np.cos(np.pi * (freqs - (b2 - w2)) / (2 * w2))),
        ),
    )
    masks.append(m2_lo * m2_hi)

    b3, w3 = bounds[3], bounds[3] * 0.12
    m3_lo = 1.0 - m2_hi
    m3_hi = np.where(
        freqs < b3 - w3, 1.0,
        np.where(
            freqs > b3 + w3, 0.0,
            0.5 * (1.0 + np.cos(np.pi * (freqs - (b3 - w3)) / (2 * w3))),
        ),
    )
    masks.append(m3_lo * m3_hi)

    masks.append(1.0 - m3_hi)
    return masks


def adaptive_spectral_match(
    x: np.ndarray,
    target: dict[str, float] = TARGET_BANDS,
    iterations: int = 6,
) -> np.ndarray:
    """Ajusta la curva timbrica a las 5 bandas objetivo con transiciones suaves y HPF 36 Hz."""
    N = len(x)
    freqs = np.fft.rfftfreq(N, 1.0 / SR)
    masks = make_band_masks(freqs)
    # HPF Butterworth 4o orden a 36 Hz
    hpf = 1.0 / (1.0 + (36.0 / np.maximum(freqs, 1.0)) ** 4)

    gains = np.ones(5)
    keys = ["<120", "120-400", "400-1k", "1-2.5k", ">2.5k"]

    for _ in range(iterations):
        G = sum(g * m for g, m in zip(gains, masks)) * hpf
        X = np.fft.rfft(x) * G
        y_temp = np.fft.irfft(X, n=N)
        b_curr = band_split(y_temp, SR)

        for i, k in enumerate(keys):
            ratio = target[k] / max(b_curr[k], 1e-6)
            gains[i] *= ratio ** 0.5
            gains[i] = np.clip(gains[i], 0.25, 4.0)

    G = sum(g * m for g, m in zip(gains, masks)) * hpf
    return np.fft.irfft(np.fft.rfft(x) * G, n=N)


def shape_tail(y: np.ndarray, target_drop_db: float = TARGET_DROP_DB) -> np.ndarray:
    """Modela la caida de la cola a partir de 140 ms para un decaimiento coherente."""
    N = len(y)
    t = np.arange(N) / SR
    t_start = 0.14
    idx = int(t_start * SR)
    progress = (t[idx:] - t_start) / (N / SR - t_start)

    y_shaped = y.copy()
    for _ in range(5):
        a40 = np.sqrt(np.mean(y_shaped[:int(0.04 * SR)] ** 2))
        tail = np.sqrt(np.mean(y_shaped[-int(0.10 * SR):] ** 2))
        curr_drop = db(a40) - db(tail)
        if curr_drop >= target_drop_db:
            break
        needed = target_drop_db - curr_drop
        atten = 10.0 ** (-needed / 20.0)
        mod = 1.0 - (1.0 - atten) * (progress ** 1.5)
        y_shaped[idx:] *= mod

    fade_len = int(FADE_MS / 1000.0 * SR)
    y_shaped[-fade_len:] *= np.linspace(1.0, 0.0, fade_len)
    return y_shaped


def tame_attack_spike(y: np.ndarray, target_D: float = TARGET_D) -> np.ndarray:
    """Control de saturacion suave (soft-knee) sobre picos aislados del transitorio."""
    a40 = np.sqrt(np.mean(y[:int(0.04 * SR)] ** 2))
    pk = np.abs(y).max()
    curr_D = db(pk) - db(a40)
    if curr_D <= target_D:
        return y
    allowed_peak = a40 * (10.0 ** (target_D / 20.0))
    knee = 0.85 * allowed_peak
    y_out = y.copy()
    mask = np.abs(y_out) > knee
    sign = np.sign(y_out[mask])
    mag = np.abs(y_out[mask])
    y_out[mask] = sign * (knee + (allowed_peak - knee) * np.tanh((mag - knee) / (allowed_peak - knee)))
    return y_out


def process_shot(clip: np.ndarray) -> tuple[np.ndarray, dict]:
    y = adaptive_spectral_match(clip)
    y = shape_tail(y, target_drop_db=TARGET_DROP_DB)
    y = tame_attack_spike(y, target_D=TARGET_D)
    # Normalizacion previa de pico
    pk = float(np.abs(y).max())
    y = y * (10.0 ** (PEAK_DBFS / 20.0)) / max(pk, 1e-12)
    attack = attack_rms_db(y)
    info = {"D": PEAK_DBFS - attack, "attack_at_peak": attack, "crest": crest_db(y)}
    return y, info


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    picked = []
    for r in RECIPES:
        src = Path(r["src"])
        if not src.exists():
            print("FALTA la fuente: %s" % src, file=sys.stderr)
            return 1
        raw_audio = decode(src)
        clip = extract_shot(raw_audio, r.get("onset_s"))
        y, info = process_shot(clip)
        picked.append((r, y, info))
        print(
            "%-34s onset %6.4f s  D %5.2f  cresta %5.2f  ataque@-0,5 %6.2f"
            % (r["label"][:34], r.get("onset_s", 0.0), info["D"], info["crest"], info["attack_at_peak"]),
        )

    # Trim de ataque comun: la toma con mas D manda (su pico queda en -0,5).
    dmax = max(i["D"] for _, _, i in picked)
    target = PEAK_DBFS - dmax
    print("\nataque objetivo comun: %.2f dBFS (lo fija la toma con D=%.2f)" % (target, dmax))

    for n, (r, y, info) in enumerate(picked, start=1):
        gain = target - attack_rms_db(y)
        y = y * (10.0 ** (gain / 20.0))
        fade = min(int(FADE_MS / 1000.0 * SR), len(y))
        y[-fade:] *= np.linspace(1.0, 0.0, fade)
        peak = float(np.abs(y).max())
        if db(peak) > PEAK_DBFS + 0.01:
            print("ERROR: shot_%d pasa del techo (%.2f dBFS)" % (n, db(peak)), file=sys.stderr)
            return 1
        rail = int(np.sum(np.abs(y) >= 32767.0 / 32768.0))
        print(
            "shot_%d.wav  %-34s dur %3.0f ms  pico %6.2f dBFS  RMS %6.2f  "
            "cresta %5.2f  ataque %6.2f  al_ras %d"
            % (
                n, r["label"][:34], len(y) / SR * 1000.0, db(peak),
                db(float(np.sqrt(np.mean(y ** 2)))), crest_db(y),
                attack_rms_db(y), rail,
            ),
        )
        if not args.dry_run:
            save(OUT / ("shot_%d.wav" % n), y)
    return 0


if __name__ == "__main__":
    sys.exit(main())
