#!/usr/bin/env python3
"""Construye los CINCO disparos reales `assets/audio/shot_1..5.wav`.

POR QUE EXISTE (el defecto concreto, medido)
--------------------------------------------
La version anterior cortaba cinco tomas de la Walther PPQ y las dejaba tal cual.
El problema no era el corte, era la DINAMICA heredada de las tomas:

    shot_1..5 antiguos   pico -1,00 dBFS   RMS -27,4..-29,4 dBFS   cresta 26,4-28,4 dB
    toma cruda X_39.wav  cresta 39,0 dB    X_39P.wav 36,5 dB

Envolvente: -6 dB a los 10 ms y -20 dB a los 15 ms, con el 99,9 % de la energia
en los primeros 60 ms. La loudness percibida va con el RMS, no con el pico, asi
que eso se oye como un chasquido fino de 15 ms: "parece que dispara peluches".
Un disparo de 9 mm es transitorio + CUERPO + cola, y aqui no habia ni cuerpo ni
cola. La causa de fondo: las tomas de la biblioteca son de micro cercano, sin
sala, y un micro cercano en un disparo es todo pico.

QUE HACE ESTE SCRIPT
--------------------
1. Elige las tomas por MEDIDA, no por nombre: de cada fuente saca las tomas de
   UN solo disparo (pico global alineado al inicio, sin un segundo disparo
   despues de 80 ms) y se queda con las de mejor factor de cresta (mas cuerpo).
2. Aplica la cadena de dinamica/EQ documentada (mas abajo). La compresion y el
   EQ NO son hacer trampa: una grabacion real de disparo puesta en crudo es
   justo lo que sonaba a juguete.
3. Iguala el ATAQUE de las cinco: por construccion las cinco acaban con el mismo
   RMS en los primeros 40 ms, asi que la diferencia entre variantes es de
   material, no de nivel.

CADENA (por toma, en este orden)
--------------------------------
  a) HPF 35 Hz, 2o orden Butterworth. Fuera el retumbe por debajo de la banda
     util; 120-400 Hz no se toca.
  b) Low-shelf a 200 Hz con ganancia POR TOMA. Es la herramienta que devuelve el
     cuerpo que el micro cercano no capturo: sube a la vez el reparto 120-400 Hz
     y el RMS respecto al pico, o sea BAJA la cresta. Medido en audiobeast_0:
     shelf +0 -> 120-400 = 0,27 / cresta 12,6 dB; shelf +6 -> 0,38 / 13,1 dB.
     Solo amplifica contenido que YA esta en la grabacion; no se anade nada.
  c) Normalizacion de pico a PEAK_DBFS = -0,5 dBFS.
  d) Trim de ataque comun: ganancia para que el RMS de los primeros 40 ms valga
     ATTACK_TARGET_DBFS en las cinco. Como el pico nunca sube (la ganancia es
     <= 0 por construccion), se cumple pico <= -0,5 dBFS y ademas el pico de la
     variante con mas D es exactamente -0,5.
  e) Fade de salida de 30 ms y comprobacion de que no hay ninguna muestra al
     ras (clip).

CRITERIOS DE ACEPTACION (los comprueba `tools/measure_shots.py`)
---------------------------------------------------------------
  cresta 12-18 dB | pico <= -0,5 dBFS sin muestras al ras | RMS >= -18 dBFS |
  energia real en 120-400 Hz y 400-1000 Hz | ataque (40 ms) igual dentro de
  1,5 dB | duracion 250-450 ms con cola que decae de verdad.

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
SR = 48000
FADE_MS = 30.0
PEAK_DBFS = -0.5
TAIL_S = 0.38
MIN_DUR_S = 0.25
# Umbrales del detector de tomas.
ONSET_FRAC = 0.45       # sobre la senal normalizada a pico 1
DEDUP_S = 0.12          # dos onsets mas cerca que esto son el mismo disparo
ANCHOR_S = 0.09         # ventana para re-anclar en el pico real
PEAK_EARLY_S = 0.006    # el pico tiene que caer aqui: si no, el corte esta mal
SECOND_DB = -3.0        # un 2o golpe mas fuerte que esto es OTRO disparo
SECOND_AFTER_S = 0.08
MIN_PEAK = 0.30

# --- Tomas elegidas (por medida, ver el informe) -----------------------------
#
# `rank` = posicion en la lista de tomas validas de esa fuente ordenadas por
# cresta ascendente (0 = la de mas cuerpo). `shelf_db` = ganancia del low-shelf
# a 200 Hz. La eleccion se hizo midiendo cresta, reparto de bandas y RMS; el
# conjunto final es el que deja las cinco dentro de los criterios con el ataque
# ya igualado.
SOURCE_DIR = REPO / "downloads"
RECIPES = [
    # Glock 19X real (Freesound CC0, areniporgen). Es la de menos cresta del
    # conjunto (13,5 dB): la que mas cuerpo tiene y la que fija el techo.
    {"src": SOURCE_DIR / "audio/gunshot_glock_19x_areniporgen.mp3",
     "rank": 0, "shelf_db": 0.0, "label": "Glock 19X (areniporgen)"},
    # Otra Glock real, tres disparos (Freesound CC0, seroutonin). Necesita
    # +6 dB de shelf para que el 120-400 Hz llegue al 24 %.
    {"src": SOURCE_DIR / "audio/gunshot_glock_3x_punchy_seroutonin.mp3",
     "rank": 0, "shelf_db": 6.0, "label": "Glock 3x (seroutonin)"},
    # Disparos de mano a bocajarro, toma larga con muchos tiros sueltos
    # (Freesound CC0, johanwestling). El titulo de la fuente dice .22/7,5 mm/9 mm.
    {"src": SOURCE_DIR / "audio/gunshot_9mm_close_single_shots_johanwestling.mp3",
     "rank": 1, "shelf_db": 0.0, "label": "close single handgun shots (johanwestling)"},
    # Pistola real (Freesound CC0, Kodack).
    {"src": SOURCE_DIR / "audio/gunshot_pistol_shot_Kodack.mp3",
     "rank": 0, "shelf_db": 0.0, "label": "Pistol Shot (Kodack)"},
    # 9 mm real (Freesound CC0, michorvath).
    {"src": SOURCE_DIR / "audio/gunshot_9mm_pistol_shot_michorvath.mp3",
     "rank": 0, "shelf_db": 6.0, "label": "9mm pistol shot (michorvath)"},
]


def decode(path: Path) -> np.ndarray:
    proc = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR),
         "-f", "f32le", "-"], capture_output=True, check=True)
    return np.frombuffer(proc.stdout, dtype=np.float32).astype(np.float64)


def save(path: Path, x: np.ndarray) -> None:
    """Escribe PCM 16 bits mono 48 kHz.

    OJO: el bloque que se le pasa a ffmpeg es int16, asi que el formato de
    ENTRADA tiene que declararse `s16le`. Con `f32le` ffmpeg lee la mitad de
    muestras (4 bytes por muestra en vez de 2) y el WAV sale a la mitad de
    duracion y con el contenido destrozado.
    """
    x = np.clip(x, -1.0, 1.0)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
         "-c:a", "pcm_s16le", str(path), "-y"],
        input=(x * 32767.0).astype(np.int16).tobytes(), capture_output=True, check=True)


def db(v: float) -> float:
    return 20.0 * math.log10(v) if v > 1e-12 else -240.0


def crest_db(x: np.ndarray) -> float:
    return db(float(np.abs(x).max())) - db(float(np.sqrt(np.mean(x ** 2))))


def hpf(x: np.ndarray, fc: float = 35.0, q: float = 0.7071) -> np.ndarray:
    """Butterworth de 2o orden (RBJ), a mano para no depender de scipy."""
    w = 2.0 * math.pi * fc / SR
    c, s = math.cos(w), math.sin(w)
    al = s / (2.0 * q)
    b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    a0, a1, a2 = 1 + al, -2 * c, 1 - al
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        v = x[i]
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y[i] = o
    return y


def low_shelf(x: np.ndarray, fc: float, gain_db: float, q: float = 0.7071) -> np.ndarray:
    """Low-shelf RBJ. Devuelve el cuerpo que el micro cercano no capturo."""
    if abs(gain_db) < 1e-6:
        return x
    A = 10.0 ** (gain_db / 40.0)
    w = 2.0 * math.pi * fc / SR
    c, s = math.cos(w), math.sin(w)
    al = s / (2.0 * q)
    t = 2.0 * math.sqrt(A) * al
    b0 = A * ((A + 1) - (A - 1) * c + t)
    b1 = 2 * A * ((A - 1) - (A + 1) * c)
    b2 = A * ((A + 1) - (A - 1) * c - t)
    a0 = (A + 1) + (A - 1) * c + t
    a1 = -2 * ((A - 1) + (A + 1) * c)
    a2 = (A + 1) + (A - 1) * c - t
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        v = x[i]
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y[i] = o
    return y


def single_shots(x: np.ndarray) -> list[np.ndarray]:
    """Tomas de UN disparo, con el pico global pegado al inicio."""
    xn = x / max(float(np.abs(x).max()), 1e-12)
    step = max(1, SR // 400)
    env = np.array([np.abs(xn[i:i + step]).max() for i in range(0, len(xn) - step, step)])
    loud = env >= ONSET_FRAC
    rising = np.flatnonzero(np.diff(loud.astype(np.int8)) == 1)
    onsets = [int(s * step + step) for s in rising]
    if len(env) and loud[0]:
        onsets.insert(0, 0)
    out: list[np.ndarray] = []
    taken: list[int] = []
    for o in onsets:
        if any(abs(o - t) < int(DEDUP_S * SR) for t in taken):
            continue
        hi = min(len(x), o + int(ANCHOR_S * SR))
        if hi <= o:
            continue
        anchor = o + int(np.argmax(np.abs(x[o:hi])))
        start = max(0, anchor - int(0.002 * SR))
        end = min(len(x), anchor + int(TAIL_S * SR))
        clip = x[start:end]
        if len(clip) < int(MIN_DUR_S * SR):
            continue
        peak = float(np.abs(clip).max())
        if peak < MIN_PEAK:
            continue
        # El pico tiene que ser global y estar al principio: si no, el corte
        # empieza en un flanco debil y el "ataque" medido no es el del disparo.
        if int(np.argmax(np.abs(clip))) > int(PEAK_EARLY_S * SR):
            continue
        # Y no puede haber OTRO disparo dentro de la ventana.
        if float(np.abs(clip[int(SECOND_AFTER_S * SR):]).max()) > peak * 10.0 ** (SECOND_DB / 20.0):
            continue
        taken.append(o)
        out.append(clip.copy())
    out.sort(key=crest_db)      # mas cuerpo (cresta baja) primero
    return out


def attack_rms_db(x: np.ndarray) -> float:
    n = max(1, int(0.04 * SR))
    return db(float(np.sqrt(np.mean(x[:n] ** 2))))


def process(clip: np.ndarray, shelf_db: float) -> tuple[np.ndarray, dict]:
    y = low_shelf(hpf(clip), 200.0, shelf_db)
    y = y * (10.0 ** (PEAK_DBFS / 20.0)) / max(float(np.abs(y).max()), 1e-12)
    attack = attack_rms_db(y)
    info = {"D": PEAK_DBFS - attack, "attack_at_peak": attack, "crest": crest_db(y)}
    return y, info


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    picked = []
    for r in RECIPES:
        src = Path(r["src"])
        if not src.exists():
            print("FALTA la fuente: %s" % src, file=sys.stderr)
            return 1
        shots = single_shots(decode(src))
        if len(shots) <= r["rank"]:
            print("%s: solo %d tomas validas, se pedia el rango %d"
                  % (src.name, len(shots), r["rank"]), file=sys.stderr)
            return 1
        y, info = process(shots[r["rank"]], r["shelf_db"])
        picked.append((r, y, info))
        print("%-34s rank %d  shelf %+.1f dB  D %5.2f  cresta %5.2f  ataque@-0,5 %6.2f"
              % (src.name, r["rank"], r["shelf_db"], info["D"], info["crest"],
                 info["attack_at_peak"]))

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
        print("shot_%d.wav  %-34s dur %3.0f ms  pico %6.2f dBFS  RMS %6.2f  "
              "cresta %5.2f  ataque %6.2f  al_ras %d"
              % (n, r["label"][:34], len(y) / SR * 1000.0, db(peak),
                 db(float(np.sqrt(np.mean(y ** 2)))), crest_db(y),
                 attack_rms_db(y), rail))
        if not args.dry_run:
            save(OUT / ("shot_%d.wav" % n), y)
    return 0


if __name__ == "__main__":
    sys.exit(main())
