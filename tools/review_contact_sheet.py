#!/usr/bin/env python3
"""Hoja de contacto para revisar UNA accion rapida del juego real.

No es un test, no calcula metricas, no da veredictos: graba la accion a
suficientes FPS y reune los frames en UNA sola PNG para mirarla de una vez.

Se ejecuta con el renderer del proyecto (Mobile/Vulkan), no forzando
Compatibility/OpenGL: la hoja debe ensenar lo que el juego dibuja de verdad.

    python3 tools/review_contact_sheet.py fire
    python3 tools/review_contact_sheet.py reload | reload_empty | inspect | idle
    python3 tools/review_contact_sheet.py burst   (rafaga de 4, apila retroceso)

Sale en captures/review/<accion>_sheet.png. Los frames temporales se borran.
Para fuego usa burst denso (~60 FPS durante ~0.8 s); para acciones lentas,
muestreo espaciado. Cada celda lleva solo su +ms desde la ignicion.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "captures", "review")

# Accion: (frames a grabar, camara lenta, selector de frames, columnas)
# El selector recibe la lista ordenada de frames y devuelve los que van a la hoja.
# La camara lenta estira el tiempo DE JUEGO para que el readback (lento en este
# PC) siga dando densidad suficiente: las etiquetas +ms son de juego, no reales.
PRESETS = {
    # Burst denso: ~30 frames en ~0.8 s de juego (pico ~50 ms, vuelta ~250 ms).
    "fire": (30, 0.08, lambda fs: fs, 6),
    "burst": (40, 0.08, lambda fs: fs, 8),
    "pen": (30, 0.25, lambda fs: fs, 6),
    "ads": (30, 0.25, lambda fs: fs, 6),
    "crate": (30, 0.25, lambda fs: fs, 6),
    "steel": (30, 0.25, lambda fs: fs, 6),
    # La recarga dura 2,10 s (2,35 s en seco): a 34 ms de juego por frame
    # hacen falta 66/76 frames para ver el final (suelta de corredera y vuelta
    # a bateria), no solo la mitad.
    "reload": (66, 0.25, lambda fs: fs[::4], 7),
    "reload_empty": (76, 0.25, lambda fs: fs[::4], 7),
    "inspect": (46, 0.30, lambda fs: fs[::3], 6),
    "idle": (10, 1.0, lambda fs: fs[::2], 5),
}

CELL_W = 320
# Recorte a la zona del arma (el viewmodel vive abajo-centro del encuadre).
CROP = (230, 250, 730, 540)
# Pen entra por los ojos del tirador: cuadro completo para leer el blanco.
# Ads mira por las miras: centro del encuadre.
# Recarga e inspeccion: el arma sube al centro-bajo y el cargador sale por
# debajo, asi que el recorte baja hasta el borde para poder juzgar el gesto
# (a 500 px el arma son 30 px y no se ve ni el cargador ni el brocal).
CROPS = {
    "pen": (0, 0, 960, 540),
    "ads": (330, 150, 630, 390),
    "crate": (0, 0, 960, 540),
    "steel": (0, 0, 960, 540),
    "reload": (300, 235, 700, 540),
    "reload_empty": (300, 235, 700, 540),
    "inspect": (300, 235, 700, 540),
}


def parse_ms(name):
    m = re.search(r"_(\d+)ms\.png$", name)
    return int(m.group(1)) if m else 0


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "fire"
    if action not in PRESETS:
        print("accion desconocida:", action, "(fire|burst|pen|ads|crate|steel|reload|reload_empty|inspect|idle)")
        return 1
    total, ts, select, cols = PRESETS[action]
    tmp = tempfile.mkdtemp(prefix="review_frames_")
    try:
        cmd = [
            "godot4", "--path", REPO,
            "--audio-driver", "Dummy",
            "--resolution", "960x540",
            "--display-driver", "x11",
            "tools/review_capture.tscn",
            "--", "--action=" + action, "--out=" + tmp,
            "--warmup=40", "--total=%d" % total,
            "--time-scale=%s" % ts,
        ]
        proc = subprocess.run(cmd, check=True, capture_output=True, cwd=REPO)
        for line in (proc.stdout.decode() + proc.stderr.decode()).splitlines():
            # Lo unico que importa del log: disparos REALES (senal shot_fired),
            # no intentos. Si la hoja dice "rafaga de 4" esto debe decir 4.
            if "REVIEW disparos" in line:
                print(line.strip())
        frames = sorted(
            (f for f in os.listdir(tmp) if f.endswith(".png")),
            key=lambda f: int(f.split("_")[1]),
        )
        if not frames:
            print("no se capturo ningun frame")
            return 1
        chosen = select(frames)
        crop = CROPS.get(action, CROP)
        cells = []
        for f in chosen:
            img = Image.open(os.path.join(tmp, f)).convert("RGB")
            img = img.crop(crop)
            # Descarta frames del apagado (viewport ya cerrada al salir).
            thumb = img.resize((32, 32))
            if sum(thumb.convert("L").getdata()) / (32 * 32) < 8:
                continue
            h = int(img.height * CELL_W / img.width)
            img = img.resize((CELL_W, h), Image.BILINEAR)
            d = ImageDraw.Draw(img)
            d.rectangle([2, 2, 78, 20], fill=(0, 0, 0))
            d.text((6, 5), "+%d ms" % parse_ms(f), fill=(255, 255, 0))
            cells.append(img)
        cw, ch = cells[0].size
        rows = (len(cells) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cw, rows * ch), (10, 10, 10))
        for i, img in enumerate(cells):
            sheet.paste(img, ((i % cols) * cw, (i // cols) * ch))
        os.makedirs(OUT_DIR, exist_ok=True)
        out = os.path.join(OUT_DIR, action + "_sheet.png")
        sheet.save(out)
        print("hoja:", out, "(%d frames de %d)" % (len(cells), len(frames)))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
