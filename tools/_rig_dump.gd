extends SceneTree

## Volcado de medida del rig (temporal, se borra tras la inspección):
## superficies, UVs, huesos, pistas de animación y recorrido REAL de la
## geometría de la corredera y el cargador al mover sus huesos.
##
## Uso: godot4 --headless --path . --script res://tools/_rig_dump.gd

const MODEL_PATH := "res://assets/models/fps_rig.glb"


func _init() -> void:
    var packed := load(MODEL_PATH) as PackedScene
    if packed == null:
        print("DUMP no se pudo cargar el modelo")
        quit(1)
        return
    var root := packed.instantiate()
    get_root().add_child(root)

    var skeleton := root.find_child("Skeleton3D", true, false) as Skeleton3D
    var gun := root.find_child("Glock19", true, false) as MeshInstance3D
    var arms := root.find_child("ArmModel", true, false) as MeshInstance3D
    print("DUMP nudos=", _count_nodes(root), " huesos=", skeleton.get_bone_count() if skeleton else -1)
    if skeleton != null:
        var names: Array[String] = []
        for i in range(skeleton.get_bone_count()):
            names.append(skeleton.get_bone_name(i))
        print("DUMP huesos=", names)

    _dump_mesh("Glock19", gun)
    _dump_mesh("ArmModel", arms)
    _dump_animations(root)

    if gun != null and skeleton != null:
        _dump_surface_travel(gun, skeleton, root)
        var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
        if ap != null:
            _sample_reload(ap, skeleton, root, gun)

    quit(0)


func _count_nodes(node: Node) -> int:
    var total := 1
    for child in node.get_children():
        total += _count_nodes(child)
    return total


func _dump_mesh(label: String, mesh: MeshInstance3D) -> void:
    if mesh == null or mesh.mesh == null:
        print("DUMP malla ", label, " = null")
        return
    print("DUMP malla ", label, " superficies=", mesh.mesh.get_surface_count(),
        " skin=", mesh.skin != null, " material_override=", mesh.material_override)
    for i in range(mesh.mesh.get_surface_count()):
        var arrays := mesh.mesh.surface_get_arrays(i)
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var uv = arrays[Mesh.ARRAY_TEX_UV]
        var uv2 = arrays[Mesh.ARRAY_TEX_UV2]
        var normals = arrays[Mesh.ARRAY_NORMAL]
        var bones = arrays[Mesh.ARRAY_BONES]
        var weights = arrays[Mesh.ARRAY_WEIGHTS]
        var uv_text := "sin_uv"
        if uv != null and uv.size() > 0:
            var lo := Vector2(INF, INF)
            var hi := Vector2(-INF, -INF)
            for t in uv:
                lo.x = minf(lo.x, t.x); lo.y = minf(lo.y, t.y)
                hi.x = maxf(hi.x, t.x); hi.y = maxf(hi.y, t.y)
            uv_text = "uv[%s..%s] n=%d" % [lo, hi, uv.size()]
        var uv2_text := "sin_uv2" if (uv2 == null or uv2.size() == 0) else "uv2_n=%d" % uv2.size()
        var bone_text := "sin_huesos"
        if bones != null and bones.size() > 0 and weights != null:
            var used := {}
            for b in range(0, bones.size(), 4):
                for k in range(4):
                    if weights[b + k] > 0.001:
                        used[bones[b + k]] = true
            bone_text = "bones_bind=%s" % [used.keys()]
        print("DUMP   ", i, " nombre=", mesh.mesh.surface_get_name(i),
            " verts=", verts.size(), " normales=", (normals.size() if normals != null else -1),
            " ", uv_text, " ", uv2_text, " ", bone_text)
    if mesh.skin != null:
        var binds: Array[String] = []
        for i in range(mesh.skin.get_bind_count()):
            binds.append("%d:%s(bone=%d)" % [i, mesh.skin.get_bind_name(i), mesh.skin.get_bind_bone(i)])
        print("DUMP binds ", label, "=", binds)


func _dump_animations(root: Node) -> void:
    var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
    if ap == null:
        print("DUMP sin AnimationPlayer")
        return
    for anim_name in ap.get_animation_list():
        var anim := ap.get_animation(anim_name)
        var bones := {}
        for t in range(anim.get_track_count()):
            var path := str(anim.track_get_path(t))
            if path.contains(":"):
                var bone := path.split(":")[1]
                var keys := anim.track_get_key_count(t)
                var times: Array[String] = []
                for k in range(mini(keys, 6)):
                    times.append("%.2f" % anim.track_get_key_time(t, k))
                if not bones.has(bone):
                    bones[bone] = []
                bones[bone].append("%s(t=%s)" % [path.split(":")[0], ",".join(times)])
        print("DUMP anim ", anim_name, " largo=%.3f" % anim.length, " pistas=", anim.get_track_count())
        for t in range(anim.get_track_count()):
            var tpath := str(anim.track_get_path(t))
            var parts := tpath.split(":")
            if parts.size() < 2 or not (parts[1] in ["Slide", "Magazine", "Trigger", "Barrel"]):
                continue
            var keys_text: Array[String] = []
            for k in range(anim.track_get_key_count(t)):
                keys_text.append("t=%.3f v=%s" % [anim.track_get_key_time(t, k), str(anim.track_get_key_value(t, k))])
            print("DUMP CLAVES ", anim_name, " ", parts[0], ":", parts[1], " tipo=", anim.track_get_type(t), " ", keys_text)
        for bone in bones:
            print("DUMP    ", bone, " -> ", bones[bone])


## Recorrido REAL de la geometría (no del hueso): se deforma cada superficie a
## mano con la pose actual y se mide su caja envolvente en espacio de modelo.
func _dump_surface_travel(gun: MeshInstance3D, skeleton: Skeleton3D, root: Node) -> void:
    var chain := _local_chain(skeleton, root)
    var bind_in_model := Transform3D.IDENTITY
    for i in range(gun.skin.get_bind_count()):
        var bname := gun.skin.get_bind_name(i)
        var bone := skeleton.find_bone(bname)
        if bone < 0:
            continue
        bind_in_model = chain * skeleton.get_bone_global_rest(bone) * gun.skin.get_bind_pose(i)
        break

    var slide_bone := skeleton.find_bone("Slide")
    var mag_bone := skeleton.find_bone("Magazine")
    var rest_slide := skeleton.get_bone_rest(slide_bone) if slide_bone >= 0 else Transform3D.IDENTITY
    var rest_mag := skeleton.get_bone_rest(mag_bone) if mag_bone >= 0 else Transform3D.IDENTITY

    var rest_box := _skinned_box(gun, skeleton, chain, bind_in_model)
    print("DUMP caja_rest=", rest_box.position.snapped(Vector3(0.001, 0.001, 0.001)),
        " tam=", rest_box.size.snapped(Vector3(0.001, 0.001, 0.001)))

    for bone_name in ["Slide", "Magazine"]:
        var idx: int = skeleton.find_bone(bone_name)
        if idx < 0:
            print("DUMP sin hueso ", bone_name)
            continue
        var before := _surface_box(gun, skeleton, chain, bind_in_model, bone_name)
        print("DUMP ", bone_name, " caja_rest=", before.size.snapped(Vector3(0.0001, 0.0001, 0.0001)),
            " centro=", (before.position + before.size * 0.5).snapped(Vector3(0.0001, 0.0001, 0.0001)))
    # Desplazamiento del hueso de la corredera en 0.039 m de frame de arma.
    var back := (bind_in_model.basis * Vector3(0, 0, 1)).normalized()
    skeleton.set_bone_pose_position(slide_bone, rest_slide.origin + (skeleton.get_bone_global_rest(slide_bone).basis.inverse() * back))
    skeleton.force_update_all_bone_transforms()
    var moved := _surface_box(gun, skeleton, chain, bind_in_model, "Slide")
    print("DUMP Slide tras_1unidad_pose tam=", moved.size.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " delta_centro=", ((moved.position + moved.size * 0.5) - (rest_box.position + rest_box.size * 0.5)).snapped(Vector3(0.0001, 0.0001, 0.0001)))
    skeleton.set_bone_pose_position(slide_bone, rest_slide.origin)
    skeleton.set_bone_pose_position(mag_bone, rest_mag.origin + (skeleton.get_bone_global_rest(mag_bone).basis.inverse() * (bind_in_model.basis * Vector3(0, -1, 0)).normalized()))
    skeleton.force_update_all_bone_transforms()
    var mag_moved := _surface_box(gun, skeleton, chain, bind_in_model, "Magazine")
    print("DUMP Magazine tras_1unidad_pose delta_centro=", ((mag_moved.position + mag_moved.size * 0.5) - (rest_box.position + rest_box.size * 0.5)).snapped(Vector3(0.0001, 0.0001, 0.0001)))
    skeleton.set_bone_pose_position(mag_bone, rest_mag.origin)
    skeleton.force_update_all_bone_transforms()


func _skinned_box(gun: MeshInstance3D, skeleton: Skeleton3D, chain: Transform3D, bind_in_model: Transform3D) -> AABB:
    var box := AABB()
    var first := true
    for s in range(gun.mesh.get_surface_count()):
        var arrays := gun.mesh.surface_get_arrays(s)
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        for v in verts:
            var p := bind_in_model * v
            if first:
                box = AABB(p, Vector3.ZERO)
                first = false
            else:
                box = box.expand(p)
    return box


func _surface_box(gun: MeshInstance3D, skeleton: Skeleton3D, chain: Transform3D, bind_in_model: Transform3D, surface_name: String) -> AABB:
    var box := AABB()
    var first := true
    for s in range(gun.mesh.get_surface_count()):
        if gun.mesh.surface_get_name(s) != surface_name:
            continue
        var arrays := gun.mesh.surface_get_arrays(s)
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var bones = arrays[Mesh.ARRAY_BONES]
        var weights = arrays[Mesh.ARRAY_WEIGHTS]
        for vi in range(verts.size()):
            var p := Vector3.ZERO
            if bones != null and bones.size() > 0:
                var total := 0.0
                for k in range(4):
                    var w: float = weights[vi * 4 + k]
                    if w <= 0.0001:
                        continue
                    var bind_idx: int = bones[vi * 4 + k]
                    var bname := gun.skin.get_bind_name(bind_idx)
                    var bone := skeleton.find_bone(bname)
                    if bone < 0:
                        continue
                    p += w * ((chain * skeleton.get_bone_global_pose(bone) * gun.skin.get_bind_pose(bind_idx)) * verts[vi])
                    total += w
                if total > 0.0001:
                    p /= total
                else:
                    p = bind_in_model * verts[vi]
            else:
                p = bind_in_model * verts[vi]
            if first:
                box = AABB(p, Vector3.ZERO)
                first = false
            else:
                box = box.expand(p)
    return box


func _local_chain(node: Node, ancestor: Node) -> Transform3D:
    var result := Transform3D.IDENTITY
    var current := node
    while current != null and current != ancestor:
        if current is Node3D:
            result = (current as Node3D).transform * result
        current = current.get_parent()
    return result


## Muestrea la animación de recarga del autor y mide, en unidades de modelo (el
## arma mide 5.09 de largo en esas unidades), dónde está el cargador, la
## corredera y la mano izquierda en cada instante. Sin esto no se puede decidir
## si la animación o la lógica deben mandar sobre el hueso del cargador.
func _sample_reload(ap: AnimationPlayer, skeleton: Skeleton3D, root: Node, gun: MeshInstance3D) -> void:
    var anim_name := ""
    for candidate in ap.get_animation_list():
        if candidate.ends_with("Reload"):
            anim_name = candidate
    if anim_name == "":
        print("DUMP sin animación de recarga")
        return
    ap.play(anim_name)
    var chain := _local_chain(skeleton, root)
    var ids := {}
    for bone_name in ["Root", "Magazine", "Slide", "SlideCatch", "Hand.L", "Hand.R.001", "Thumb.L", "Index.L"]:
        var idx := skeleton.find_bone(bone_name)
        if idx >= 0:
            ids[bone_name] = idx
    var t := 0.0
    while t <= 2.1:
        ap.seek(t, true)
        skeleton.force_update_all_bone_transforms()
        var line := "DUMP RELOAD t=%.2f" % t
        var mag := Vector3.ZERO
        var hand := Vector3.ZERO
        for bone_name in ids:
            var p: Vector3 = (chain * skeleton.get_bone_global_pose(ids[bone_name])).origin
            if bone_name == "Magazine":
                mag = p
            if bone_name == "Hand.L":
                hand = p
            line += " %s=(%.3f,%.3f,%.3f)" % [bone_name, p.x, p.y, p.z]
        line += " mano_a_cargador=%.3f" % (hand - mag).length()
        print(line)
        t += 0.1
    ap.stop()
