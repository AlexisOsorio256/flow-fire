#!/usr/bin/env python3
"""Quita las texturas EMBEBIDAS de un .glb dejando la geometria intacta.

POR QUE EXISTE
--------------
`g19_pistol.glb` traia 10.186.698 bytes de imagenes dentro, y esos mismos PNG
estaban YA en `assets/models/g19_pistol_Image_*.png`, byte a byte y con el mismo
sha256. O sea: la misma textura dos veces en el repositorio. Lo mismo pasaba con
`range_shell.glb`, que embebia seis copias de `assets/textures/real/*`.

El runtime vuelve a enganchar los mapas desde su fuente unica
(`GlockWeapon._bind_materials` para el arma, `RangeShell.gd` para la sala), asi
que el .glb solo tiene que llevar GEOMETRIA.

Los accesors apuntan a bufferViews por INDICE, y al borrar los bufferViews de
las imagenes esos indices se desplazan. Recalcular ese mapeo es justo lo que
hace este script; sin el, el .glb queda corrupto y Godot lo rechaza con
"The buffer view size was smaller than the minimum required size for the
accessor".

    python3 tools/strip_glb_textures.py entrada.glb salida.glb
"""
from __future__ import annotations

import copy
import json
import struct
import sys
from pathlib import Path


def read_glb(path: Path):
    d = path.read_bytes()
    magic, version, length = struct.unpack("<III", d[:12])
    if magic != 0x46546C67:
        raise ValueError("no es un GLB")
    off, js, binc = 12, None, None
    while off < len(d):
        clen, ctype = struct.unpack("<II", d[off:off + 8])
        payload = d[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(payload)
        elif ctype == 0x004E4942:
            binc = payload
        off += 8 + clen
    return js, binc, d


def strip(src: Path, dst: Path) -> tuple[int, int]:
    js, binc, original = read_glb(src)
    images = js.get("images", [])
    if not images:
        return 0, len(original)
    dropped = {im["bufferView"] for im in images if "bufferView" in im}
    freed = sum(js["bufferViews"][i]["byteLength"] for i in dropped)

    keep = [i for i in range(len(js["bufferViews"])) if i not in dropped]
    # MAPEO viejo -> nuevo. Esto es lo que faltaba: los accessors guardan el
    # indice, no una referencia, asi que hay que reescribirlo.
    remap = {old: new for new, old in enumerate(keep)}

    new_bvs, blob = [], bytearray()
    for old in keep:
        bv = copy.deepcopy(js["bufferViews"][old])
        start = bv.pop("byteOffset", 0)
        data = binc[start:start + bv["byteLength"]]
        while len(blob) % 4:
            blob.append(0)
        bv["byteOffset"] = len(blob)
        blob += data
        new_bvs.append(bv)
    while len(blob) % 4:
        blob.append(0)

    js["bufferViews"] = new_bvs
    js["buffers"] = [{"byteLength": len(blob)}]
    for accessor in js.get("accessors", []):
        if "bufferView" in accessor:
            accessor["bufferView"] = remap[accessor["bufferView"]]
    for mesh in js.get("meshes", []):
        for prim in mesh.get("primitives", []):
            for target in prim.get("targets", []) or []:
                for key, index in list(target.items()):
                    target[key] = remap[index]

    js.pop("images", None)
    js.pop("textures", None)
    js.pop("samplers", None)
    for mat in js.get("materials", []):
        pbr = mat.get("pbrMetallicRoughness", {})
        for key in ("baseColorTexture", "metallicRoughnessTexture"):
            pbr.pop(key, None)
        for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            mat.pop(key, None)
        mat["pbrMetallicRoughness"] = pbr

    jn = json.dumps(js, separators=(",", ":")).encode("utf-8")
    while len(jn) % 4:
        jn += b" "
    blob = bytes(blob)
    out = b"glTF" + struct.pack("<II", 2, 12 + 8 + len(jn) + 8 + len(blob))
    out += struct.pack("<II", len(jn), 0x4E4F534A) + jn
    out += struct.pack("<II", len(blob), 0x004E4942) + blob
    dst.write_bytes(out)

    # Validacion: cada accessor TIENE que caber en su bufferView.
    comp = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
    for acc in js["accessors"]:
        bv = js["bufferViews"][acc["bufferView"]]
        need = acc["count"] * ncomp[acc["type"]] * comp[acc["componentType"]]
        if need > bv["byteLength"]:
            raise RuntimeError("accessor no cabe en su bufferView")
    return freed, len(out)


def main() -> int:
    src = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/models/g19_pistol.glb")
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else src
    freed, size = strip(src, dst)
    print("%s -> %.3f MB (imagenes liberadas: %.1f KB)" % (dst, size / 1048576, freed / 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())
