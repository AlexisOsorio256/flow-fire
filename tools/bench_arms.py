"""BANCO DE BRAZOS: mira el brazo contra NUESTRA Glock antes de tocar Godot.

    blender --background --python tools/bench_arms.py -- \
        --arms downloads/models/lo_que_sea/scene.gltf \
        --out captures/arms_bench/candidato_a

POR QUE EXISTE
--------------
Un AABB no certifica un brazo. La pasada anterior aprobo un antebrazo por
coordenadas y en la primera captura real tapaba el arma y el fogonazo. Este
banco coloca el arma y el brazo en el MISMO encuadre que el juego, que sale de
`tools/frame_probe.tscn` (transforms reales del runtime, no constantes
recalculadas), y renderiza los estados que importan: cadera, ADS, el hito en que
el cargador entra, el asiento, la inspeccion y el pico de retroceso.

CAMARAS
-------
- `eye`:  la camara del juego (FOV vertical 82 en cadera, 60 en ADS), 16:9. Es
  la que decide si el brazo TAPA el arma, las miras o el fogonazo.
- `3q`:   orbita 3/4 sobre la empuñadura, para juzgar el agarre de la mano.
- `side`: lateral sobre la empuñadura.
- `top`:  planta sobre la empuñadura.

ESPACIO DE TRABAJO
------------------
El candidato se mide SIEMPRE en el espacio del arma (mismo sistema que el GLB
`g19_pistol.glb`: +Y arriba, -Z al morro, origen en la raiz del arma). El brazo
se mueve con `--pos/--rot-deg/--scale`, que en el juego se convierten en UNA
linea: `ArmsRig.global_transform = Weapon.global_transform` al montar (el arma
esta en reposo en ese instante, asi que la cadena entera es identidad).
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Matrix, Vector

REPO = Path(__file__).resolve().parents[1]
GUN = REPO / "assets" / "models" / "g19_pistol.glb"
DEFAULT_FRAME = REPO / "captures" / "arms_bench" / "frame.json"


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--arms", default="", help="GLB/GLTF/FBX/BLEND del candidato")
    p.add_argument("--out", default="captures/arms_bench/banca")
    p.add_argument("--frame", default=str(DEFAULT_FRAME))
    p.add_argument("--states", default="hip,ads,reload_in,reload_seat,inspect,fire_peak")
    p.add_argument("--views", default="eye,3q,side,top")
    p.add_argument("--pos", default="0,0,0")
    p.add_argument("--rot-deg", default="0,0,0")
    p.add_argument("--scale", type=float, default=1.0)
    p.add_argument("--res", type=int, default=960)
    p.add_argument("--clay", type=int, default=1, help="1 = material neutro (juzga forma)")
    p.add_argument("--hide-arms", type=int, default=0)
    p.add_argument("--gun", type=int, default=1, help="0 = no importar la Glock")
    p.add_argument("--action", default="", help="accion del donante que se aplica al brazo")
    p.add_argument("--action-frame", type=float, default=-1.0,
                   help="segundo concreto de la accion; <0 = primer frame")
    p.add_argument("--arms-only", type=int, default=0,
                   help="1 = ignora el frame.json y encuadra el brazo entero")
    p.add_argument("--subdiv", type=int, default=0,
                   help="niveles de subdivision Catmull-Clark sobre la malla del brazo")
    ## El importador glTF de Blender mete TODO asset en (x,-z,y) respecto del
    ## glTF: mete el morro del arma en +Y de Blender.  La camara `eye` del banco
    ## mira con +Y arriba, asi que sin corregir esto la vista `eye` sale girada
    ## 90 grados sobre X respecto del juego (mira la escena desde ARRIBA: el
    ## morro del arma apunta hacia arriba en pantalla en vez de hacia dentro).
    ## POR DEFECTO SE CORRIGE (1). El importador glTF mete todo asset en
    ## (x, -z, y) —Y-arriba a Z-arriba— y esta banca coloca las matrices en
    ## espacio del juego, asi que sin deshacer esa conversion la vista `eye`
    ## renderiza la escena girada 90 grados sobre X: mira el arma DESDE ARRIBA
    ## en vez de por el anima. Con el valor por defecto anterior (0) la banca
    ## certificaba un agarre que el juego no dibuja, que es justo el fallo que
    ## este banco existe para evitar. `--gunspace 0` solo reproduce aquel
    ## encuadre roto, para depurar.
    p.add_argument("--gunspace", type=int, default=1,
                   help="1 (por defecto) = vista eye fiel al juego; 0 = encuadre roto antiguo, solo para depurar")
    ## El banco nacio con un sujeto de 0,6 m y tres area lights de 90/32/45 W:
    ## a la distancia de orbita del puño (0,13-0,26 m) el clay sale QUEMADO y no
    ## se puede juzgar ni el agarre ni los dedos. `--exposure` (paradas) y
    ## `--light` (multiplicador) dejan bajarlo sin tocar el encuadre. Con los
    ## valores por defecto el comportamiento es el de siempre.
    p.add_argument("--exposure", type=float, default=0.0,
                   help="paradas de exposicion (negativo = menos luz de escena)")
    p.add_argument("--light", type=float, default=1.0,
                   help="multiplicador de la energia de las tres luces")
    p.add_argument("--mask", type=int, default=0,
                   help="1 = arma en rojo y brazos en verde (mide cobertura)")
    return p.parse_args(argv)


## Subdivir un brazo de 1176 tris NO inventa detalle: redondea una aproximacion
## facetada de un cilindro, que es lo que un brazo es. Se mide antes de decidir:
## si no mejora la lectura, no se paga.
def subdivide(objects: list, levels: int) -> None:
    for obj in objects:
        if obj.type != "MESH":
            continue
        mod = obj.modifiers.new("Banca_Subdiv", "SUBSURF")
        mod.levels = levels
        mod.render_levels = levels
        # `boundary_smooth = ALL`: con el valor por defecto, Catmull-Clark tira de
        # los bordes abiertos (la muneca) y abre una muesca en V. Los bordes
        # abiertos no son costuras invisibles: son el corte del brazo.
        mod.boundary_smooth = "ALL"
        bpy.context.view_layer.objects.active = obj
        for m in list(obj.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except RuntimeError as exc:
                print("BANCA aviso: no se pudo aplicar", m.name, exc)
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        print("BANCA subdiv %d -> %s tris=%d" % (levels, obj.name, tris))


def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for group in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
                  bpy.data.armatures, bpy.data.actions, bpy.data.images,
                  bpy.data.cameras, bpy.data.lights):
        for item in list(group):
            if item.users == 0:
                group.remove(item)


def import_any(path: Path) -> list:
    """Importa lo que sea y devuelve los objetos de nivel raiz que trajo."""
    before = set(bpy.data.objects)
    suffix = path.suffix.lower()
    if suffix in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(path))
    elif suffix == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(path))
    elif suffix == ".blend":
        with bpy.data.libraries.load(str(path)) as (src, dst):
            dst.objects = list(src.objects)
        for obj in dst.objects:
            if obj is not None:
                bpy.context.scene.collection.objects.link(obj)
    elif suffix == ".obj":
        bpy.ops.wm.obj_import(filepath=str(path))
    else:
        raise SystemExit("Formato no soportado: %s" % suffix)
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    return roots


def xform_from_json(entry: dict) -> Matrix:
    basis = entry["basis"]
    m = Matrix((
        (basis[0][0], basis[1][0], basis[2][0], entry["origin"][0]),
        (basis[0][1], basis[1][1], basis[2][1], entry["origin"][1]),
        (basis[0][2], basis[1][2], basis[2][2], entry["origin"][2]),
        (0.0, 0.0, 0.0, 1.0),
    ))
    return m


def neutral_material() -> bpy.types.Material:
    mat = bpy.data.materials.new("Banca_Clay")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.62, 0.60, 0.58, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.62
    return mat


def flat_material(name: str, color: tuple) -> bpy.types.Material:
    """Material de EMISION plano: para medir cobertura hay que poder separar
    "pixel de arma" de "pixel de brazo" sin dudas.  Con el clay de siempre los
    dos son claros y del mismo orden de luminancia, asi que una mascara por
    brillo confunde mano y pistola (se probo: daba 2% de cobertura donde el
    brazo tapaba media corredera).  Rojo y verde puros no se confunden."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emi = nt.nodes.new("ShaderNodeEmission")
    emi.inputs[0].default_value = (color[0], color[1], color[2], 1.0)
    emi.inputs[1].default_value = 1.0
    nt.links.new(emi.outputs[0], out.inputs[0])
    return mat


def clayskin() -> bpy.types.Material:
    mat = bpy.data.materials.new("Banca_Piel")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.72, 0.55, 0.45, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.55
    return mat


def apply_clay(objects: list, mat, keep=()) -> None:
    for obj in objects:
        if obj.type != "MESH" or obj.name in keep:
            continue
        obj.data.materials.clear()
        obj.data.materials.append(mat)


def setup_world(light_scale: float = 1.0, exposure: float = 0.0) -> None:
    scn = bpy.context.scene
    scn.render.engine = "BLENDER_EEVEE"
    scn.render.film_transparent = False
    scn.render.resolution_x = 960
    scn.render.resolution_y = 960
    scn.view_settings.view_transform = "Standard"
    scn.view_settings.exposure = exposure
    world = bpy.data.worlds.new("Banca")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.22, 0.23, 0.25, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.85 * light_scale
    scn.world = world
    for name, loc, energy, size in (
        ("Key", (0.45, 0.75, 0.55), 90.0, 0.5),
        ("Fill", (-0.65, 0.35, 0.35), 32.0, 0.7),
        ("Rim", (0.05, 0.45, -0.75), 45.0, 0.5),
    ):
        light = bpy.data.lights.new(name, "AREA")
        light.energy = energy * light_scale
        light.size = size
        node = bpy.data.objects.new(name, light)
        node.location = loc
        node.rotation_euler = _look_at(Vector(loc), Vector((0.0, -0.05, -0.35)))
        scn.collection.objects.link(node)


def _look_at(origin: Vector, target: Vector) -> Euler:
    direction = (target - origin)
    return direction.to_track_quat("-Z", "Y").to_euler()


def make_camera(name: str, loc: Vector, target: Vector, fov_y_deg: float, res: tuple) -> bpy.types.Object:
    cam = bpy.data.cameras.new(name)
    cam.sensor_fit = "VERTICAL"
    cam.sensor_height = 24.0
    cam.angle_y = math.radians(fov_y_deg)
    cam.clip_start = 0.005
    cam.clip_end = 100.0
    node = bpy.data.objects.new(name, cam)
    node.location = loc
    node.rotation_euler = _look_at(loc, target)
    bpy.context.scene.collection.objects.link(node)
    return node


def apply_action(name: str, at_second: float) -> None:
    """Aplica una accion del donante al brazo. Es la via barata: el donante ya
    trae la mano con forma de pistola y solo hay que corregirla contra NUESTRA
    Glock. Si la accion no existe, se grita en vez de renderizar una T-pose."""
    found = None
    for action in bpy.data.actions:
        if action.name == name or action.name.startswith(name):
            found = action
            break
    if found is None:
        print("BANCA FALLO: el donante no tiene la accion", name,
              "| tiene:", [a.name for a in bpy.data.actions])
        return
    scene = bpy.context.scene
    for obj in bpy.data.objects:
        if obj.type != "ARMATURE":
            continue
        if obj.animation_data is None:
            obj.animation_data_create()
        obj.animation_data.action = found
    scene.frame_start = int(found.frame_range[0])
    scene.frame_end = int(found.frame_range[1])
    fps = scene.render.fps / max(scene.render.fps_base, 0.001)
    if at_second >= 0.0:
        scene.frame_set(int(round(found.frame_range[0] + at_second * fps)))
    else:
        scene.frame_set(int(found.frame_range[0]))
    bpy.context.view_layer.update()
    print("BANCA accion %s frames=%s frame_actual=%d fps=%.1f" % (
        found.name, tuple(round(v, 1) for v in found.frame_range), scene.frame_current, fps))


def orbit(target: Vector, azimuth_deg: float, elevation_deg: float, dist: float) -> Vector:
    a = math.radians(azimuth_deg)
    e = math.radians(elevation_deg)
    return target + Vector((
        math.sin(a) * math.cos(e) * dist,
        math.sin(e) * dist,
        math.cos(a) * math.cos(e) * dist,
    ))


def main() -> None:
    args = parse_args()
    out = REPO / args.out
    out.mkdir(parents=True, exist_ok=True)
    frame = json.loads(Path(args.frame).read_text())
    reset()
    setup_world(args.light, args.exposure)

    FIX = (Matrix.Rotation(math.radians(-90.0), 4, "X") if args.gunspace
           else Matrix.Identity(4))
    gun_roots = []
    gun_holder = bpy.data.objects.new("Weapon", None)
    bpy.context.scene.collection.objects.link(gun_holder)
    if args.gun:
        gun_roots = import_any(GUN)
        for root in gun_roots:
            root.parent = gun_holder

    # BodyGive es el padre de los brazos y NO recibe el retroceso: si el brazo
    # se colgara del arma, en el pico de retroceso la banca ensenaria una mano
    # que sigue al arma, que es justo lo que la jerarquia del juego prohibe.
    body_give = bpy.data.objects.new("BodyGive", None)
    bpy.context.scene.collection.objects.link(body_give)

    arms_holder = None
    if args.arms and not args.hide_arms:
        arms_roots = import_any(Path(args.arms).expanduser().resolve())
        arms_holder = bpy.data.objects.new("ArmsRig", None)
        bpy.context.scene.collection.objects.link(arms_holder)
        pos = Vector([float(v) for v in args.pos.split(",")])
        rot = Euler([math.radians(float(v)) for v in args.rot_deg.split(",")], "XYZ")
        # Espacio del ARMA: el brazo se autora en el mismo sistema que el GLB de
        # la Glock (+Y arriba, -Z al morro). En el juego esto es una linea:
        # `ArmsRig.global_transform = Weapon.global_transform` al montar.
        arms_holder.matrix_basis = (
            Matrix.Translation(pos) @ rot.to_matrix().to_4x4() @ Matrix.Scale(args.scale, 4))
        ## `body_give` ya lleva FIX en modo gunspace; el brazo no lo repite.
        arms_holder.parent = body_give
        arms_holder.matrix_parent_inverse = Matrix.Identity(4)
        for root in arms_roots:
            root.parent = arms_holder
        print("BANCA candidato %s  objetos raiz=%d" % (args.arms, len(arms_roots)))
        if args.subdiv > 0:
            subdivide([o for o in bpy.data.objects if o.type == "MESH"], args.subdiv)
        if args.action:
            apply_action(args.action, args.action_frame)

    if args.mask:
        ## Modo MEDIDA: arma roja, brazos verdes, mundo negro y sin luces.  Con
        ## emision plana el pixel dice exactamente que superficie gano el
        ## z-buffer, que es lo unico que permite medir "el brazo tapa el arma".
        apply_clay(gun_roots, flat_material("Mask_Arma", (1.0, 0.0, 0.0)))
        if arms_holder is not None:
            apply_clay([o for o in bpy.data.objects if o.type == "MESH"
                        and any(m.type == "ARMATURE" for m in o.modifiers)],
                       flat_material("Mask_Brazos", (0.0, 1.0, 0.0)))
        for o in [o for o in bpy.data.objects if o.type == "LIGHT"]:
            bpy.data.objects.remove(o, do_unlink=True)
        bg = bpy.context.scene.world.node_tree.nodes["Background"]
        bg.inputs[1].default_value = 0.0
    elif args.clay:
        skin = clayskin()
        apply_clay(gun_roots, neutral_material())
        if arms_holder is not None:
            apply_clay([o for o in bpy.data.objects if o.type == "MESH"], skin)

    if args.arms_only:
        render_arms_only(out, args)
        print("BANCA listo ->", out)
        return

    states = [s for s in args.states.split(",") if s]
    for state in states:
        if state not in frame["states"]:
            print("BANCA aviso: el probe no tiene el estado", state)
            continue
        entry = frame["states"][state]
        gun_holder.matrix_world = xform_from_json(entry["Weapon"]) @ FIX
        body_give.matrix_world = xform_from_json(entry["PoseRoot/BodyGive"]) @ FIX
        bpy.context.view_layer.update()

        ## El blanco de las orbitas del puño es el NODO `Grip` del arma
        ## importada, no una reconstruccion a mano desde el JSON: la version
        ## anterior aplicaba FIX dos veces y las camaras de puño acababan
        ## mirando a la corredera en vez de a la empuñadura (se veia el arma
        ## entera y la mano por el borde).  El nodo es exacto por construccion.
        bpy.context.view_layer.update()
        grip_node = None
        for obj in bpy.data.objects:
            if obj.name.split(".")[0].lower() in ("grip", "gripnode"):
                grip_node = obj
                break
        if grip_node is not None:
            grip_pos = grip_node.matrix_world.translation.copy()
        else:
            grip_pos = Vector((0, 0, 0))
            if "grip" in entry:
                grip_local = (xform_from_json(entry["Weapon"]).inverted()
                              @ xform_from_json(entry["grip"]).translation)
                grip_pos = gun_holder.matrix_world @ (FIX @ grip_local)
            print("BANCA aviso: el arma no trae nodo Grip; blanco reconstruido")
        fov = 60.0 if state == "ads" else 82.0
        cams = {
            "eye": make_camera("eye", Vector((0, 0, 0)), Vector((0, 0, -1)), fov, (960, 540)),
            "3q": make_camera("3q", orbit(grip_pos, -42.0, 24.0, 0.38), grip_pos, 42.0, (960, 960)),
            "side": make_camera("side", orbit(grip_pos, -90.0, 6.0, 0.42), grip_pos, 42.0, (960, 960)),
            "top": make_camera("top", orbit(grip_pos, -20.0, 72.0, 0.40), grip_pos, 42.0, (960, 960)),
            ## `hand`: primer plano del puño (es el juez del agarre).  `back`:
            ## desde atras, que es donde se ve si la palma apoya en la espalda.
            "hand": make_camera("hand", orbit(grip_pos, -35.0, 18.0, 0.26), grip_pos, 40.0, (960, 960)),
            "back": make_camera("back", orbit(grip_pos, 150.0, 16.0, 0.36), grip_pos, 42.0, (960, 960)),
        }
        for view in [v for v in args.views.split(",") if v]:
            cam = cams.get(view)
            if cam is None:
                continue
            bpy.context.scene.camera = cam
            if view == "eye":
                bpy.context.scene.render.resolution_x = 960
                bpy.context.scene.render.resolution_y = 540
            else:
                bpy.context.scene.render.resolution_x = 960
                bpy.context.scene.render.resolution_y = 960
            path = out / ("%s_%s.png" % (state, view))
            bpy.context.scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            print("BANCA render", path.name)
        for cam in cams.values():
            bpy.data.objects.remove(cam, do_unlink=True)
    print("BANCA listo ->", out)


def arms_bbox() -> tuple:
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    deps = bpy.context.evaluated_depsgraph_get()
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        ev = obj.evaluated_get(deps)
        for corner in ev.bound_box:
            world = obj.matrix_world @ Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], world[i])
                hi[i] = max(hi[i], world[i])
    return lo, hi


def bone_world(name: str):
    """Posicion del hueso EN LA POSE ACTUAL. `bone.head_local` es la posicion de
    REPOSO: apuntar con ella deja la camara mirando donde la mano ya no esta."""
    for obj in bpy.data.objects:
        if obj.type != "ARMATURE":
            continue
        pbone = obj.pose.bones.get(name)
        if pbone is not None:
            return obj.matrix_world @ pbone.head
    return None


## Encuadre del brazo ENTERO (sin arma): es el que dice si la mano parece humana
## antes de discutir el agarre. El encuadre del juego es demasiado pequeno para
## juzgar dedos, asi que aqui se mira de cerca y luego se vuelve al ojo.
##
## La camara de mano apunta al HUESO de la mano, no al centro de la caja del
## brazo: el centro de dos brazos abiertos es el hueco entre ellos, y ahi no hay
## nada que mirar (la primera version de esto renderizo cuatro PNG vacios).
def render_arms_only(out: Path, args) -> None:
    actions = [a for a in args.states.split(",") if a]
    if not actions:
        actions = ["<rest>"]
    for name in actions:
        if name != "<rest>":
            apply_action(name, args.action_frame)
        bpy.context.view_layer.update()
        lo, hi = arms_bbox()
        center = (lo + hi) * 0.5
        radius = max((hi - lo).length * 0.5, 0.05)
        hand = bone_world("palm.02.R") or bone_world("hand.R") or center
        if hand == center:
            print("BANCA aviso: no hay hueso de mano; el encuadre de mano no vale")
        cams = {
            "34": make_camera("34", orbit(center, 40.0, 22.0, radius * 2.1), center, 40.0, (960, 960)),
            "front": make_camera("front", orbit(center, 180.0, 6.0, radius * 2.1), center, 40.0, (960, 960)),
            "side": make_camera("side", orbit(center, 90.0, 4.0, radius * 2.1), center, 40.0, (960, 960)),
            "hand": make_camera("hand", orbit(hand, 40.0, 20.0, 0.30), hand, 40.0, (960, 960)),
            "hand2": make_camera("hand2", orbit(hand, -55.0, 22.0, 0.30), hand, 40.0, (960, 960)),
            "hand3": make_camera("hand3", orbit(hand, 150.0, 30.0, 0.30), hand, 40.0, (960, 960)),
        }
        for view in [v for v in args.views.split(",") if v]:
            cam = cams.get(view)
            if cam is None:
                continue
            bpy.context.scene.camera = cam
            bpy.context.scene.render.resolution_x = 960
            bpy.context.scene.render.resolution_y = 960
            path = out / ("%s_%s.png" % (name.replace("|", "_"), view))
            bpy.context.scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            print("BANCA render", path.name)
        for cam in cams.values():
            bpy.data.objects.remove(cam, do_unlink=True)


if __name__ == "__main__":
    main()
