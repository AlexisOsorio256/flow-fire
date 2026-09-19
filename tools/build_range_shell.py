"""Construye la ARQUITECTURA del rango interior de FlowFire en Blender.

Uso (desde la raiz del repo):

    blender --background --python tools/build_range_shell.py

POR QUE EXISTE
--------------
El shell es GEOMETRIA. Las texturas PBR ya viven en ``assets/textures/real/``
con su propia fuente unica, asi que el GLB NO las embebe: exporta la relacion
textura->canal y el runtime (``scripts/RangeMeshes.gd``) las vuelve a enganchar
desde esos mismos ficheros. Antes el .glb pesaba 9,8 MB porque llevaba dentro
12 imagenes, la mitad de ellas copias byte a byte de las del repo.

ESCALA FISICA / TEXEL DENSITY
-----------------------------
Cada material declara cuantos METROS de mundo cubre una vuelta de su textura
(``METROS_POR_TILE``) y el script hornea las UV con proyeccion cubica a esa
densidad. Nada de "pared de 72 m con la textura repetida tres veces": la pared
repite una vez cada 2,4 m de hormigon, que es como se lee un muro de verdad.

GEOMETRIA
---------
Cajas biseladas + perfiles + railes. Los biseles y los junquillos no son
decoracion: son lo que produce una linea de luz en la arista, y sin esa linea
una caja de 24 x 72 m se lee como un poligono plano de 2004.
"""

from __future__ import annotations

from pathlib import Path

import bpy
import bmesh
from mathutils import Vector


REPO = Path(__file__).resolve().parents[1]
MODELS = REPO / "assets" / "models"
TEXTURES = REPO / "assets" / "textures" / "real"

# Cuantos metros de mundo cubre UNA vuelta completa de textura. Las cuatro
# texturas del repo son fotos de 1024 px de un material real; estos numeros son
# la escala a la que se ven creibles, no un ajuste para que "llene".
METROS_POR_TILE = {
    "piso": 3.0,      # hormigon pulido con juntas de losa
    "muro": 2.4,      # hormigon visto encofrado
    "metal": 1.6,     # chapa de acero pintada
    "madera": 1.2,    # tablon de roble
}


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.images,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def image(path: Path, non_color: bool = False):
    img = bpy.data.images.load(str(path), check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def material(
    name: str,
    albedo: Path | None,
    roughness: Path | None,
    normal: Path | None,
    color=(0.8, 0.8, 0.8, 1.0),
    metallic: float = 0.0,
    roughness_value: float = 0.8,
    emission=None,
    emission_strength: float = 2.5,
):
    """Material Principled con las tres mapas del repo.

    El tiling va en un nodo Mapping con la escala 1/metros_por_tile. El
    exportador glTF lo hornea en KHR_texture_transform y ademas genera UVs
    propias, asi que la densidad se mantiene aunque el runtime no toque nada.
    """
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness_value
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])

    scale = next((v for k, v in METROS_POR_TILE.items() if k in name.lower()), 1.0)

    def tiled(path: Path, non_color: bool):
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image(path, non_color)
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (1.0 / scale, 1.0 / scale, 1.0 / scale)
        coords = nodes.new("ShaderNodeTexCoord")
        links.new(coords.outputs["UV"], mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
        return tex

    if albedo is not None:
        links.new(tiled(albedo, False).outputs["Color"], shader.inputs["Base Color"])
    if roughness is not None:
        links.new(tiled(roughness, True).outputs["Color"], shader.inputs["Roughness"])
    if normal is not None:
        normal_node = nodes.new("ShaderNodeNormalMap")
        normal_node.inputs["Strength"].default_value = 0.7
        links.new(tiled(normal, True).outputs["Color"], normal_node.inputs["Color"])
        links.new(normal_node.outputs["Normal"], shader.inputs["Normal"])
    if emission is not None:
        shader.inputs["Emission Color"].default_value = (*emission, 1.0)
        shader.inputs["Emission Strength"].default_value = emission_strength
    mat["metros_por_tile"] = scale
    return mat


def cube_project(obj, scale: float) -> None:
    """UV por proyeccion cubica a densidad fisica, en ESPACIO DE MUNDO.

    Se proyecta DESPUES de unir el grupo entero, con las coordenadas de mundo:
    asi dos caras contiguas de la misma pared comparten el mismo sistema de UV
    y el material no aparece cortado por una costura que no existe en la obra.
    Proyectar caja a caja en espacio local (lo que hacia antes) ponia una
    costura distinta en cada cara y el hormigon se leia a parches.
    """
    matrix = obj.matrix_world
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv = bm.loops.layers.uv.verify()
    for face in bm.faces:
        world_normal = (matrix.to_3x3() @ face.normal)
        axis = max(range(3), key=lambda i: abs(world_normal[i]))
        for loop in face.loops:
            co = matrix @ loop.vert.co
            if axis == 0:
                u, v = co.y, co.z
            elif axis == 1:
                u, v = co.x, co.z
            else:
                u, v = co.x, co.y
            loop[uv].uv = (u / scale, v / scale)
    bm.to_mesh(mesh)
    bm.free()


def add_box(
    name: str,
    location,
    size,
    mat,
    bevel: float = 0.012,
    rotation=(0.0, 0.0, 0.0),
):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel > 0.0:
        mod = obj.modifiers.new("Real bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1 if bevel <= 0.009 else 2
        mod.limit_method = "ANGLE"
        mod.harden_normals = False
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def add_cylinder(name: str, location, radius: float, depth: float, mat, vertices=16, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(
        location=location, radius=radius, depth=depth, vertices=vertices, rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def join(name: str, objects, root, meters_per_tile: float):
    """Une el grupo, aplica el transform y proyecta UV a densidad fisica.

    El transform se APLICA antes de proyectar para que ``matrix_world`` sea la
    identidad y las UV queden en metros de mundo reales (una vuelta de textura
    cada ``meters_per_tile`` metros), que es lo que pide la constitucion: la
    textura tiene que leerse como material, no como foto estirada.
    """
    if not objects:
        raise RuntimeError(f"sin geometria para {name}")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    joined.parent = root
    joined.matrix_parent_inverse = root.matrix_world.inverted()
    bpy.context.view_layer.objects.active = joined
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # NO se llama a normals_make_consistent: los cubos primitivos ya traen las
    # caras hacia fuera, y esa operacion las REINVERTIA. El resultado medido fue
    # dot(geometrica, vertice) = -1.00 en todas las caras, o sea bobinado
    # invertido: Godot culeaba el piso y dibujaba su cara interior (el borron
    # radial lavado que se veia en pantalla).
    cube_project(joined, meters_per_tile)
    joined["metros_por_tile"] = meters_per_tile
    return joined


# ---------------------------------------------------------------------------
# Dimensiones del rango (en metros, espacio Godot; el eje largo es Y de Blender)
# ---------------------------------------------------------------------------
HALF_W = 12.0        # ancho total 24 m
Z0 = 6.0             # pared de atras (detras del tirador)
Z1 = -66.0           # pared del fondo
LENGTH = Z0 - Z1     # 72 m
HEIGHT = 4.2
BAY = 3.6            # modulo de losa / vano estructural
CENTER_Y = (Z0 + Z1) * 0.5  # Blender +Y = Godot -Z


def gz(godot_z: float) -> float:
    """Godot -Z -> Blender +Y."""
    return -godot_z


def build() -> None:
    reset_scene()
    root = bpy.data.objects.new("RangeShell", None)
    bpy.context.collection.objects.link(root)

    # Piso: hormigon de losa normal. NO el "brushed": ese es un hormigon
    # cepillado con estrías largas y anisotropicas que, repetido en una losa de
    # 24 x 72 m, se lee como moqueta sucia en diagonal en vez de como solera.
    # Solera: hormigon FRATASADO (grano isótropo). El `concrete_concrete` es un
    # hormigon de encofrado con franjas de tabla: sobre una losa de 72 m se
    # repiten en rayas y la solera parece un tablado.
    concrete_floor = material(
        "Range_Concrete_Floor",
        TEXTURES / "concrete_brushed_concrete_diff.jpg",
        TEXTURES / "concrete_brushed_concrete_rough.jpg",
        TEXTURES / "concrete_brushed_concrete_nor_gl.jpg",
        color=(0.74, 0.73, 0.72, 1.0),
        roughness_value=0.93,
    )
    concrete_wall = material(
        "Range_Concrete_Wall",
        TEXTURES / "concrete_concrete_diff.jpg",
        TEXTURES / "concrete_concrete_rough.jpg",
        TEXTURES / "concrete_concrete_nor_gl.jpg",
        color=(0.70, 0.70, 0.72, 1.0),
        roughness_value=0.90,
    )
    concrete_brushed = material(
        "Range_Concrete_Brushed",
        TEXTURES / "concrete_brushed_concrete_diff.jpg",
        TEXTURES / "concrete_brushed_concrete_rough.jpg",
        TEXTURES / "concrete_brushed_concrete_nor_gl.jpg",
        color=(0.78, 0.77, 0.75, 1.0),
        roughness_value=0.86,
    )
    steel = material(
        "Range_Painted_Metal",
        TEXTURES / "metal_metal_plate_diff.jpg",
        TEXTURES / "metal_metal_plate_rough.jpg",
        TEXTURES / "metal_metal_plate_nor_gl.jpg",
        color=(0.30, 0.32, 0.35, 1.0),
        metallic=0.65,
        roughness_value=0.48,
    )
    oak = material(
        "Range_Oak_Trim",
        TEXTURES / "wood_oak_wood_planks_diff.jpg",
        TEXTURES / "wood_oak_wood_planks_rough.jpg",
        TEXTURES / "wood_oak_wood_planks_nor_gl.jpg",
        color=(0.62, 0.50, 0.37, 1.0),
        roughness_value=0.84,
    )
    luminaire = material(
        "Range_Luminaire", None, None, None,
        color=(0.92, 0.90, 0.84, 1.0), roughness_value=0.28,
        emission=(1.0, 0.93, 0.76), emission_strength=1.5,
    )
    marking = material(
        "Range_Markings", None, None, None,
        color=(0.62, 0.55, 0.38, 1.0), roughness_value=0.88,
    )

    floor: list = []
    floor_brushed: list = []
    wall: list = []
    metal: list = []
    wood: list = []
    light: list = []
    marks: list = []

    # ----------------------------------------------------------------- piso
    # Losa de hormigon en paños de BAY con junta fresada: la junta es una
    # ranura de 12 mm que atrapa sombra y da la escala del suelo de un vistazo.
    for index, gy in enumerate(frange(Z1 + BAY * 0.5, Z0, BAY)):
        floor.append(add_box(
            "Slab", (0.0, gz(gy), -0.15),
            (HALF_W * 2 - 0.10, BAY - 0.024, 0.30), concrete_floor, 0.010,
        ))
    floor.append(add_box("Slab edge", (0.0, CENTER_Y, -0.15), (HALF_W * 2, 0.10, 0.30), concrete_floor, 0.008))
    # Solera endurecida de la linea de fuego: aqui si es un hormigon cepillado
    # de verdad (se pule para que el tirador no resbale).
    floor_brushed.append(add_box(
        "Firing line slab", (0.0, gz(-1.4), 0.012),
        (HALF_W * 2 - 0.20, 4.2, 0.03), concrete_brushed, 0.006,
    ))

    # ---------------------------------------------------------------- muros
    # Muro de hormigon visto en paños verticales de BAY. Cada paño va separado
    # 24 mm del siguiente: en esa sombra se lee el encofrado y el muro deja de
    # ser una sabana.
    panels = int(LENGTH / BAY)
    for index in range(panels):
        y = Z1 + BAY * (index + 0.5)
        for sign, x in ((-1.0, -HALF_W + 0.15), (1.0, HALF_W - 0.15)):
            wall.append(add_box(
                "Wall panel", (x, y, HEIGHT * 0.5),
                (0.30, BAY - 0.024, HEIGHT), concrete_wall, 0.012,
            ))
    wall.append(add_box("Back wall", (0.0, Z0 - 0.15, HEIGHT * 0.5), (HALF_W * 2, 0.30, HEIGHT), concrete_wall, 0.012))
    # Techo: forjado con casetones. El nervio visto cada BAY da la retícula.
    wall.append(add_box("Ceiling slab", (0.0, CENTER_Y, HEIGHT + 0.10), (HALF_W * 2, LENGTH, 0.20), concrete_wall, 0.008))
    for index in range(panels + 1):
        y = Z1 + BAY * index
        wall.append(add_box("Ceiling rib", (0.0, y, HEIGHT - 0.09), (HALF_W * 2 - 0.10, 0.16, 0.18), concrete_wall, 0.008))
    for x in (-HALF_W + 0.20, HALF_W - 0.20):
        wall.append(add_box("Ceiling spine", (x, CENTER_Y, HEIGHT - 0.09), (0.14, LENGTH, 0.18), concrete_wall, 0.008))

    # --------------------------------------------------------- zocalo y canal
    for sign_x in (-1.0, 1.0):
        base_x = sign_x * (HALF_W - 0.30)
        metal.append(add_box(
            "Baseboard", (sign_x * (HALF_W - 0.36), CENTER_Y, 0.11),
            (0.12, LENGTH, 0.22), steel, 0.010,
        ))
        metal.append(add_box(
            "Cable tray", (base_x - sign_x * 0.06, CENTER_Y, 3.42),
            (0.22, LENGTH, 0.10), steel, 0.008,
        ))
        # Soportes de la bandeja: dan ritmo vertical a un muro larguisimo.
        for index in range(0, panels, 2):
            metal.append(add_box(
                "Tray bracket", (base_x - sign_x * 0.06, Z1 + BAY * index, 3.30),
                (0.26, 0.08, 0.26), steel, 0.006,
            ))

    # --------------------------------------------------------------- vigas
    for index in range(panels + 1):
        y = Z1 + BAY * index
        # Dos tramos laterales, no una viga de lado a lado: cruzando el pasillo
        # la viga se come el encuadre del tirador.
        for side in (-1.0, 1.0):
            metal.append(add_box("Roof beam", (side * (HALF_W * 0.5 + 0.15), y, HEIGHT - 0.42),
                (HALF_W - 0.80, 0.20, 0.34), steel, 0.014))
        for x in (-HALF_W + 0.60, HALF_W - 0.60):
            metal.append(add_box("Beam post", (x, y, HEIGHT * 0.5 - 0.05), (0.22, 0.22, HEIGHT - 0.60), steel, 0.012))

    # ---------------------------------------------------------- luminarias
    # Bandeja + difusor. El difusor es la unica superficie emisiva: las luces
    # reales viven en la escena de Godot, que es quien decide cuantas y con
    # sombra.
    for index in range(panels):
        y = Z1 + BAY * (index + 0.5)
        for x in (-5.4, 5.4):
            metal.append(add_box("Luminaire housing", (x, y, HEIGHT - 0.17), (1.90, 0.30, 0.10), steel, 0.010))
            light.append(add_box("Luminaire diffuser", (x, y, HEIGHT - 0.225), (1.74, 0.24, 0.035), luminaire, 0.008))
            metal.append(add_box("Luminaire endcap", (x - 0.98, y, HEIGHT - 0.17), (0.06, 0.32, 0.12), steel, 0.006))
            metal.append(add_box("Luminaire endcap", (x + 0.98, y, HEIGHT - 0.17), (0.06, 0.32, 0.12), steel, 0.006))
            for dx in (-0.7, 0.0, 0.7):
                metal.append(add_box("Hanger", (x + dx, y, HEIGHT - 0.05), (0.035, 0.035, 0.28), steel, 0.004))

    # --------------------------------------------- separadores de calle: FUERA
    # Aqui vivian los montantes, los pies y los tres railes por calle (cinco
    # calles) de acero pintado. Eran el elemento que convertia "una nave" en
    # "un campo de tiro"... y tambien lo que el dueño del repo no quiere:
    # "no quiero que esten los fierros, debe estar sin eso [para] moverme por
    # donde yo quiero en todo el mapa". El rango es un instrumento: se camina
    # por el entero y se dispara a lo que hay. No se repone nada en su lugar.

    # ------------------------------------------------------ puesto de tiro
    # La linea de fuego: encimera de roble sobre bancada de acero, mampara
    # lateral y balda de cargadores. Es la superficie que el jugador MIRA al
    # recargar, asi que es la que mas detalle necesita.
    bench_z = -1.4
    metal.append(add_box("Booth deck", (1.80, gz(bench_z), 0.70), (1.30, 1.10, 0.06), steel, 0.008))
    wood.append(add_box("Booth top", (1.80, gz(bench_z), 0.755), (1.34, 1.14, 0.05), oak, 0.010))
    metal.append(add_box("Booth shelf", (1.80, gz(bench_z - 0.52), 0.30), (1.30, 0.05, 0.04), steel, 0.006))
    for dx in (-0.62, 0.62):
        for dy in (-0.50, 0.50):
            metal.append(add_cylinder("Booth leg", (1.80 + dx, gz(bench_z) + dy, 0.36), 0.026, 0.72, steel, 12))
    # Las pantallas laterales del puesto tambien se van: son los dos paneles
    # negros grandes que flanqueaban el carril y tapaban media linea de tiro.
    # Queda la mesa, que es lo unico que el jugador usa (los cargadores).

    # ----------------------------------------------------------- blanco/trap
    # Trampa de balas: rampa de acero inclinada, labio y alas laterales de
    # madera. Es una silueta reconocible, no una caja al fondo.
    trap_y = gz(-63.0)
    for index in range(7):
        steel_y = trap_y + 0.16 + index * 0.30
        metal.append(add_box(
            "Trap ramp", (0.0, steel_y, 2.30 - index * 0.30),
            (HALF_W * 2 - 1.0, 0.28, 0.10), steel, 0.010, rotation=(0.72, 0.0, 0.0),
        ))
    metal.append(add_box("Trap lip", (0.0, trap_y + 2.10, 0.55), (HALF_W * 2 - 1.0, 0.34, 1.10), steel, 0.014))
    metal.append(add_box("Trap base", (0.0, trap_y + 1.0, 0.10), (HALF_W * 2 - 1.0, 2.40, 0.20), steel, 0.008))
    for sign_x in (-1.0, 1.0):
        wood.append(add_box("Trap wing", (sign_x * (HALF_W - 0.75), trap_y + 1.10, 1.25), (0.34, 2.30, 2.50), oak, 0.014))
        metal.append(add_box("Trap post", (sign_x * (HALF_W - 0.75), trap_y - 0.10, 1.25), (0.16, 0.16, 2.50), steel, 0.008))
    metal.append(add_box("Trap header", (0.0, trap_y - 0.10, 3.05), (HALF_W * 2 - 1.5, 0.22, 0.22), steel, 0.010))

    # ------------------------------------------------------- marcas de suelo
    for godot_z in (0.0, -5.0, -10.0, -15.0, -25.0, -35.0, -50.0):
        marks.append(add_box("Distance marking", (0.0, gz(godot_z), 0.008), (9.0, 0.10, 0.014), marking, 0.003))
    for lane_x in (-8.0, -4.0, 4.0, 8.0):
        marks.append(add_box("Lane marking", (lane_x + 2.0, gz(-25.0), 0.008), (0.09, 50.0, 0.014), marking, 0.003))

    join("RangeShell_concrete_floor", floor, root, METROS_POR_TILE["piso"])
    join("RangeShell_concrete_brushed", floor_brushed, root, METROS_POR_TILE["piso"])
    join("RangeShell_concrete_wall", wall, root, METROS_POR_TILE["muro"])
    join("RangeShell_painted_metal", metal, root, METROS_POR_TILE["metal"])
    join("RangeShell_oak_trim", wood, root, METROS_POR_TILE["madera"])
    join("RangeShell_luminaire", light, root, METROS_POR_TILE["metal"])
    join("RangeShell_markings", marks, root, METROS_POR_TILE["piso"])

    root["asset_role"] = "static range presentation"
    root["textures"] = "external: assets/textures/real"
    export(root)


def frange(start: float, stop: float, step: float):
    value = start
    while value < stop:
        yield value
        value += step


def export(root) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    MODELS.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(MODELS / "range_shell.glb"),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
        # SIN texturas dentro del GLB: la fuente unica es assets/textures/real.
        export_image_format="NONE",
    )
    path = MODELS / "range_shell.glb"
    tris = sum(
        len(poly.vertices) - 2
        for obj in bpy.data.objects
        if obj.type == "MESH"
        for poly in obj.data.polygons
    )
    print(f"RANGE_SHELL built {path} {path.stat().st_size / 1024:.0f} KB tris={tris}")


if __name__ == "__main__":
    build()
