#!/usr/bin/env python3
"""Deja un rig de brazos de FPS en SOLO lo que el viewmodel usa de verdad.

El pack de 1Matzh viene como escaparate completo: 12 mallas (pistola, skybox,
ayudantes de apuntado), 1068 huesos y 9 clips a densidad de exportacion. De todo
eso el viewmodel solo necesita las mallas del personaje, los huesos que las
deforman, los clips que reproduce y las texturas que esas mallas pintan.

Que hace, exactamente:

  - Conserva las mallas de `KEEP_MESHES` y su cadena de nodos padre.
  - Conserva los huesos con peso en esas mallas MAS su cadena de ancestros
    (sin la cadena, la pose no se puede componer) y el `inverseBindMatrices`
    de esos huesos, en el orden nuevo.
  - Reescribe las animaciones de esos huesos a `FPS` fotogramas por segundo.
    El original guarda una clave por fotograma de Blender; a la distancia del
    viewmodel, 60 Hz es indistinguible y multiplica el tamano por ~20.
  - Conserva solo las texturas que pintan los materiales que quedan, con tope de
    resolucion por material.
  - Renombra los nodos que el codigo toca para que el runtime no busque patrones.
  - Comprueba al final que cada vertice conserva exactamente sus pesos
    originales (mismos huesos, mismos pesos, reindexados). Si eso falla, no
    escribe la salida.

El asset de origen ya no vive en el repo (pesa 102 MB). Para reproducirlo:
  git show fb95cc3:assets/models/deagle_arms.glb > /tmp/deagle_arms.glb
  python3 tools/prune_arms.py /tmp/deagle_arms.glb assets/models/arms.glb
"""
import json, struct, sys

import numpy as np

FPS = 60
KEEP_MESHES = {
    "Mesh_Cloths_0": "Sleeves",
    "Mesh_Watch_0": "Watch",
    "Mesh_Watch_Emission_0": "Watch_Emission",
    "Mesh_Body_0": "Body",
    "Mesh_Gloves_0": "Gloves",
}
KEEP_CLIPS = {"Idle", "Fire", "Reload", "Reload_Empty", "Inspect"}
RENAME_BONES = {
    "DEF-hand.L_0458": "Hand_L",
    "DEF-hand.R_0583": "Hand_R",
}
MAX_PX = {"Watch": 512, "Watch_Emission": 512, "Body": 512}

CT = {5120: ("b", "BYTE", 1), 5121: ("B", "UNSIGNED_BYTE", 1),
      5122: ("h", "SHORT", 2), 5123: ("H", "UNSIGNED_SHORT", 2),
      5125: ("I", "UNSIGNED_INT", 4), 5126: ("f", "FLOAT", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    d = open(path, "rb").read()
    assert d[:4] == b"glTF", "no es un GLB"
    off, js, bin_ = 12, None, b""
    while off < len(d):
        ln, ty = struct.unpack_from("<II", d, off)
        ch = d[off + 8:off + 8 + ln]
        if ty == 0x4E4F534A:
            js = json.loads(ch)
        elif ty == 0x004E4942:
            bin_ = ch
        off += 8 + ln
    return js, bin_


class Src:
    def __init__(self, js, bin_):
        self.js, self.bin_ = js, bin_

    def view(self, i):
        a = self.js["accessors"][i]
        bv = self.js["bufferViews"][a["bufferView"]]
        fmt, _, sz = CT[a["componentType"]]
        n = NC[a["type"]]
        stride = bv.get("byteStride") or sz * n
        base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        out = np.empty((a["count"], n), dtype=np.dtype(fmt))
        raw = np.frombuffer(self.bin_, dtype=np.dtype(fmt), count=-1, offset=base)
        if stride == sz * n:
            out = raw[: a["count"] * n].reshape(a["count"], n)
        else:
            step = stride // sz
            out = raw[: (a["count"] - 1) * step + n].reshape(-1, step)[:, :n]
        return out

    def bytes_of_view(self, bv_index):
        bv = self.js["bufferViews"][bv_index]
        o = bv.get("byteOffset", 0)
        return self.bin_[o:o + bv["byteLength"]]


class Dst:
    """Constructor de glTF: asigna bufferViews y accessors en orden."""

    def __init__(self):
        self.blobs = []
        self.bufferViews = []
        self.accessors = []
        self._acc_cache = {}

    def blob(self, raw, target=None):
        off = sum(len(b) for b in self.blobs)
        self.blobs.append(raw)
        bv = {"buffer": 0, "byteOffset": off, "byteLength": len(raw)}
        if target:
            bv["target"] = target
        self.bufferViews.append(bv)
        return len(self.bufferViews) - 1

    def accessor(self, arr, component_type, type_name, normalized=False,
                 target=None, bounds=False):
        arr = np.ascontiguousarray(arr)
        key = (arr.tobytes(), component_type, type_name, normalized)
        if key in self._acc_cache:
            return self._acc_cache[key]
        bv = self.blob(arr.tobytes(), target)
        acc = {"bufferView": bv, "componentType": component_type,
               "count": len(arr), "type": type_name}
        if normalized:
            acc["normalized"] = True
        if bounds:
            f = arr.astype(np.float64)
            acc["min"] = [float(x) for x in f.min(axis=0)]
            acc["max"] = [float(x) for x in f.max(axis=0)]
        self.accessors.append(acc)
        self._acc_cache[key] = len(self.accessors) - 1
        return len(self.accessors) - 1

    def json(self):
        return {"bufferViews": self.bufferViews, "accessors": self.accessors,
                "buffers": [{"byteLength": sum(len(b) for b in self.blobs)}],
                "bin": b"".join(self.blobs)}


def sample_rotation(times, quats, out_t):
    """Slerp por tramos, como manda glTF para rotaciones lineales."""
    idx = np.clip(np.searchsorted(times, out_t, side="right") - 1, 0, len(times) - 2)
    t0, t1 = times[idx], times[idx + 1]
    u = np.where(t1 > t0, (out_t - t0) / np.maximum(t1 - t0, 1e-9), 0.0)[:, None]
    a, b = quats[idx].astype(np.float64), quats[idx + 1].astype(np.float64)
    dot = np.sum(a * b, axis=1, keepdims=True)
    b = np.where(dot < 0.0, -b, b)
    dot = np.abs(dot)
    near = dot > 0.9995
    # lerp donde el arco es casi nulo (evita dividir por seno ~0); slerp al resto
    lin = a + u * (b - a)
    lin /= np.linalg.norm(lin, axis=1, keepdims=True)
    th = np.arccos(np.clip(dot, -1.0, 1.0))
    s = np.where(np.sin(th) < 1e-6, 1.0, np.sin(th))
    sl = (np.sin((1 - u) * th) * a + np.sin(u * th) * b) / s
    nrm = np.linalg.norm(sl, axis=1, keepdims=True)
    sl /= np.where(nrm < 1e-9, 1.0, nrm)
    return np.where(near, lin, sl)


def main(src_path, out_path):
    js, bin_ = read_glb(src_path)
    src = Src(js, bin_)
    nodes = js["nodes"]
    parents = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parents[c] = i

    # --- 1. mallas que se quedan -------------------------------------------
    keep_mesh_nodes = {}
    for i, n in enumerate(nodes):
        mi = n.get("mesh")
        if mi is None or "skin" not in n:
            continue
        name = js["meshes"][mi].get("name")
        if name in KEEP_MESHES:
            keep_mesh_nodes[i] = name
    missing = set(KEEP_MESHES) - set(keep_mesh_nodes.values())
    assert not missing, f"no encontre estas mallas en el GLB: {missing}"

    skin = js["skins"][0]
    joints = skin["joints"]

    def chain(i):
        out = []
        while i is not None:
            out.append(i)
            i = parents.get(i)
        return out

    keep_nodes = set()
    for i in keep_mesh_nodes:
        keep_nodes |= set(chain(i))

    # --- 2. huesos que se quedan: los que pesan + su cadena ----------------
    used = set()
    for i in keep_mesh_nodes:
        for pr in js["meshes"][nodes[i]["mesh"]]["primitives"]:
            j = src.view(pr["attributes"]["JOINTS_0"]).reshape(-1, 4)
            w = src.view(pr["attributes"]["WEIGHTS_0"]).reshape(-1, 4)
            used |= {int(x) for x in np.unique(j[w > 0.0])}
    assert used, "ninguna malla usa huesos"
    keep_nodes |= {a for u in used for a in chain(joints[u])}
    # El skin conserva el orden del original: asi el inverseBindMatrices de los
    # huesos que quedan es un subconjunto contiguo y el reindexado es directo.
    keep_joints = [k for k, j in enumerate(joints) if j in keep_nodes]
    mapa_joint = {k: i for i, k in enumerate(keep_joints)}
    assert used <= set(keep_joints)

    # --- 3. orden nuevo de nodos (padres antes que hijos) ------------------
    order = sorted(keep_nodes, key=lambda i: (len(chain(i)), i))
    new_index = {old: k for k, old in enumerate(order)}

    # --- 4. nombre nuevo de los nodos que el codigo toca -------------------
    def out_name(old):
        n = nodes[old].get("name", "nodo")
        if old in keep_mesh_nodes:
            return KEEP_MESHES[keep_mesh_nodes[old]]
        return RENAME_BONES.get(n, n)

    # --- 5. materiales, texturas e imagenes que se quedan ------------------
    used_mats = []
    for i in keep_mesh_nodes:
        for pr in js["meshes"][nodes[i]["mesh"]]["primitives"]:
            used_mats.append(pr["material"])
    used_mats = sorted(set(used_mats))

    def textures_of(mat):
        out = []

        def walk(o):
            if isinstance(o, dict):
                for k, v in o.items():
                    if k.endswith("Texture") and isinstance(v, dict) and "index" in v:
                        out.append(v["index"])
                    else:
                        walk(v)
        walk(mat)
        return out

    used_tex = sorted({t for m in used_mats for t in textures_of(js["materials"][m])})
    used_img = sorted({js["textures"][t]["source"] for t in used_tex
                       if "source" in js["textures"][t]})
    tex_new = {t: k for k, t in enumerate(used_tex)}
    img_new = {s: k for k, s in enumerate(used_img)}
    mat_new = {m: k for k, m in enumerate(used_mats)}
    print(f"materiales {len(used_mats)}/{len(js['materials'])}  "
          f"texturas {len(used_tex)}/{len(js['textures'])}  "
          f"imagenes {len(used_img)}/{len(js.get('images', []))}")

    # --- 6. escribir el glTF nuevo ----------------------------------------
    dst = Dst()
    out_materials = []
    for m in used_mats:
        mat = json.loads(json.dumps(js["materials"][m]))

        def fix(o):
            if isinstance(o, dict):
                for k, v in list(o.items()):
                    if k.endswith("Texture") and isinstance(v, dict) and "index" in v:
                        v["index"] = tex_new[v["index"]]
                    else:
                        fix(v)
        fix(mat)
        out_materials.append(mat)

    out_textures = []
    for t in used_tex:
        tex = json.loads(json.dumps(js["textures"][t]))
        if "source" in tex:
            tex["source"] = img_new[tex["source"]]
        out_textures.append(tex)

    out_images = []
    shrunk = []
    for s in used_img:
        im = js["images"][s]
        raw = src.bytes_of_view(im["bufferView"])
        limit, dueno = 0, "?"
        for m in used_mats:
            mat = js["materials"][m]
            if any(js["textures"][t].get("source") == s for t in textures_of(mat)):
                if MAX_PX.get(mat["name"], 0) > limit:
                    limit, dueno = MAX_PX[mat["name"]], mat["name"]
        if limit:
            raw = shrink_png(raw, limit)
            shrunk.append((dueno, limit))
        d = {"mimeType": im.get("mimeType", "image/png")}
        if "name" in im:
            d["name"] = im["name"]
        d["bufferView"] = dst.blob(raw)
        out_images.append(d)
    for nm, px in shrunk:
        print(f"  textura de {nm} reducida a {px}px")

    # --- 7. mallas ---------------------------------------------------------
    out_meshes, mesh_new = [], {}
    for old in keep_mesh_nodes:
        mi = nodes[old]["mesh"]
        m = js["meshes"][mi]
        prims = []
        for pr in m["primitives"]:
            attrs = {}
            for k, acc in pr["attributes"].items():
                a = js["accessors"][acc]
                ctype = CT[a["componentType"]][0]
                arr = src.view(acc)
                if k == "JOINTS_0":
                    arr = np.vectorize(mapa_joint.__getitem__)(arr)
                attrs[k] = dst.accessor(
                    arr.astype(ctype), a["componentType"], a["type"],
                    normalized=a.get("normalized", False),
                    target=34962, bounds=(k == "POSITION"))
            ia = js["accessors"][pr["indices"]]
            idx = src.view(pr["indices"])
            prim = {"attributes": attrs,
                    "indices": dst.accessor(idx.astype(CT[ia["componentType"]][0]),
                                            ia["componentType"], "SCALAR", target=34963),
                    "material": mat_new[pr["material"]]}
            if "mode" in pr:
                prim["mode"] = pr["mode"]
            prims.append(prim)
        out_meshes.append({"name": KEEP_MESHES[keep_mesh_nodes[old]], "primitives": prims})
        mesh_new[old] = len(out_meshes) - 1

    # --- 8. skin -----------------------------------------------------------
    ibm = src.view(skin["inverseBindMatrices"]).reshape(len(joints), 16)
    ibm_out = np.ascontiguousarray(ibm[keep_joints]).reshape(-1, 16).astype(np.float32)
    out_skin = {"joints": [new_index[joints[k]] for k in keep_joints],
                "inverseBindMatrices": dst.accessor(ibm_out, 5126, "MAT4")}
    if "skeleton" in skin:
        out_skin["skeleton"] = new_index[skin["skeleton"]]
    if "name" in skin:
        out_skin["name"] = skin["name"]

    # --- 9. nodos ----------------------------------------------------------
    out_nodes = []
    for old in order:
        n = nodes[old]
        d = {"name": out_name(old)}
        for k in ("translation", "rotation", "scale", "matrix"):
            if k in n:
                d[k] = n[k]
        kids = [new_index[c] for c in n.get("children", []) if c in keep_nodes]
        if kids:
            d["children"] = kids
        if old in keep_mesh_nodes:
            d["mesh"] = mesh_new[old]
            d["skin"] = 0
        out_nodes.append(d)

    # --- 10. animaciones, remuestreadas -----------------------------------
    out_anims, dropped_tracks = [], 0
    for a in js["animations"]:
        short = a["name"].split("|")[-1]
        if short not in KEEP_CLIPS:
            continue
        channels, samplers = [], []
        by_target = {}
        for ch in a["channels"]:
            tgt = ch["target"]
            if tgt.get("path") != "rotation" or tgt["node"] not in keep_nodes:
                dropped_tracks += 1
                continue
            by_target.setdefault(tgt["node"], ch["sampler"])
        for node_old, s in by_target.items():
            smp = a["samplers"][s]
            t = src.view(smp["input"])[:, 0].astype(np.float64)
            q = src.view(smp["output"]).astype(np.float64)
            n_out = max(2, int(round(float(t[-1]) * FPS)) + 1)
            t_out = np.linspace(0.0, float(t[-1]), n_out)
            q_out = sample_rotation(t, q, t_out)
            channels.append({"sampler": len(samplers),
                             "target": {"node": new_index[node_old], "path": "rotation"}})
            samplers.append({"input": dst.accessor(t_out.astype(np.float32), 5126, "SCALAR"),
                             "output": dst.accessor(q_out.astype(np.float32), 5126, "VEC4"),
                             "interpolation": "LINEAR"})
        out_anims.append({"name": short, "channels": channels, "samplers": samplers})

    # --- 11. comprobar pesos: mismo hueso, mismo peso, reindexado ----------
    built = dst.json()
    blob = built["bin"]

    def read_acc(i):
        a = built["accessors"][i]
        bv = built["bufferViews"][a["bufferView"]]
        fmt, _, sz = CT[a["componentType"]]
        n = NC[a["type"]]
        raw = np.frombuffer(blob, dtype=np.dtype(fmt),
                            count=a["count"] * n, offset=bv["byteOffset"])
        return raw.reshape(a["count"], n)

    ok = True
    mapa = np.array(keep_joints, dtype=np.int64)  # indice nuevo -> indice original
    for old in keep_mesh_nodes:
        m_old = js["meshes"][nodes[old]["mesh"]]
        m_new = out_meshes[mesh_new[old]]
        for pr_old, pr_new in zip(m_old["primitives"], m_new["primitives"]):
            j0 = src.view(pr_old["attributes"]["JOINTS_0"]).reshape(-1, 4).astype(np.int64)
            w0 = src.view(pr_old["attributes"]["WEIGHTS_0"]).reshape(-1, 4).astype(np.float32)
            j1 = read_acc(pr_new["attributes"]["JOINTS_0"]).astype(np.int64)
            w1 = read_acc(pr_new["attributes"]["WEIGHTS_0"]).astype(np.float32)
            if not np.allclose(np.sort(w0, axis=1), np.sort(w1, axis=1), atol=1e-6):
                ok = False
                print(f"  PESOS DISTINTOS (valor) en {nodes[old]['name']}")
                continue
            for k in range(4):
                orig = np.where(w0[:, k] > 0.0, j0[:, k], -1)
                got = np.where(w1[:, k] > 0.0, mapa[j1[:, k]], -1)
                if not np.array_equal(orig, got):
                    ok = False
                    print(f"  PESOS DISTINTOS (hueso) en {nodes[old]['name']} ranura {k}")
    print("pesos: " + ("identicos al original" if ok else "DISTINTOS"))

    out = {"asset": {"version": "2.0",
                     "generator": "tools/prune_arms.py (FlowFire)"},
           "scene": 0,
           "scenes": [{"name": "arms", "nodes": [new_index[js["scenes"][0]["nodes"][0]]]}]}
    for k in ("extensionsUsed", "extensionsRequired"):
        if k in js:
            out[k] = js[k]
    out["nodes"] = out_nodes
    out["meshes"] = out_meshes
    out["materials"] = out_materials
    out["textures"] = out_textures
    out["images"] = out_images
    if "samplers" in js:
        out["samplers"] = js["samplers"]
    out["skins"] = [out_skin]
    out["animations"] = out_anims
    out["accessors"] = built["accessors"]
    out["bufferViews"] = built["bufferViews"]
    out["buffers"] = built["buffers"]

    jb = json.dumps(out, separators=(",", ":")).encode()
    jb += b" " * (-len(jb) % 4)
    bb = built["bin"] + b"\x00" * (-len(built["bin"]) % 4)
    glb = (b"glTF" + struct.pack("<II", 2, 12 + 8 + len(jb) + 8 + len(bb))
           + struct.pack("<II", len(jb), 0x4E4F534A) + jb
           + struct.pack("<II", len(bb), 0x004E4942) + bb)
    if ok:
        open(out_path, "wb").write(glb)
    print(f"nodos {len(keep_nodes)}/{len(nodes)}  huesos {len(keep_joints)}/{len(joints)}  "
          f"mallas {len(out_meshes)}/{len(js['meshes'])}  clips {len(out_anims)}  "
          f"pistas fuera {dropped_tracks}")
    print(f"{out_path}: {len(glb)/1e6:.2f} MB " + ("(escrito)" if ok else "(NO escrito)"))


def shrink_png(raw, max_px):
    from io import BytesIO
    from PIL import Image
    im = Image.open(BytesIO(raw))
    if max(im.size) <= max_px:
        return raw
    im = im.resize((max_px, max_px), Image.LANCZOS)
    buf = BytesIO()
    im.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
