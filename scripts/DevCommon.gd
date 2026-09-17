class_name DevCommon
extends Node

## Utilidades de laboratorio que usan DOS o mas modulos (capturas, esperas,
## geometria en pantalla). No tiene autoridad de juego ni estado propio: si algo
## solo lo usa un modulo, vive en ese modulo.

var _player: CharacterBody3D
var _hud: CanvasLayer


func setup(main_node: Node3D, player_node: CharacterBody3D, hud_node: CanvasLayer, common_node) -> void:
    _player = player_node
    _hud = hud_node


## Fija el viewport al tamaño de diseño del proyecto (1920x1080). Sin esto,
## según cómo el WM decore/recorte la ventana, benchmarks sucesivos medirían
## 1920x1008 o 1920x1080 y no serían comparables.
func lock_viewport() -> void:
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
    var width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920))
    var height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
    DisplayServer.window_set_size(Vector2i(width, height))
    DisplayServer.window_set_position(Vector2i.ZERO)


func capture_view(path: String) -> void:
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    image.save_png(path)


func capture_image() -> Image:
    # En headless, con Engine.time_scale=0, frame_post_draw puede no emitirse
    # aunque el árbol sí procese frames; esperar esa señal deja geometrydebug
    # bloqueado después de imprimir la pose de hip. Dos frames de margen ya los
    # aporta el llamador, así que aquí basta con ceder un frame al viewport.
    await get_tree().process_frame
    var texture := get_viewport().get_texture()
    if texture == null:
        return null
    return texture.get_image()


## Espera a que la pose del arma se asiente (la transición hip<->ADS tarda ~0.5 s
## y medir a mitad da números falsos).
func settle_pose() -> void:
    for _i in range(200):
        await get_tree().process_frame
        var w = _player.weapon
        if absf(w.aim_blend - (1.0 if w.aim else 0.0)) < 0.01 and w.sprint_blend < 0.01:
            break


func bounds_of(verts: PackedVector3Array) -> AABB:
    if verts.is_empty():
        return AABB()
    var mn := verts[0]
    var mx := verts[0]
    for v in verts:
        mn = mn.min(v)
        mx = mx.max(v)
    return AABB(mn, mx - mn)


func transform_aabb(box: AABB, transform: Transform3D) -> AABB:
    var cmin := box.position
    var cmax := box.position + box.size
    var result := AABB()
    var first := true
    for xi in [0.0, 1.0]:
        for yi in [0.0, 1.0]:
            for zi in [0.0, 1.0]:
                var corner := Vector3(
                    lerpf(cmin.x, cmax.x, xi),
                    lerpf(cmin.y, cmax.y, yi),
                    lerpf(cmin.z, cmax.z, zi)
                )
                var p := transform * corner
                if first:
                    result = AABB(p, Vector3.ZERO)
                    first = false
                else:
                    result = result.expand(p)
    return result


func screen_bbox(verts_box: AABB, world_transform: Transform3D, camera_node: Camera3D) -> Dictionary:
    var cmin := verts_box.position
    var cmax := verts_box.position + verts_box.size
    var smin := Vector2(1e9, 1e9)
    var smax := Vector2(-1e9, -1e9)
    for xi in [0.0, 1.0]:
        for yi in [0.0, 1.0]:
            for zi in [0.0, 1.0]:
                var corner := Vector3(
                    lerpf(cmin.x, cmax.x, xi),
                    lerpf(cmin.y, cmax.y, yi),
                    lerpf(cmin.z, cmax.z, zi)
                )
                var sp := camera_node.unproject_position(world_transform * corner)
                smin.x = minf(smin.x, sp.x); smin.y = minf(smin.y, sp.y)
                smax.x = maxf(smax.x, sp.x); smax.y = maxf(smax.y, sp.y)
    return {"min": smin, "max": smax, "size": smax - smin}


## Mallas visibles del viewmodel: pistola (Object_938/939/940) + brazos.
func viewmodel_meshes(w) -> Array:
    return gun_family_meshes(w, ["Object_938", "Object_939", "Object_940", "Object_8", "Object_7"])


## Subconjunto de mallas del viewmodel por nombre de nodo.
func gun_family_meshes(w, names: Array) -> Array:
    var out: Array = []
    if w.viewmodel.arms_root == null:
        return out
    var stack: Array = [w.viewmodel.arms_root]
    while not stack.is_empty():
        var n = stack.pop_back()
        if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh != null and names.has(n.name):
            out.append(n)
        for c in n.get_children():
            stack.append(c)
    return out


## Deja el arma en un estado que sí admite recarga: con el cargador lleno
## start_reload() no hace nada y las capturas de "recarga" saldrían falsas.
func force_reloadable_state() -> void:
    _player.weapon.mag = 0
    _player.weapon.chamber = 0
    _player.weapon.reserve = 17
