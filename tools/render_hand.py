"""Renderiza right_hand.glb en Blender para VERIFICAR el asset sin abrir el juego.

Tres vistas ortograficas (lateral, frontal, planta) sobre fondo claro. Sirve
para comprobar de un vistazo si la mano esta entera, en que escala esta y hacia
donde apunta. Es mas rapido y mas honesto que deducirlo de AABBs.

    blender --background --python tools/render_hand.py
"""
from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector

REPO = Path(__file__).resolve().parents[1]
GLB = REPO / "assets" / "models" / "right_hand.glb"
OUT = REPO / "captures" / "asset"


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(GLB))

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in meshes:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], world[i])
                hi[i] = max(hi[i], world[i])
    size = hi - lo
    center = (hi + lo) * 0.5
    print("RENDER aabb lo=(%.3f, %.3f, %.3f) size=(%.3f, %.3f, %.3f)"
          % (lo.x, lo.y, lo.z, size.x, size.y, size.z))
    print("RENDER objetos=%d tris=%d" % (
        len(meshes),
        sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)))

    # Fondo claro para que una mano oscura se lea.
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.5, 0.52, 1.0)
    bpy.context.scene.world = world

    span = max(size) * 1.15
    distance = span * 2.2
    views = {
        "lateral": (0.0, -1.0, 0.0),   # mirando desde -Y (el morro)
        "frontal": (-1.0, 0.0, 0.0),   # desde -X
        "planta": (0.0, 0.0, 1.0),     # desde arriba
        "oblicua": (-0.7, -0.7, 0.4),
    }
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "SINGLE"
    scene.display.shading.single_color = (0.35, 0.33, 0.30)
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.film_transparent = False
    OUT.mkdir(parents=True, exist_ok=True)

    for name, direction in views.items():
        vec = Vector(direction).normalized()
        cam_data = bpy.data.cameras.new("Cam_" + name)
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = span
        cam = bpy.data.objects.new("Cam_" + name, cam_data)
        scene.collection.objects.link(cam)
        cam.location = center + vec * distance
        # Apuntar la camara al centro.
        look = (center - cam.location).normalized()
        cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
        scene.camera = cam
        scene.render.filepath = str(OUT / ("hand_%s.png" % name))
        bpy.ops.render.render(write_still=True)
        print("RENDER %s" % (OUT / ("hand_%s.png" % name)))


if __name__ == "__main__":
    main()
