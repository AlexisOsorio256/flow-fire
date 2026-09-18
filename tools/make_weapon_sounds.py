#!/usr/bin/env python3
"""Genera los WAV del arma que no salen de ningun master. Es sintesis, no
grabacion: cada uno cubre un evento que estaba mudo.

    python3 tools/make_weapon_sounds.py

Escribe en assets/audio/ (16 bits, mono, 44,1 kHz, que es lo que importa Godot):

  mag_drop.wav       el cargador vacio rebotando en el suelo de hormigon
  mag_slap.wav       la palma dando en la culata del cargador al asentarlo
  slide_release.wav  el reten de la corredera al soltarse
  reload_rustle.wav  roce de correaje y ropa mientras se recarga
  mag_insert.wav     el cargador rozando el brocal mientras sube
  chamber_check.wav  la corredera llevada atras un pelo para ver la recamara

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


def chamber_check():
    """Comprobacion de recamara: la corredera se lleva atras un pelo contra el
    muelle y vuelve. Dos clics de acero separados 70 ms y un resorte corto entre
    ellos; no es el golpe del disparo ni la corredera a tope."""
    n = int(0.22 * SR)
    out = np.zeros(n)
    for i, (at, amp, pitch) in enumerate([(0.000, 1.00, 1.00), (0.070, 0.72, 0.92)]):
        start = int(at * SR)
        m = int(0.09 * SR)
        tick = click(m, 0.0028, 71 + i, 2800.0, 9500.0)
        ring = partials(m, [2350.0 * pitch, 4020.0 * pitch, 6120.0 * pitch],
                        [0.008, 0.006, 0.004], 73 + i) * 0.55
        out[start:start + m] += normalize(tick + ring, 1.0) * amp
    # Resorte tensandose entre los dos clics.
    t = np.arange(n) / SR
    zip_ = band(noise(n, 75), 900.0, 3800.0) * np.exp(-np.maximum(t - 0.012, 0.0) / 0.018)
    zip_[:int(0.012 * SR)] = 0.0
    return normalize(out + zip_ * 0.35, 0.42)


def main():
    os.makedirs(OUT, exist_ok=True)
    print("generando sonidos del arma en", OUT)
    write("mag_drop.wav", mag_drop())
    write("mag_slap.wav", mag_slap())
    write("slide_release.wav", slide_release())
    write("reload_rustle.wav", reload_rustle())
    write("mag_insert.wav", mag_insert())
    write("chamber_check.wav", chamber_check())
    print("listo. reimporta con: godot --headless --path . --import")


if __name__ == "__main__":
    main()
