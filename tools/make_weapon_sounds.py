#!/usr/bin/env python3
"""Genera los WAV del arma que no salen de ningun master. Es sintesis, no
grabacion: cada uno cubre un evento que estaba mudo.

    python3 tools/make_weapon_sounds.py

Escribe en assets/audio/ (16 bits, mono, 44,1 kHz, que es lo que importa Godot):

  trigger_reset.wav  click del reset del disparador (40 ms)
  mag_drop.wav       UN golpe del cargador contra hormigon
  slide_release.wav  el reten de la corredera al soltarse
  mag_insert.wav     el cargador rozando el brocal mientras sube

Cada sonido se piensa para un unico golpe audible: ataque corto, cola corta y
nada de reverb. Despues de generarlos hay que reimportar:
    godot --headless --path . --import
"""
import os
import struct
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")


def rng(seed):
    return np.random.default_rng(seed)


def noise(n, seed):
    return rng(seed).normal(0.0, 1.0, n)


def band(x, low, high, slope=2.0):
    """Filtro de banda por FFT: barato, estable y suficiente para foley."""
    spec = np.fft.rfft(x)
    freq = np.fft.rfftfreq(x.size, 1.0 / SR)
    shape = np.ones_like(freq)
    if low > 0.0:
        shape *= 1.0 / (1.0 + (low / np.maximum(freq, 1e-6)) ** slope)
    if high > 0.0:
        shape *= 1.0 / (1.0 + (freq / high) ** slope)
    return np.fft.irfft(spec * shape, x.size)


def decay(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def click(n, tau, seed, low, high):
    e = decay(n, tau)
    return band(noise(n, seed), low, high) * e


def partials(n, freqs, taus, seed, jitter=0.0, detune=0.0):
    t = np.arange(n) / SR
    r = rng(seed)
    out = np.zeros(n)
    for f, tau in zip(freqs, taus):
        f = f * (1.0 + detune * (r.random() - 0.5))
        phase = r.random() * 2.0 * np.pi
        out += np.sin(2.0 * np.pi * f * t + phase) * decay(n, tau)
    return out


def normalize(x, peak):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def write(name, x):
    x = np.clip(x, -1.0, 1.0)
    data = (x * 32767.0).astype("<i2")
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("  %-20s %5.0f ms  pico %.2f" % (name, 1000.0 * x.size / SR, float(np.max(np.abs(x)))))


def mag_drop():
    """UN solo golpe de cargador vacio contra hormigon. Cada contacto real
    dispara un golpe con nivel/pitch por velocidad (ver MagazineDrop); nada de
    rebotes horneados."""
    n = int(0.22 * SR)
    body = partials(n, [540.0, 1210.0, 1780.0, 2660.0, 3520.0],
                    [0.055, 0.040, 0.030, 0.020, 0.014], 100)
    hit = click(n, 0.009, 200, 900.0, 4200.0) * 1.4
    return normalize(band(body + hit, 120.0, 9000.0), 0.62)


def slide_release():
    """Reten de corredera: un tic de acero corto y agudo, sin cola."""
    n = int(0.10 * SR)
    tick = click(n, 0.0035, 31, 2600.0, 9000.0)
    ring = partials(n, [2450.0, 4180.0, 6350.0], [0.010, 0.007, 0.004], 32)
    return normalize(tick + ring * 0.6, 0.38)


def mag_insert():
    """El cargador rozando el brocal mientras sube: metal contra metal, con el
    traqueteo de las costillas y sin golpe final (el asiento es otro sonido).
    Dura lo que dura la subida: 0,36 s."""
    n = int(0.36 * SR)
    t = np.arange(n) / SR
    # Sube frenando, como el cargador: la friccion es mas fuerte al principio.
    slide_env = 0.55 + 0.45 * np.exp(-t / 0.22)
    # Costillas del cargador pasando por el brocal.
    chatter = 0.6 + 0.4 * np.sin(2.0 * np.pi * 34.0 * t + 0.3) ** 2
    drag = band(noise(n, 61), 1400.0, 6500.0) * slide_env * chatter
    body = band(noise(n, 62), 200.0, 900.0) * slide_env * 0.7
    # Un resto de resorte al final del recorrido.
    spring = partials(n, [820.0, 1310.0], [0.05, 0.03], 63) * 0.18 * np.exp(-np.maximum(t - 0.20, 0.0) / 0.06)
    return normalize(band(drag + body + spring, 140.0, 9000.0) * decay(n, 0.42), 0.34)


def trigger_reset():
    """Click del reset del disparador: acero diminuto, 40 ms, sin cola.
    El reset sigue al movimiento real del gatillo (ver Glock.gd); esto es solo
    su transitorio, no una corredera."""
    n = int(0.05 * SR)
    tick = click(n, 0.0022, 91, 3200.0, 11000.0)
    ring = partials(n, [3350.0, 5400.0, 8200.0], [0.006, 0.004, 0.0025], 92) * 0.5
    return normalize(tick + ring, 0.30)


def main():
    os.makedirs(OUT, exist_ok=True)
    print("generando sonidos del arma en", OUT)
    write("trigger_reset.wav", trigger_reset())
    write("mag_drop.wav", mag_drop())
    write("slide_release.wav", slide_release())
    write("mag_insert.wav", mag_insert())
    print("listo. reimporta con: godot --headless --path . --import")


if __name__ == "__main__":
    main()
