#!/usr/bin/env python3
"""MONTA EL DISPARO (DRY): crack real + cuerpo grave. Sin sala horneada.

El corte del maestro (Glock 18c a 1 m, MKH416) trae el estampido y el
mecanismo, pero medido es un disparo FLACO y CORTO: 160 ms de chasquido con la
cola recortada. Lo que separa un disparo de verdad de uno de juguete no es el
grave a secas —medido con la transformada, el propio maestro tiene el 9% de su
energia por debajo de 150 Hz, y el corte suelto ya lo iguala—, sino tres cosas
que al corte le faltan: cuerpo que empuje, una cola que dure y un ataque que
destaque sobre su propia media.

Este montaje las pone con material real, sin inventar ninguna capa:

  CRACK  el corte del maestro, intacto. Es el ataque.
  CUERPO otra toma real 9 mm a 1 m del mismo bundle (Beretta 93R), en paso bajo
         para que aporte el empuje del fogonazo y no un segundo estampido. Se
         alinea por ATAQUE, no por pico: el golpe grave empieza con el crack.
  SALA   ninguna horneada: la sala la pone el bus World (Reverb). Hornear la
         misma IR en cada tiro impedia cambiar el recinto sin reconstruir los
         cinco WAV. El WAV es DRY; el sitio lo pone el bus.

Se comprueba con medidas, no a oido: duracion, fraccion de energia <150 Hz y
factor de cresta (pico menos RMS). El maestro real mide cresta ~20 y el corte
suelto ~11: esa diferencia ES el efecto "chasquido" y es lo que la cola repone.

    python3 tools/build_shot.py crack.wav cuerpo.wav -4.0 salida.wav [fade_s]
"""
import subprocess
import sys

import numpy as np

SR = 44100
CEILING_DB = -1.2
# Cola de sala LEGADA (solo comparacion --sin --dry): ruido exponencial.
ROOM_TAU_S = 0.055
ROOM_DB = -14.0
ROOM_LEN_S = 0.45
# Cierre de la muestra para que dos disparos seguidos no se apilen.
FADE_S = 0.06


def load(path):
    p = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "s16le",
         "-acodec", "pcm_s16le", "-ac", "1", "-ar", str(SR), "-"],
        capture_output=True, check=True)
    return np.frombuffer(p.stdout, dtype=np.int16).astype(np.float64) / 32768.0


def save(path, x):
    x = np.clip(x, -1.0, 1.0)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1",
         "-i", "-", "-c:a", "pcm_s16le", path, "-y"],
        input=(x * 32767.0).astype(np.int16).tobytes(), capture_output=True,
        check=True)


## Primer instante con senal de verdad: alinear por aqui (y no por el pico)
## deja el golpe grave EMPEZANDO con el crack, que es como suena un disparo.
def onset(x, frac=0.2):
    umbral = np.abs(x).max() * frac
    return int(np.argmax(np.abs(x) > umbral))


## Fraccion de energia por debajo de 150 Hz, promediada por tramos (STFT).
## Se mide por tramos y no sobre el archivo entero porque una ventana unica
## sobre una muestra corta miente: deja el ataque fuera de la ventana.
def low_share(x, n=1024, hop=256):
    w = np.hanning(n)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    num = den = 0.0
    for i in range(0, max(1, len(x) - n), hop):
        p = np.abs(np.fft.rfft(x[i:i + n] * w)) ** 2
        num += p[f < 150.0].sum()
        den += p.sum()
    return 100.0 * num / max(den, 1e-12)


def crest_db(x):
    return 20.0 * np.log10(np.abs(x).max() + 1e-12) - 20.0 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)


## Cola de sala: ruido exponencial. La muestra 0 va a 1 para que el ataque
## directo no se atenue (la convolucion sin eso restaria nivel al crack).
def room(tau_s=ROOM_TAU_S, length_s=ROOM_LEN_S):
    n = int(length_s * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(7)
    ir = rng.standard_normal(n) * np.exp(-t / tau_s)
    ir[0] = 1.0
    return ir


def main():
    args = [a for a in sys.argv[1:] if a != "--dry"]
    dry_only = "--dry" in sys.argv
    crack_path, body_path, rel_db, out_path = args[0], args[1], float(args[2]), args[3]
    fade = float(args[4]) if len(args) > 4 else FADE_S
    crack = load(crack_path)
    body = load(body_path)
    # El cuerpo cae justo detras del ataque del crack (menos de 1 ms de
    # separacion: el oido los funde en UN golpe, efecto Haas).
    shift = onset(crack) - onset(body)
    n_dry = max(len(crack), max(0, shift) + len(body))
    dry = np.zeros(n_dry)
    dry[:len(crack)] += crack
    g = (np.abs(crack).max() / max(np.abs(body).max(), 1e-9)) * 10.0 ** (rel_db / 20.0)
    if shift >= 0:
        dry[shift:shift + len(body)] += body * g
    else:
        dry[:len(body) + shift] += (body[-shift:]) * g
    if dry_only:
        mix = dry
    else:
        # Sala legada (solo para comparar): el crack suena en un sitio.
        mix = np.convolve(dry, room()) * 10.0 ** (ROOM_DB / 20.0)
        mix[:len(dry)] += dry
        mix = mix[:int(ROOM_LEN_S * SR)]
    n_fade = min(int(fade * SR), len(mix))
    if n_fade > 1:
        mix[-n_fade:] *= np.linspace(1.0, 0.0, n_fade)
    peak = np.abs(mix).max()
    ceil_lin = 10.0 ** (CEILING_DB / 20.0)
    if peak > ceil_lin:
        mix *= ceil_lin / peak
    save(out_path, mix)
    print("%s + %s (%+.1fdB) -> %.0f ms, pico %.1fdBFS, cresta %.1f, grave %.1f%% (crack solo %.1f%%, cresta %.1f)" %
          (crack_path.split("/")[-1], body_path.split("/")[-1], rel_db,
           len(mix) / SR * 1000.0, 20 * np.log10(np.abs(mix).max() + 1e-12),
           crest_db(mix), low_share(mix), low_share(crack), crest_db(crack)))


if __name__ == "__main__":
    sys.exit(main())
