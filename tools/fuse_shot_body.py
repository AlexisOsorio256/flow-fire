#!/usr/bin/env python3
"""Fusiona un cuerpo grave bajo cada disparo: UNA sola percepcion, no dos capas.

Toma el blast (crack) y el cuerpo (thump), alinea sus PICOS de muestra (<1 ms,
fusionan en un solo evento por Haas, no se oyen como dos golpes) y los mezcla
con el cuerpo a `rel_db` bajo el blast, limitando el pico final al techo.

    python3 tools/fuse_shot_body.py shot_1.wav body.wav -7.0 out.wav

Los niveles de entrada ya vienen normalizados por tools/process_audio.sh; aqui
solo se fija el reparto blast/cuerpo y el techo de pico.
"""
import subprocess
import sys

import numpy as np

SR = 44100
CEILING_DB = -1.2


def load(path):
    p = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "s16le",
         "-acodec", "pcm_s16le", "-ac", "1", "-ar", str(SR), "-"],
        capture_output=True, check=True)
    return np.frombuffer(p.stdout, dtype=np.int16).astype(np.float64) / 32768.0


def save(path, x):
    x = np.clip(x, -1.0, 1.0)
    p = subprocess.run(
        ["ffmpeg", "-v", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1",
         "-i", "-", "-c:a", "pcm_s16le", path, "-y"],
        input=(x * 32767.0).astype(np.int16).tobytes(), capture_output=True)


def main():
    shot_path, body_path, rel_db, out_path = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
    shot = load(shot_path)
    body = load(body_path)
    # Alineacion por pico de muestra: el cuerpo cae EXACTO sobre el blast.
    js = int(np.argmax(np.abs(shot)))
    jb = int(np.argmax(np.abs(body)))
    # Ventana comun que cubre ambos desde un origen compartido.
    start = min(0, js - jb)
    end = max(len(shot), js - jb + len(body))
    mix = np.zeros(end - start)
    # Reparto por picos: el cuerpo cae a rel_db bajo el pico del blast.
    g = (np.abs(shot).max() / max(np.abs(body).max(), 1e-9)) * 10.0 ** (rel_db / 20.0)
    mix[0 - start:len(shot) - start] += shot
    bo = js - jb - start
    mix[bo:bo + len(body)] += body * g
    # La muestra empieza 1 ms antes del ataque del blast: nada de pre-rollo
    # del cuerpo que retrase el disparo.
    keep_from = max(0, (0 - start) - SR // 1000)
    mix = mix[keep_from:]
    # Techo de pico: baja lo justo, sin recortar.
    peak = np.abs(mix).max()
    ceil_lin = 10.0 ** (CEILING_DB / 20.0)
    if peak > ceil_lin:
        mix *= ceil_lin / peak
    save(out_path, mix)
    print("%s + %s (%+.1fdB) -> pico %.1fdBFS" %
          (shot_path.split("/")[-1], body_path.split("/")[-1], rel_db,
           20 * np.log10(np.abs(mix).max())))


if __name__ == "__main__":
    sys.exit(main())
