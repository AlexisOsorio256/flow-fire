extends Node3D

## Brazos en primera persona.
##
## Asset: "Fps Rig" de J-Toastie (CC-BY 3.0, vía Poly Pizza), del mismo pack que
## el Glock. Es un rig sin animaciones (24 huesos: brazos, manos y dedos), así
## que la pose se resuelve aquí: se miden los huesos en runtime, se coloca la
## mano derecha en la empuñadura y la izquierda de apoyo, y los brazos siguen el
## movimiento del arma porque cuelgan de su misma raíz de pose.
##
## Nada de números inventados: la escala sale del largo real de la mano y los
## puntos de agarre de la caja medida del arma.

const ARMS_MODEL := preload("res://assets/models/fps_arms.glb")
const SHADER: Shader = preload("res://shaders/gun.gdshader")

# Escala calibrada con el antebrazo (codo -> muñeca), que en el rig es la
# medida más fiable: calibrando con la mano el antebrazo salía enorme.
const FOREARM_LENGTH := 0.22  # antebrazo estilizado (el rig es cabezón)
# Punto de agarre de la mano derecha dentro del espacio de bind de los brazos,
# medido entre la muñeca y los nudillos.
const GRIP_OFFSET := Vector3(0.013, -0.04, 0.0)

var gun                      # el Glock del juego (para medir la empuñadura)
var model_root: Node3D
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var arms_to_weapon := Transform3D.IDENTITY
var skeleton_to_weapon := Transform3D.IDENTITY
var grip_weapon := Vector3.ZERO

var _hand_bones := {}


func setup(weapon) -> void:
    gun = weapon
    _build()
    _align()
    _pose_hands()


func _build() -> void:
    model_root = ARMS_MODEL.instantiate()
    model_root.name = "ArmsModel"
    model_root.transform = Transform3D.IDENTITY
    add_child(model_root)

    skeleton = model_root.find_child("Skeleton3D", true, false) as Skeleton3D
    mesh = model_root.find_child("ArmModel", true, false) as MeshInstance3D
    if mesh != null:
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        var materials := _build_materials()
        for i in range(mesh.mesh.get_surface_count()):
            var surface_name: String = mesh.mesh.surface_get_name(i)
            if materials.has(surface_name):
                mesh.set_surface_override_material(i, materials[surface_name])
            else:
                push_warning("Superficie de brazos sin material: %s" % surface_name)
    if skeleton == null:
        push_error("Los brazos no traen esqueleto")


## Materiales de los brazos con el mismo shader procedural del arma.
func _build_materials() -> Dictionary:
    return {
        # Manga de camiseta: tela mate.
        "Shirt": _material(Color(0.30, 0.31, 0.33), 0.0, 0.86, 90.0, 0.06),
        # Piel.
        "Skin": _material(Color(0.42, 0.29, 0.22), 0.0, 0.62, 260.0, 0.05),
        # Guante táctico.
        "Glove": _material(Color(0.075, 0.078, 0.085), 0.05, 0.55, 230.0, 0.10),
    }


func _material(color: Color, metallic: float, roughness: float, detail_scale: float, detail_albedo: float) -> ShaderMaterial:
    var mat := ShaderMaterial.new()
    mat.shader = SHADER
    mat.set_shader_parameter("base_color", color)
    mat.set_shader_parameter("metallic", metallic)
    mat.set_shader_parameter("roughness", roughness)
    mat.set_shader_parameter("detail_scale", detail_scale)
    mat.set_shader_parameter("detail_albedo", detail_albedo)
    mat.set_shader_parameter("wear", 0.12)
    return mat


## Mide la base real de los brazos y los lleva al frame del arma.
## Bind: +X hacia delante (hombro -> dedos), +Y izquierda (los huesos .L), +Z arriba.
func _align() -> void:
    if skeleton == null or mesh == null or mesh.skin == null:
        return
    var elbow := _bone_bind_position("LowerArm.R.001")
    var wrist := _bone_bind_position("Hand.R.001")
    var forearm_units := (wrist - elbow).length()
    if forearm_units <= 0.0001:
        push_error("No se pudo medir el antebrazo de los brazos")
        return
    var total_scale := FOREARM_LENGTH / forearm_units

    # Cadena real: modelo -> Armature -> bind poses.
    var bind_in_skeleton: Transform3D = skeleton.get_bone_global_rest(0) * mesh.skin.get_bind_pose(0)
    var bind_in_model: Transform3D = _local_chain(skeleton, model_root) * bind_in_skeleton

    # Frame de los brazos medido: derecha = -Y_bind, arriba = +Z_bind, atrás = -X_bind.
    var arms_frame := Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))
    model_root.basis = Basis.IDENTITY.scaled(Vector3.ONE * total_scale) * (bind_in_model.basis * arms_frame).inverse()
    model_root.position = Vector3.ZERO
    arms_to_weapon = model_root.transform * bind_in_model

    # Los hombros quedan detrás de la cámara; las manos las coloca el IK.
    skeleton_to_weapon = arms_to_weapon * bind_in_skeleton.affine_inverse()
    model_root.position += Vector3(0.0, -0.02, 0.16)
    arms_to_weapon.origin = model_root.position
    print("ARMS escala=", snappedf(total_scale, 0.01), " antebrazo_bind=", snappedf(forearm_units, 0.0001),
        " codo_mundo=", (arms_to_weapon * elbow).snapped(Vector3(0.001, 0.001, 0.001)))


## Punto donde la mano debe cerrarse sobre la empuñadura, medido sobre la caja
## real del arma (mitad de la empuñadura, un poco por encima de la base).
func _gun_grip_point() -> Vector3:
    var box: AABB = gun.gun_box
    return Vector3(0.0, box.position.y + box.size.y * 0.30, box.position.z + box.size.z * 0.80)


## Pose de agarre por IK analítico de dos huesos. El rig viene en cruz (las dos
## manos al mismo punto), así que la pose se resuelve aquí: la mano derecha
## empuña y la izquierda apoya delante, con los codos hacia abajo y afuera.
func _pose_hands() -> void:
    if skeleton == null:
        return
    var grip := _gun_grip_point()
    grip_weapon = grip
    # Muñeca derecha: detrás y algo por debajo del agarre (la mano envuelve).
    _solve_arm("R", grip + Vector3(0.012, -0.030, 0.060), Vector3(0.0, -0.35, -1.0))
    # Muñeca izquierda: delante y debajo, apoyando bajo el guardamonte.
    _solve_arm("L", grip + Vector3(-0.010, -0.045, -0.055), Vector3(0.0, 0.35, -1.0))
    _print_hands()


func _print_hands() -> void:
    for side in ["L", "R"]:
        var suffix := ".L" if side == "L" else ".R.001"
        var hand := skeleton.find_bone("Hand" + suffix)
        var knuckles := skeleton.find_bone("DoubleFingersBeginning" + ("" if side == "L" else ".001"))
        var tip := skeleton.find_bone("IndexTip" + suffix)
        if hand < 0 or knuckles < 0:
            continue
        var p_hand := skeleton_to_weapon * skeleton.get_bone_global_pose(hand).origin
        var p_knuckles := skeleton_to_weapon * skeleton.get_bone_global_pose(knuckles).origin
        var p_tip := skeleton_to_weapon * skeleton.get_bone_global_pose(tip).origin
        print("ARMS mano ", side, " muneca=", p_hand.snapped(Vector3(0.001,0.001,0.001)),
            " nudillos=", p_knuckles.snapped(Vector3(0.001,0.001,0.001)),
            " punta=", p_tip.snapped(Vector3(0.001,0.001,0.001)),
            " agarre=", grip_weapon.snapped(Vector3(0.001,0.001,0.001)))


func _solve_arm(side: String, target_weapon: Vector3, pole_bind: Vector3) -> void:
    var suffix := ".L" if side == "L" else ".R.001"
    var upper := skeleton.find_bone("UpperArm" + suffix)
    var lower := skeleton.find_bone("LowerArm" + suffix)
    var hand := skeleton.find_bone("Hand" + suffix)
    if upper < 0 or lower < 0 or hand < 0:
        push_warning("Faltan huesos del brazo %s" % side)
        return

    var shoulder := skeleton.get_bone_global_rest(upper).origin
    var elbow_rest := skeleton.get_bone_global_rest(lower).origin
    var wrist_rest := skeleton.get_bone_global_rest(hand).origin
    var l1 := (elbow_rest - shoulder).length()
    var l2 := (wrist_rest - elbow_rest).length()

    var target := skeleton_to_weapon.affine_inverse() * target_weapon
    var to_target := target - shoulder
    var distance := clampf(to_target.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
    var axis := to_target.normalized()

    var pole := (skeleton_to_weapon.basis * pole_bind).normalized()
    var perp := (pole - axis * pole.dot(axis))
    if perp.length_squared() < 1e-8:
        perp = axis.cross(Vector3.UP)
    perp = perp.normalized()

    var cos_a := clampf((l1 * l1 + distance * distance - l2 * l2) / (2.0 * l1 * distance), -1.0, 1.0)
    var bend := acos(cos_a)
    var elbow := shoulder + (axis * cos(bend) + perp * sin(bend)) * l1
    var wrist := shoulder + axis * distance
    var hinge := perp.cross(axis).normalized()

    # Direcciones en espacio del ESQUELETO (skeleton_to_weapon lleva esqueleto
    # -> arma, así que para lo contrario hay que invertir).
    var to_skeleton := skeleton_to_weapon.basis.inverse()
    _set_bone_global(upper, shoulder, elbow - shoulder, hinge)
    _set_bone_global(lower, elbow, wrist - elbow, hinge)
    _set_bone_global(hand, wrist, to_skeleton * Vector3(0, 0, -1), to_skeleton * Vector3(0, 1, 0))


## Coloca un hueso en pose global (espacio del esqueleto). El +Y del hueso
## apunta a lo largo del hueso, como en este rig.
func _set_bone_global(index: int, origin: Vector3, direction: Vector3, up_ref: Vector3) -> void:
    var y := direction.normalized()
    var x := up_ref.cross(y)
    if x.length_squared() < 1e-8:
        x = y.cross(Vector3.UP)
    x = x.normalized()
    var z := x.cross(y).normalized()
    skeleton.set_bone_global_pose_override(index, Transform3D(Basis(x, y, z), origin), 1.0, true)


func _bone_bind_position(bone_name: String) -> Vector3:
    var index := skeleton.find_bone(bone_name)
    if index < 0:
        push_warning("Falta el hueso %s en los brazos" % bone_name)
        return Vector3.ZERO
    var bind_in_skeleton: Transform3D = skeleton.get_bone_global_rest(0) * mesh.skin.get_bind_pose(0)
    return bind_in_skeleton.affine_inverse() * skeleton.get_bone_global_rest(index).origin


func _local_chain(node: Node, ancestor: Node) -> Transform3D:
    var result := Transform3D.IDENTITY
    var current := node
    while current != null and current != ancestor:
        if current is Node3D:
            result = (current as Node3D).transform * result
        current = current.get_parent()
    return result
