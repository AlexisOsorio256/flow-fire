#!/usr/bin/env python3
"""COBERTURA DEL ARMA POR LOS BRAZOS: mascaras de pantalla, en el encuadre real.

    blender --background --python tools/bench_arms.py -- \
        --arms assets/models/fps_arms.glb --gunspace 1 --mask 1 \
        --out captures/arms_bench/bamen/_mask \
        --states hip,ads,fire_peak,reload_seat,reload_empty_slide,inspect \
        --views eye,3q,side,hand,back
    blender --background --python tools/bench_arms.py -- \
        --arms assets/models/fps_arms.glb --gunspace 1 --mask 1 --hide-arms 1 \
        --out captures/arms_bench/bamen/_mask_gunonly \
        --states hip,ads,fire_peak,reload_seat,reload_empty_slide,inspect --views eye
    python3 tools/coverage_arms.py

POR QUE EXISTE
--------------
"El antebrazo no tapa las miras" es una afirmacion que hay que MEDIR, no mirar.
El banco ya renderiza dos veces el MISMO encuadre de camara del juego (FOV
vertical 82 en cadera, 60 en ADS, transforms del runtime en `frame.json`): una
con los brazos y otra sin ellos.  Un pixel del arma que esta en la mascara
`_gunonly` y NO esta en la mascara con brazos es un pixel que el brazo tapa DE
VERDAD (el z-buffer del render decide quien esta delante, no una suposicion).

Las regiones no son franjas arbitrarias: se proyectan los sockets REALES del
arma (`sight_rear`, `sight_front`, `muzzle`, `ejection_port` de `frame.json`) a
pixeles y se mide alrededor de ellos.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
BENCH = REPO / "captures" / "arms_bench" / "bamen"
FRAME = REPO / "captures" / "arms_bench" / "frame.json"
STATES = ("hip", "ads", "fire_peak", "reload_seat", "reload_empty_slide", "inspect")
## Radio en pixeles de cada region alrededor del socket proyectado.
REGIONS = {
    "miras (rear->front +-12px)": ("sights", 12),
    "corredera alta (+-20px)": ("slide_top", 20),
    "ventana de expulsion (+-28px)": ("ejection_port", 28),
    "boca (+-22px)": ("muzzle", 22),
}


def load(path: Path) -> np.ndarray:
    """RGB en [0,1].  El modo `--mask` del banco pinta el arma de ROJO puro y los
    brazos de VERDE puro sobre fondo negro, asi que el canal que domina dice que
    superficie gano el z-buffer en ese pixel."""
    img = Image.open(path).convert("RGB")
    return np.asarray(img, dtype=np.float32) / 255.0


def gun_mask(rgb: np.ndarray) -> np.ndarray:
    return (rgb[..., 0] > 0.5) & (rgb[..., 1] < 0.5)


def arm_mask(rgb: np.ndarray) -> np.ndarray:
    return (rgb[..., 1] > 0.5) & (rgb[..., 0] < 0.5)


def project(points: list, fov_deg: float, aspect: float, w: int, h: int) -> list:
    """Punto de camara (x,y,z; -z al frente) -> pixel."""
    t = math.tan(math.radians(fov_deg) * 0.5)
    out = []
    for p in points:
        z = -p[2]
        if z <= 1e-6:
            out.append(None)
            continue
        nx = (p[0] / z) / (t * aspect)
        ny = (p[1] / z) / t
        out.append(((nx * 0.5 + 0.5) * w, (0.5 - ny * 0.5) * h))
    return out


def main() -> None:
    frame = json.loads(FRAME.read_text())
    print("%-18s %-30s %8s %8s" % ("estado", "region", "pixeles", "tapado"))
    for state in STATES:
        full_path = BENCH / "_mask" / ("%s_eye.png" % state)
        gun_path = BENCH / "_mask_gunonly" / ("%s_eye.png" % state)
        if not full_path.exists() or not gun_path.exists():
            print("  falta %s o %s" % (full_path.name, gun_path.name))
            continue
        full = load(full_path)
        gun = load(gun_path)
        h, w, _ = gun.shape
        aspect = w / float(h)
        entry = frame["states"][state]
        fov = 60.0 if state == "ads" else 82.0
        # Un pixel es "arma tapada" si en el render SIN brazos es rojo (arma) y
        # en el render CON brazos es verde (el brazo le gano el z-buffer).
        gmask = gun_mask(gun)
        covered = gmask & arm_mask(full)
        pts = {}
        for key in ("sight_rear", "sight_front", "muzzle", "ejection_port"):
            if key in entry:
                pts[key] = project([entry[key]["origin"]], fov, aspect, w, h)[0]
        for label, (kind, radius) in REGIONS.items():
            if kind == "sights":
                if "sight_rear" not in pts or "sight_front" not in pts:
                    continue
                (x0, y0), (x1, y1) = pts["sight_rear"], pts["sight_front"]
                xs = np.arange(max(0, int(min(x0, x1) - radius)), min(w, int(max(x0, x1) + radius) + 1))
                ys = np.arange(max(0, int(min(y0, y1) - radius)), min(h, int(max(y0, y1) + radius) + 1))
                box = np.zeros_like(gmask)
                box[ys[0]:ys[-1] + 1, xs[0]:xs[-1] + 1] = True
            else:
                if kind not in pts:
                    continue
                x, y = pts[kind]
                box = np.zeros_like(gmask)
                box[max(0, int(y - radius)):int(y + radius) + 1,
                    max(0, int(x - radius)):int(x + radius) + 1] = True
            reg = gmask & box
            n = int(reg.sum())
            b = int((covered & reg).sum())
            pct = (100.0 * b / n) if n else 0.0
            print("%-18s %-30s %8d %7.2f%%" % (state, label, n, pct))
        whole = 100.0 * covered.sum() / max(int(gmask.sum()), 1)
        print("%-18s %-30s %8d %7.2f%%" % (state, "ARMA ENTERA", int(gmask.sum()), whole))


if __name__ == "__main__":
    main()
