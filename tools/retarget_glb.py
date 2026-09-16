#!/usr/bin/env python3
"""Retarget OFFLINE de las animaciones de un rig de brazos a otro.

Por que offline y no en runtime: el contrato del proyecto prohibe sistemas de
retarget genericos. Aqui se calcula UNA vez en Python y se escribe el resultado
dentro del GLB de destino, asi que en el juego solo queda un AnimationPlayer con
las animaciones ya horneadas sobre el rig nuevo. Nada de IK ni de correcciones
por frame.

Como se emparejan los huesos (sin depender de nombres, que no coinciden):
  1. Brazos y manos: por nombre normalizado (hand/forearm/upper_arm + lado).
  2. Dedos: por la ESTRUCTURA del arbol de cada mano. Se ordenan las cadenas de
     cada mano por la posicion lateral de su punta y se emparejan en orden; el
     pulgar se identifica aparte porque es la cadena cuya punta esta mas lejos
     del eje de los demas dedos.
  3. Dentro de cada cadena, por profundidad (nivel), que es lo que hace
     corresponder falange 1 con falange 1 aunque un rig tenga 4 huesos y el otro 3.

Formulacion del retarget: se conserva el DELTA respecto al reposo de origen y se
aplica al reposo del destino, con la correccion de orientacion entre ambos:
    R_destino = (R_rest_dest * R_rest_src^-1) * delta_src * (R_rest_dest * R_rest_src^-1)^-1
donde delta_src = R_rest_src^-1 * R_src(t). Esto mantiene la orientacion
relativa de cada hueso respecto a su padre, que es lo que define la pose.

Uso: python3 retarget_glb.py <destino.glb> <rig_origen.json> <rig_destino.json> <salida.glb>
"""
import json, struct, sys, copy
import numpy as np

CT = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
FPS = 30.0


def read_glb(p):
    d = open(p, 'rb').read(); off = 12; js = None; b = b''
    while off < len(d):
        ln, ty = struct.unpack_from('<II', d, off)
        ch = d[off+8:off+8+ln]
        if ty == 0x4E4F534A:
            js = json.loads(ch)
        elif ty == 0x004E4942:
            b = ch
        off += 8 + ln
    return js, b


def read_acc(j, b, i):
    a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]
    fmt, sz = CT[a['componentType']]; n = NC[a['type']]
    st = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride') or (sz*n)
    if stride == sz*n:
        o = np.frombuffer(b[st:st+a['count']*stride], dtype=np.dtype('<'+fmt)).astype(np.float64)
    else:
        o = np.empty(a['count']*n)
        for k in range(a['count']):
            o[k*n:(k+1)*n] = struct.unpack_from('<'+fmt*n, b, st+k*stride)
    return o.reshape(a['count'], n) if n > 1 else o


# ---------- cuaterniones ----------
def qmul(a, b):
    ax, ay, az, aw = a; bx, by, bz, bw = b
    return np.array([aw*bx + ax*bw + ay*bz - az*by,
                     aw*by - ax*bz + ay*bw + az*bx,
                     aw*bz + ax*by - ay*bx + az*bw,
                     aw*bw - ax*bx - ay*by - az*bz])


def qconj(q):
    return np.array([-q[0], -q[1], -q[2], q[3]])


def qnorm(q):
    n = np.linalg.norm(q)
    return q/n if n > 1e-12 else np.array([0.0, 0.0, 0.0, 1.0])


def qmat(q):
    x, y, z, w = q; n = x*x+y*y+z*z+w*w
    if n < 1e-12:
        return np.eye(3)
    s = 2.0/n
    return np.array([[1-s*(y*y+z*z), s*(x*y-z*w), s*(x*z+y*w)],
                     [s*(x*y+z*w), 1-s*(x*x+z*z), s*(y*z-x*w)],
                     [s*(x*z-y*w), s*(y*z+x*w), 1-s*(x*x+y*y)]])


def mat2q(m):
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t+1.0)*2
        return np.array([(m[2, 1]-m[1, 2])/s, (m[0, 2]-m[2, 0])/s, (m[1, 0]-m[0, 1])/s, 0.25*s])
    i = int(np.argmax([m[0, 0], m[1, 1], m[2, 2]]))
    if i == 0:
        s = np.sqrt(1.0+m[0, 0]-m[1, 1]-m[2, 2])*2
        return np.array([0.25*s, (m[0, 1]+m[1, 0])/s, (m[0, 2]+m[2, 0])/s, (m[2, 1]-m[1, 2])/s])
    if i == 1:
        s = np.sqrt(1.0+m[1, 1]-m[0, 0]-m[2, 2])*2
        return np.array([(m[0, 1]+m[1, 0])/s, 0.25*s, (m[1, 2]+m[2, 1])/s, (m[0, 2]-m[2, 0])/s])
    s = np.sqrt(1.0+m[2, 2]-m[0, 0]-m[1, 1])*2
    return np.array([(m[0, 2]+m[2, 0])/s, (m[1, 2]+m[2, 1])/s, 0.25*s, (m[1, 0]-m[0, 1])/s])


# ---------- mapeo de huesos ----------
def norm(s):
    return ''.join(ch for ch in s.lower() if ch.isalnum())


def pick(bones, *keys):
    """Primer hueso cuyo nombre normalizado contenga todas las claves."""
    for b in bones:
        n = norm(b)
        if all(k in n for k in keys):
            return b
    return None


def build_mapping(src, dst):
    """Devuelve {nombre_destino: nombre_origen}."""
    s_names = [b['name'] for b in src['bones']]
    d_names = [b['name'] for b in dst['bones']]
    s_by = {b['name']: b for b in src['bones']}
    d_by = {b['name']: b for b in dst['bones']}
    m = {}

    # 1. brazos: se prueban los nombres habituales de los dos packs
    pairs = []
    for side, (sd, ss) in {'L': ('l', 'l'), 'R': ('r', 'r')}.items():
        for dst_keys, src_keys in [
            (('hand', sd), ('hand', ss)),
            (('forearm', sd, '001'), ('forearm', ss, '001')),
            (('forearm', sd), ('forearm', ss)),
            (('upperarm', sd, '001'), ('uparm', ss, '001')),
            (('upperarm', sd), ('uparm', ss)),
            (('shoulder', sd), ('arm', ss)),
        ]:
            d = pick(d_names, *dst_keys)
            s = pick(s_names, *src_keys)
            if d and s:
                pairs.append((d, s))
    for d, s in pairs:
        m[d] = s

    # 2. dedos: por estructura de cada mano
    def hand_chains(names_by, by, hand_name, parent_of):
        """Cadenas que cuelgan de la mano (o de su padre), con geometria."""
        if hand_name is None:
            return []
        out = []
        # hijos directos de la mano
        kids = [n for n in names_by if parent_of.get(n) == hand_name]
        for k in kids:
            chain = [k]
            cur = k
            while True:
                nxt = [n for n in names_by if parent_of.get(n) == cur]
                if not nxt:
                    break
                cur = nxt[0]; chain.append(cur)
            tip = np.array(by[chain[-1]]['head'])
            out.append((chain, tip))
        return out

    def parent_map(by):
        return {b['name']: b['parent'] for b in by}

    for side, (sd, ss) in {'L': ('l', 'l'), 'R': ('r', 'r')}.items():
        d_hand = m.get(pick(d_names, 'hand', sd) or '')
        s_hand = m.get(pick(s_names, 'hand', ss) or '')
        if not d_hand or not s_hand:
            continue
        dp, sp = parent_map(dst['bones']), parent_map(src['bones'])
        dc = hand_chains(d_names, d_by, d_hand, dp)
        sc = hand_chains(s_names, s_by, s_hand, sp)
        if not dc or not sc:
            continue
        # el pulgar es la cadena cuya punta esta mas lejos del eje de las demas
        def split_thumb(chains):
            if len(chains) < 2:
                return chains, None
            tips = np.array([c[1] for c in chains])
            best, bi = -1, 0
            for i in range(len(chains)):
                others = np.delete(tips, i, axis=0)
                ref = others.mean(axis=0)
                d = np.linalg.norm(tips[i]-ref)
                if d > best:
                    best, bi = d, i
            return [c for j, c in enumerate(chains) if j != bi], chains[bi]
        d_rest, d_thumb = split_thumb(dc)
        s_rest, s_thumb = split_thumb(sc)
        # ordenar por coordenada lateral (la que mas varia entre las puntas)
        def order(chains):
            if not chains:
                return []
            tips = np.array([c[1] for c in chains])
            if len(tips) > 1:
                spread = tips.max(axis=0)-tips.min(axis=0)
                ax = int(np.argmax(spread))
            else:
                ax = 0
            return sorted(chains, key=lambda c: c[1][ax])
        for (dch, _), (sch, _) in zip(order(d_rest), order(s_rest)):
            for i, db in enumerate(dch):
                # reparto proporcional: si el destino tiene mas huesos que el
                # origen, el ultimo repite la ultima falange de origen
                si = min(int(round(i*(len(sch)-1)/max(len(dch)-1, 1))), len(sch)-1)
                m[db] = sch[si]
        if d_thumb and s_thumb:
            for i, db in enumerate(d_thumb[0]):
                si = min(int(round(i*(len(s_thumb[0])-1)/max(len(d_thumb[0])-1, 1))), len(s_thumb[0])-1)
                m[db] = s_thumb[0][si]
    return m


def main():
    DST_GLB, SRC_JSON, DST_JSON, OUT = sys.argv[1:5]
    src = json.load(open(SRC_JSON))
    dst = json.load(open(DST_JSON))
    m = build_mapping(src, dst)
    print(f"mapeo: {len(m)} huesos destino")
    for d, s in sorted(m.items()):
        print(f"   {d:28s} <- {s}")

    j, b = read_glb(DST_GLB)
    names = [n.get('name', '') for n in j['nodes']]
    ni_of = {}
    for i, n in enumerate(names):
        ni_of.setdefault(n, i)
    by_name = {b_['name']: b_ for b_ in dst['bones']}

    # --- construir las animaciones retargeteadas ---
    new_anims = []
    for aname, adata in src['animations'].items():
        tracks = adata['tracks']
        dur = adata['duration']
        n_frames = max(2, int(round(dur*FPS))+1)
        times = np.linspace(0.0, dur, n_frames)
        out_tracks = []
        for dbone, sname in m.items():
            st = tracks.get(sname)
            if st is None:
                continue
            r_rest_d = qnorm(np.array(by_name[dbone]['rest_local_rotation']))
            r_rest_s = qnorm(np.array(next(x for x in src['bones'] if x['name'] == sname)['rest_local_rotation']))
            corr = qmul(r_rest_d, qconj(r_rest_s))
            corr_inv = qconj(corr)
            s_times = st['times']
            rots = []
            for t in times:
                i = max(0, min(int(np.searchsorted(s_times, t, side='right')-1), len(s_times)-2))
                f = 0.0 if s_times[i+1] == s_times[i] else (t-s_times[i])/(s_times[i+1]-s_times[i])
                q0 = np.array(st['rot'][i]); q1 = np.array(st['rot'][i+1])
                qs = qnorm(q0*(1-f)+q1*f)
                delta = qmul(qconj(r_rest_s), qs)          # delta respecto al reposo origen
                qd = qmul(qmul(corr, delta), corr_inv)     # aplicado al reposo destino
                rots.append(qnorm(qd))
            out_tracks.append((dbone, rots))
        if not out_tracks:
            continue
        new_anims.append({'name': aname, 'duration': dur, 'times': times, 'tracks': out_tracks})
        print(f"  retarget {aname}: {len(out_tracks)} huesos, {n_frames} frames, {dur:.3f}s")

    # --- escribir: sustituir animaciones por las nuevas y reescribir buffer ---
    j['animations'] = []
    j.setdefault('bufferViews', [])
    buf = bytearray()

    def add_view(raw):
        while len(buf) % 4:
            buf.append(0)
        off = len(buf); buf.extend(raw)
        j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': len(raw)})
        return len(j['bufferViews'])-1

    skin0 = j['skins'][0]['joints']
    joint_index = {names[n]: k for k, n in enumerate(skin0)}

    # accessors existentes -> se recrean
    old_accessors = j['accessors']
    j['accessors'] = []

    def new_acc(arr, comp, typ, with_min=False):
        arr = np.asarray(arr)
        fmt, sz = CT[comp]
        n = NC[typ]
        flat = arr.reshape(-1) if typ == 'SCALAR' else (arr[:, None] if arr.ndim == 1 else arr)
        raw = flat.astype(np.dtype('<'+fmt)).tobytes()
        bvi = add_view(raw)
        a = {'bufferView': bvi, 'componentType': comp, 'count': int(flat.shape[0]), 'type': typ}
        if with_min:
            am = flat.reshape(flat.shape[0], -1)
            a['min'] = [float(x) for x in am.min(axis=0)]
            a['max'] = [float(x) for x in am.max(axis=0)]
        j['accessors'].append(a)
        return len(j['accessors'])-1

    # copiar mallas primero
    mesh_acc_map = {}
    for ai, a in enumerate(old_accessors):
        mesh_acc_map[ai] = None
    # se recrean TODOS los accessors antiguos que sigan referenciados por mallas/skins
    referenced = set()
    for mm in j['meshes']:
        for pr in mm['primitives']:
            for k, v in pr['attributes'].items():
                referenced.add(v)
            if 'indices' in pr:
                referenced.add(pr['indices'])
    for s in j.get('skins', []):
        if 'inverseBindMatrices' in s:
            referenced.add(s['inverseBindMatrices'])
    remap_acc = {}
    for ai in sorted(referenced):
        a = old_accessors[ai]
        arr = read_acc(j, b, ai)
        remap_acc[ai] = new_acc(arr, a['componentType'], a['type'], with_min='min' in a)
    for mm in j['meshes']:
        for pr in mm['primitives']:
            for k in list(pr['attributes'].keys()):
                pr['attributes'][k] = remap_acc[pr['attributes'][k]]
            if 'indices' in pr:
                pr['indices'] = remap_acc[pr['indices']]
    for s in j.get('skins', []):
        if 'inverseBindMatrices' in s:
            s['inverseBindMatrices'] = remap_acc[s['inverseBindMatrices']]

    # imagenes
    for img in j.get('images', []):
        bv = j['bufferViews'][img['bufferView']] if 'bufferView' in img else None
        if bv is None:
            continue
        raw = bytes(buf[bv['byteOffset']:bv['byteOffset']+bv['byteLength']])
        img['bufferView'] = add_view(raw)

    # animaciones nuevas
    for an in new_anims:
        samplers = []
        channels = []
        t_in = new_acc(an['times'], 5126, 'SCALAR', with_min=True)
        for dbone, rots in an['tracks']:
            k = joint_index.get(dbone)
            if k is None:
                continue
            t_out = new_acc(np.array(rots), 5126, 'VEC4')
            samplers.append({'input': t_in, 'interpolation': 'LINEAR', 'output': t_out})
            channels.append({'sampler': len(samplers)-1,
                             'target': {'node': skin0[k], 'path': 'rotation'}})
        j['animations'].append({'name': an['name'], 'samplers': samplers, 'channels': channels})

    while len(buf) % 4:
        buf.append(0)
    j['buffers'] = [{'byteLength': len(buf)}]
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    out = bytearray()
    out += b'glTF' + struct.pack('<II', 2, 12+8+len(js)+8+len(buf))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js
    out += struct.pack('<II', len(buf), 0x004E4942) + bytes(buf)
    open(OUT, 'wb').write(bytes(out))
    print(f"escrito {OUT}  {len(out)/1e6:.2f} MB  animaciones={len(j['animations'])}")


main()
