#!/usr/bin/env python3
"""Genera los WAV de la recarga que faltaban. Es sintesis, no grabacion: la
recarga se contaba con cuatro sonidos que no existian.

    python3 tools/make_reload_sounds.py

Escribe en assets/audio/ (16 bits, mono, 44,1 kHz, que es lo que importa Godot):

  mag_drop.wav       el cargador vacio rebotando en el suelo de hormigon
  mag_slap.wav       la palma dando en la culata del cargador al asentarlo
  slide_release.wav  el reten de la corredera al soltarse
  reload_rustle.wav  roce de correaje y ropa mientras se recarga

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
    """Cargador de acero vacio cayendo de canto en hormigon: cinco rebotes, cada
    uno mas flojo y mas grave, con el cuerpo metalico sonando por detras."""
    total = int(0.85 * SR)
    out = np.zeros(total)
    bounces = [(0.000, 1.00, 1.00), (0.115, 0.52, 0.94), (0.245, 0.30, 0.88),
               (0.375, 0.17, 0.83), (0.520, 0.10, 0.79)]
    for i, (at, amp, pitch) in enumerate(bounces):
        start = int(at * SR)
        n = int(0.30 * SR)
        body = partials(n, [540 * pitch, 1210 * pitch, 1780 * pitch, 2660 * pitch, 3520 * pitch],
                        [0.055, 0.040, 0.030, 0.020, 0.014], 100 + i)
        hit = click(n, 0.009, 200 + i, 900.0, 4200.0) * 1.4
        piece = normalize(body + hit, 1.0) * amp
        out[start:start + n] += piece[:max(0, min(n, total - start))]
    return normalize(band(out, 120.0, 9000.0), 0.62)


def mag_slap():
    """Palma enguantada dando en la culata del cargador: golpe sordo, sin brillo,
    con un resto de metal al final (el cargador entrando del todo)."""
    n = int(0.16 * SR)
    t = np.arange(n) / SR
    thud = np.sin(2.0 * np.pi * 132.0 * t) * decay(n, 0.045) * 1.0
    knock = np.sin(2.0 * np.pi * 430.0 * t) * decay(n, 0.022) * 0.5
    leather = band(noise(n, 7), 300.0, 1800.0) * decay(n, 0.014) * 0.8
    metal = partials(n, [1900.0, 3100.0], [0.010, 0.006], 8) * 0.25
    return normalize((thud + knock + leather + metal) * 1.2, 0.5)


def slide_release():
    """Reten de corredera: un tic de acero corto y agudo, sin cola."""
    n = int(0.10 * SR)
    tick = click(n, 0.0035, 31, 2600.0, 9000.0)
    ring = partials(n, [2450.0, 4180.0, 6350.0], [0.010, 0.007, 0.004], 32)
    return normalize(tick + ring * 0.6, 0.38)


def reload_rustle():
    """Ropa y correaje: ruido de banda con dos agarres marcados (sacar el
    cargador, coger el lleno) y nada mas. Es el fondo que hace que la recarga
    no suene a dos clics flotando en silencio."""
    n = int(1.20 * SR)
    t = np.arange(n) / SR
    shape = np.zeros(n)
    for at, width, amp in [(0.10, 0.10, 1.0), (0.42, 0.13, 0.8), (0.78, 0.11, 0.9)]:
        shape += amp * np.exp(-((t - at) ** 2) / (2.0 * width * width))
    wobble = 0.65 + 0.35 * np.abs(np.sin(2.0 * np.pi * 5.5 * t + 0.7))
    cloth = band(noise(n, 51), 700.0, 5200.0) * shape * wobble
    grit = band(noise(n, 52), 180.0, 900.0) * shape * 0.5
    return normalize(cloth + grit, 0.30)


def main():
    os.makedirs(OUT, exist_ok=True)
    print("generando sonidos de recarga en", OUT)
    write("mag_drop.wav", mag_drop())
    write("mag_slap.wav", mag_slap())
    write("slide_release.wav", slide_release())
    write("reload_rustle.wav", reload_rustle())
    print("listo. reimporta con: godot --headless --path . --import")


if __name__ == "__main__":
    main()
