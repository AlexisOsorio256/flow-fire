extends Node

## Diagnostico del arma y del rig. Responde "donde esta cada cosa y cuanto
## mide", no "se ve bien". Secciones, en orden de lectura:
##
##   --recoilprobe     perfil real de retroceso del primer disparo
##   --geometrydebug   geometria, encuadre y ciclo mecanico (corredera, recarga)
##   --armdiag         encuadre de brazos y silueta en % de pantalla
##   --gundiag         geometria del rig: piel, miras, muñeca, escala manos/arma

## Huesos que deciden el encuadre de los brazos: hombro, codo, mano y punta de
## cada dedo. `Rif` es el arma, y sirve de referencia de "donde deberia estar la
## mano izquierda si el agarre fuera a dos manos".
const ARM_BONES := [
    "Arm_L", "UpArm_L", "Forearm_L", "Hand_L",
    "Bone_L.007", "Bone_L.011", "Bone_L.015", "Bone_L.019", "Bone_L.022",
    "Arm_R", "UpArm_R", "Forearm_R", "Hand_R",
    "Bone_R.007", "Bone_R.011", "Bone_R.015", "Bone_R.019", "Bone_R.022",
    "Rif",
]

## ---------------------------------------------------------------------------
## Diagnóstico del arma real del viewmodel (rig full9mm de 1Matzh).
##
## Los marcadores de Glock (SightMarker/FrontMarker/Muzzle) son hijos fijos de
## un soporte y NO describen la pistola visible, que vive dentro del esqueleto
## animado. Este instrumento mide la pistola de verdad de dos formas
## independientes que deben coincidir:
##   1) huesos: Slidder_919 (corredera), Barrel_920, Weapon_922, gatillo y
##      cargador, con los puntos de mira derivados OFFLINE de la geometría de
##      la corredera (ver GUNDIAG_SIGHT_*);
##   2) piel: AABB de las mallas del arma (Object_938/939/940) frente a manos
##      (Object_8) y antebrazos (Object_7), en el MISMO espacio (esqueleto),
##      la MISMA pose (Idle aparcada) y la MISMA escala.
## FUENTE de cada número: MEDIDO EN ESTE ASSET salvo que se diga lo contrario.
## ---------------------------------------------------------------------------
# Puntos de mira en espacio local del hueso Slidder_919 (metros del asset).
# Extraídos offline de la malla de corredera (1486 verts): alza = centroide del
# 15% superior dentro del 10% trasero; punto = idem en el 8% delantero; boca =
# centroide del 10% delantero del cañón expresado en la corredera. Línea de
# mira resultante (0, -0.004, 1.0), radio 158.3 mm, altura sobre el eje 13.6 mm
# (una G19 real anda por 160 mm y ~13 mm: el asset es dimensionalmente honesto).
const GUNDIAG_REAR := Vector3(-0.0037, 0.01081, -0.0538)

const GUNDIAG_FRONT := Vector3(-0.0037, 0.01022, 0.10447)

const GUNDIAG_MUZZLE_SLIDE := Vector3(-0.0037, -0.00283, 0.11336)

const GUNDIAG_GUN_BONES := ["Slidder_919", "Barrel_920", "Weapon_922",
    "Weapon_Trigger_921", "Magazine_924"]

var _player: CharacterBody3D
var _hud: CanvasLayer
var common: DevCommon

var _hip_bbox := Rect2()          # caja del arma en pantalla con la pose de lista
var _exposure_hip := {}           # exposición medida del arma en hip
var _exposure_ads := {}           # exposición medida del arma en ADS
var _recoil_time := 0.0


func setup(main_node: Node3D, player_node: CharacterBody3D, hud_node: CanvasLayer, common_node) -> void:
    _player = player_node
    _hud = hud_node
    common = common_node


## TEMPORAL (se retira al cerrar el pulido del retroceso): mide, frame a frame y
## a escala 1, cuanto gira y cuanto se desplaza el arma respecto a la camara
## durante el primer instante de un disparo, y lo compara con lo que solo aporta
## la capa procedural. Sirve para saber en que ms esta el pico y si el arma se
## mueve o solo se mueve la vaina.
func run_recoilprobe() -> void:
    await get_tree().create_timer(0.8).timeout
    var w = _player.weapon
    w.set_aim(false)
    await get_tree().create_timer(0.4).timeout
    # A escala 1 el ciclo entero (60 ms) cabe en 1-2 frames de esta maquina, asi
    # que se muestrea a 0.08: cada frame vale 1.3 ms de tiempo de juego y el
    # reloj se acumula con el delta real, no con el reloj de pared.
    _recoil_time = 0.0
    var fwd0 := Vector3.ZERO
    w.force_fire_once()
    Engine.time_scale = 0.08
    for i in range(46):
        await get_tree().process_frame
        _recoil_time += w.last_delta
        var cam: Camera3D = _player.camera
        var cam_inv := cam.global_transform.affine_inverse()
        var gun_xf: Transform3D = w.viewmodel.arms_skeleton.global_transform * w.viewmodel.arms_skeleton.get_bone_global_pose(w.viewmodel.slide_bone)
        var up: Vector3 = (cam_inv.basis * gun_xf.basis.y).normalized()
        var fwd: Vector3 = (cam_inv.basis * gun_xf.basis.z).normalized()
        if fwd0 == Vector3.ZERO:
            fwd0 = fwd
        var elev := rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
        var azim := rad_to_deg(atan2(fwd.x, fwd.z))
        var elev0 := rad_to_deg(asin(clampf(fwd0.y, -1.0, 1.0)))
        var azim0 := rad_to_deg(atan2(fwd0.x, fwd0.z))
        print("RECOIL %02d t=%5.1fms elev=%6.2f (d=%6.2f) azim=%6.2f (d=%6.2f) roll=%6.2f slide=%5.1fmm proc(wrist=%5.2f° arm=%5.2f°) cam=%5.2f°" % [
            i, _recoil_time * 1000.0, elev, elev - elev0, azim, azim - azim0,
            rad_to_deg(atan2(up.x, up.y)),
            w.slide_pos * 1000.0, rad_to_deg(w.recoil.rot.x), rad_to_deg(w.recoil.arm_rot.x),
            rad_to_deg(_player.recoil_pitch)])
    Engine.time_scale = 1.0
    print("RECOILPROBE_DONE")
    get_tree().quit()


## ---------------------------------------------------------------------------
## Geometria, encuadre y ciclo mecanico (--geometrydebug)
## ---------------------------------------------------------------------------
func run_geometrydebug() -> void:
    await get_tree().create_timer(0.8).timeout
    _player.weapon.set_aim(false)
    await common.settle_pose()
    _print_geometry("hip")
    _exposure_hip = await _measure_gun_exposure("hip")
    _player.weapon.set_aim(true)
    await common.settle_pose()
    _print_geometry("ads")
    _exposure_ads = await _measure_gun_exposure("ads")
    _player.weapon.set_aim(false)
    await get_tree().create_timer(0.4).timeout
    var travel := _print_bone_travel()
    var cycle := _measure_slide_cycle()
    # Durante la recarga: recorrido real del cargador y estado de los huesos.
    common.force_reloadable_state()
    _player.weapon.start_reload()
    await get_tree().create_timer(0.45).timeout
    _print_geometry("reload")
    _print_live_bones("reload")
    var mag: Dictionary = await _measure_reload_mag()
    _finish_geometrydebug(travel, cycle, mag)


## Comprueba las medidas del arma: si deja de medirse o alinearse bien, el
## comando falla (es el ojo que vigila la alineación medida en runtime).


## Posición viva de los huesos del arma (pose actual) en espacio de recoil.
func _print_live_bones(label: String) -> void:
    var w = _player.weapon
    var sk: Skeleton3D = w.viewmodel.arms_skeleton
    if sk == null:
        return
    var recoil_inv: Transform3D = (w.viewmodel.recoil_node as Node3D).global_transform.affine_inverse()
    for bone_name in ["Slidder_919", "Magazine_924", "Weapon_Trigger_921", "Barrel_920"]:
        var bi := sk.find_bone(bone_name)
        if bi < 0:
            continue
        var live: Vector3 = recoil_inv * (sk.global_transform * sk.get_bone_global_pose(bi).origin)
        print("LIVE ", label, " ", bone_name, " pose=", live.snapped(Vector3(0.0001, 0.0001, 0.0001)),
            " slide_pos=", snappedf(w.slide_pos, 0.0001))


## Comprueba que la corredera viaja hacia atrás (-Z local, hacia el tirador)
## cuando la logica la mueve: el hueso Slidder lo escribe _apply_pistol_parts
## desde slide_pos, asi que esto vigila la autoridad mecanica real.
func _print_bone_travel() -> Dictionary:
    var w = _player.weapon
    var sk: Skeleton3D = w.viewmodel.arms_skeleton
    var rest: Vector3 = sk.get_bone_pose_position(w.viewmodel.slide_bone)
    w.slide_pos = w.SLIDE_TRAVEL
    w.viewmodel.apply_mechanics(w.slide_pos, w.SLIDE_TRAVEL, w.trigger_visual)
    var posed: Vector3 = sk.get_bone_pose_position(w.viewmodel.slide_bone)
    w.slide_pos = 0.0
    w.viewmodel.apply_mechanics(w.slide_pos, w.SLIDE_TRAVEL, w.trigger_visual)
    var delta: Vector3 = posed - rest
    print("TRAVEL Slidder rest=", rest.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " posed=", posed.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " delta=", delta.snapped(Vector3(0.0001, 0.0001, 0.0001)))
    return {"Slide": delta}


## Recorrido del cargador durante una recarga real, medido en vivo sobre su
## hueso: lo lleva la mano en la animacion de recarga, asi que se muestrea
## mientras ocurre. El recorrido es el diametro de la nube de posiciones (sin
## referencia de reposo: la animacion manda el gesto, la logica los cartuchos).
func _measure_reload_mag() -> Dictionary:
    var w = _player.weapon
    var sk: Skeleton3D = w.viewmodel.arms_skeleton
    if sk == null:
        return {}
    var mag_bone := sk.find_bone("Magazine_924")
    if mag_bone < 0:
        return {}
    var samples: Array[Vector3] = []
    var on_screen := 0
    var best_margin := -1e9
    var viewport := get_viewport().get_visible_rect().size
    var cam: Camera3D = _player.camera
    for _i in range(26):
        await get_tree().create_timer(0.1).timeout
        var world: Vector3 = sk.global_transform * sk.get_bone_global_pose(mag_bone).origin
        samples.append(world)
        # Lo que importa de verdad: que el cargador se VEA salir y entrar.
        if not cam.is_position_behind(world):
            var screen := cam.unproject_position(world)
            var margin := minf(minf(screen.x, viewport.x - screen.x), minf(screen.y, viewport.y - screen.y))
            best_margin = maxf(best_margin, margin)
            if margin > 20.0:
                on_screen += 1
    var max_travel := 0.0
    for a in samples:
        for b in samples:
            max_travel = maxf(max_travel, a.distance_to(b))
    print("RELOAD_MAG recorrido_max=", snappedf(max_travel, 0.001),
        " m muestras_en_pantalla=", on_screen, "/26 margen_max=", snappedf(best_margin, 0.1), "px")
    return {"travel": max_travel, "on_screen": on_screen}


func _print_geometry(label: String) -> void:
    var cam: Camera3D = _player.camera
    var w = _player.weapon
    if w.viewmodel.slide_attach == null:
        print("GEOMETRY ", label, " sin arma")
        return
    var recoil_inv: Transform3D = (w.viewmodel.recoil_node as Node3D).global_transform.affine_inverse()
    # La caja de la corredera real (SLIDE_BOX, en su espacio) proyectada por el
    # global del attachment que la sigue.
    var bbox := common.screen_bbox(w.viewmodel.gun_box, (w.viewmodel.slide_attach as Node3D).global_transform, cam)
    var sight_screen: Vector2 = cam.unproject_position(w.viewmodel.get_sight_world_position())
    var muzzle_screen: Vector2 = cam.unproject_position(w.viewmodel.muzzle.global_position)
    var sight_cam: Vector3 = cam.global_transform.affine_inverse() * w.viewmodel.get_sight_world_position()
    var muzzle_cam: Vector3 = cam.global_transform.affine_inverse() * w.viewmodel.muzzle.global_position
    var pm: Vector3 = recoil_inv * (w.viewmodel.muzzle as Node3D).global_position
    var pe: Vector3 = recoil_inv * (w.viewmodel.ejection_port as Node3D).global_position
    var ps: Vector3 = recoil_inv * w.viewmodel.get_sight_world_position()
    print("MOUNT ", label, " escala_brazos=", snappedf(w.viewmodel.arms_scale, 0.0001),
        " ads_offset=", w.viewmodel.ads_offset.snapped(Vector3(0.001, 0.001, 0.001)),
        " ads_rot_deg=", (w.viewmodel.ads_rot * 180.0 / PI).snapped(Vector3(0.1, 0.1, 0.1)))
    print("GUNBOX ", label,
        " min=", w.viewmodel.gun_box.position.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " size=", w.viewmodel.gun_box.size.snapped(Vector3(0.0001, 0.0001, 0.0001)))
    if w.viewmodel.arms_skeleton != null:
        var sk: Skeleton3D = w.viewmodel.arms_skeleton
        for bone_name in ["Slidder_919", "Barrel_920", "Weapon_922", "Magazine_924", "DEF-hand.R_842"]:
            var bi := sk.find_bone(bone_name)
            if bi >= 0:
                var gp: Vector3 = sk.global_transform * sk.get_bone_global_pose(bi).origin
                var rel: Vector3 = recoil_inv * gp
                print("BONE ", label, " ", bone_name, " rel=", rel.snapped(Vector3(0.0001, 0.0001, 0.0001)))
    print("AXES ", label,
        " sight_local=", ps.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " muzzle_local=", pm.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " eject_local=", pe.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " barrel_dir=", (pm - ps).normalized().snapped(Vector3(0.001, 0.001, 0.001)))
    print("GEOMETRY ", label,
        " bbox_min=", bbox["min"].snapped(Vector2(0.1, 0.1)),
        " bbox_max=", bbox["max"].snapped(Vector2(0.1, 0.1)),
        " bbox_size=", bbox["size"].snapped(Vector2(0.1, 0.1)),
        " sight_screen=", sight_screen.snapped(Vector2(0.1, 0.1)),
        " muzzle_screen=", muzzle_screen.snapped(Vector2(0.1, 0.1)),
        " sight_cam=", sight_cam.snapped(Vector3(0.001, 0.001, 0.001)),
        " muzzle_cam=", muzzle_cam.snapped(Vector3(0.001, 0.001, 0.001)),
        " viewport=", get_viewport().get_visible_rect().size)
    if label == "hip":
        _hip_bbox = Rect2(bbox["min"], bbox["size"])


## Cuánta luz recibe de verdad el arma en pantalla. El arma se aísla por
## diferencia (captura con y sin ella) para que la medida no la contamine el
## fondo: devuelve la luminancia media de sus píxeles, el percentil 90, cuántos
## están recortados a blanco y cuántos a negro.
func _measure_gun_exposure(label: String) -> Dictionary:
    Engine.time_scale = 0.0
    await get_tree().process_frame
    await get_tree().process_frame
    # El objetivo es medir la pistola, no la tela que la rodea: en ADS los brazos
    # ocupan la mayoría de los píxeles distintos del fondo y hundían el p90
    # aunque la corredera estuviese correctamente expuesta.
    # Se aisla la pistola apagando solo las mallas de brazos (manos+mangas):
    # antes se apagaba arms_root entero y la pistola se iba con el.
    var arm_meshes := common.gun_family_meshes(_player.weapon, ["Object_8", "Object_7"])
    var arms_was: Array = []
    for m in arm_meshes:
        arms_was.append((m as MeshInstance3D).visible)
        (m as MeshInstance3D).visible = false
    await get_tree().process_frame
    var with_gun := await common.capture_image()
    _player.weapon.visible = false
    await get_tree().process_frame
    await get_tree().process_frame
    var without := await common.capture_image()
    _player.weapon.visible = true
    for i in range(arm_meshes.size()):
        (arm_meshes[i] as MeshInstance3D).visible = arms_was[i]
    Engine.time_scale = 1.0
    if with_gun == null or without == null:
        print("EXPOSURE ", label, " sin captura")
        return {}
    with_gun.convert(Image.FORMAT_RGB8)
    without.convert(Image.FORMAT_RGB8)
    var a := with_gun.get_data()
    var b := without.get_data()
    var width := with_gun.get_width()
    var height := with_gun.get_height()
    var samples := PackedFloat32Array()
    var total := 0
    var sum := 0.0
    var bright := 0
    var dark := 0
    var step := 2
    for y in range(0, height, step):
        for x in range(0, width, step):
            var i := (y * width + x) * 3
            var dr := absi(a[i] - b[i])
            var dg := absi(a[i + 1] - b[i + 1])
            var db := absi(a[i + 2] - b[i + 2])
            if dr + dg + db < 6:
                continue
            var luma := (a[i] * 0.299 + a[i + 1] * 0.587 + a[i + 2] * 0.114) / 255.0
            samples.append(luma)
            sum += luma
            total += 1
            if luma > 0.96:
                bright += 1
            if luma < 0.03:
                dark += 1
    if total == 0:
        print("EXPOSURE ", label, " el arma no ocupa ningún píxel")
        return {}
    samples.sort()
    var result := {
        "pixels": total,
        "mean": sum / float(total),
        "p90": samples[int(float(total) * 0.90)],
        "blown": float(bright) / float(total),
        "black": float(dark) / float(total),
    }
    print("EXPOSURE ", label, " px=", total,
        " media=", snappedf(result["mean"] * 255.0, 0.1), "/255",
        " p90=", snappedf(result["p90"] * 255.0, 0.1),
        " recortado=", snappedf(result["blown"] * 100.0, 0.1), "%",
        " negro=", snappedf(result["black"] * 100.0, 0.1), "%")
    return result


## Mide el ciclo REAL de la corredera usando el integrador del juego (no una
## copia): se dispara el impulso de un tiro y se avanza el subpaso con dt fijo
## hasta que vuelve a batería. Devuelve recorrido máximo y tiempos, que son el
## contrato de "la corredera se ve viajar".
func _measure_slide_cycle() -> Dictionary:
    var w = _player.weapon
    w.slide_pos = 0.0
    w.slide_vel = 0.0
    w.slide_locked = false
    w.slide_open = false
    w.slide_extracted = false
    w.slide_vel += w.SLIDE_IMPULSE  # mismo impulso que _fire()
    var dt := 0.001
    var peak := 0.0
    var t_total := 0.0
    var t_above := 0.0
    var came_back := false
    for i in range(400):
        w._update_slide(dt)
        var t := float(i) * dt
        peak = maxf(peak, w.slide_pos)
        if w.slide_pos > 0.025:
            t_above += dt
        if i > 4 and w.slide_pos < 0.002 and not came_back:
            came_back = true
            t_total = t
    if not came_back:
        t_total = 0.4
    w.slide_pos = 0.0
    w.slide_vel = 0.0
    var result := {"peak": peak, "total": t_total, "above": t_above}
    print("SLIDECYCLE recorrido_max=", snappedf(peak * 1000.0, 0.1), " mm",
        " ciclo_total=", snappedf(t_total * 1000.0, 1), " ms",
        " sobre_25mm=", snappedf(t_above * 1000.0, 1), " ms")
    return result


func _bind_aabb(mesh: MeshInstance3D) -> AABB:
    var result := AABB()
    var first := true
    for surface in range(mesh.mesh.get_surface_count()):
        var arrays := mesh.mesh.surface_get_arrays(surface)
        if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
            continue
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        for v in verts:
            if first:
                result = AABB(v, Vector3.ZERO)
                first = false
            else:
                result = result.expand(v)
    return result


func _finish_geometrydebug(travel: Dictionary, cycle: Dictionary, mag: Dictionary) -> void:
    var w = _player.weapon
    var failures: Array[String] = []
    var viewport := get_viewport().get_visible_rect().size
    var low_res_headless := viewport.x < 256.0 or viewport.y < 256.0
    if not w.viewmodel.pistol_ok:
        failures.append("los huesos mecanicos no quedaron utilizables")
    # Caja de la corredera real (SLIDE_BOX del asset: 29.4 x 42.4 x 176.3 mm).
    var size: Vector3 = w.viewmodel.gun_box.size
    if absf(size.x - 0.0294) > 0.004 or absf(size.y - 0.0424) > 0.004 or absf(size.z - 0.1763) > 0.004:
        failures.append("caja del arma %s (esperado ~0.029 x 0.042 x 0.176)" % size)
    # La corredera viaja hacia atras en su espacio local (-Z): con el recorrido
    # logico completo son -33.6 mm en el asset.
    var slide: Vector3 = travel.get("Slide", Vector3.ZERO)
    if slide.z > -0.02:
        failures.append("la corredera no viaja hacia atrás (delta %s)" % slide)
    if float(mag.get("travel", 0.0)) < 0.08:
        failures.append("el cargador casi no se separa del arma al recargar (%.3f m)" % float(mag.get("travel", 0.0)))
    if not low_res_headless and int(mag.get("on_screen", 0)) < 3:
        failures.append("el cargador no llega a verse en pantalla al recargar (%d/26 muestras)" % int(mag.get("on_screen", 0)))

    # Encuadre: el arma tiene que caber en pantalla con la pose de lista. Antes
    # quedaban 264 px por debajo del borde y sólo se veía media corredera.
    if _hip_bbox.size.y < 1.0:
        failures.append("no se midió el encuadre del arma")
    else:
        var top_frac := _hip_bbox.position.y / viewport.y
        var visible := (minf(_hip_bbox.end.y, viewport.y) - maxf(_hip_bbox.position.y, 0.0)) / maxf(_hip_bbox.size.y, 1.0)
        var right_frac := _hip_bbox.end.x / viewport.x
        var left_frac := _hip_bbox.position.x / viewport.x
        var centre_frac := (_hip_bbox.position.x + _hip_bbox.size.x * 0.5) / viewport.x
        if _hip_bbox.position.y < 0.24 * viewport.y:
            failures.append("el arma tapa el centro de la pantalla (y=%.0f de %.0f)" % [_hip_bbox.position.y, viewport.y])
        if top_frac > 0.74:
            failures.append("el arma está demasiado baja: su borde superior cae en y=%.0f (%.0f%% de la pantalla)" % [_hip_bbox.position.y, top_frac * 100.0])
        if visible < 0.94:
            failures.append("sólo se ve el %.0f%% del arma en pose de lista" % (visible * 100.0))
        if right_frac > 1.02:
            failures.append("el arma se sale por la derecha (x=%.0f de %.0f)" % [_hip_bbox.end.x, viewport.x])
        if left_frac < -0.02:
            failures.append("el arma se sale por la izquierda (x=%.0f)" % _hip_bbox.position.x)
        # Centrado: el arma va en el centro del encuadre, no desplazada a un lado.
        if absf(centre_frac - 0.5) > 0.09:
            failures.append("el arma no va centrada: su centro cae en el %.0f%% del ancho" % (centre_frac * 100.0))

    # Exposición: ni silueta negra ni mancha recortada.
    for entry in [["hip", _exposure_hip], ["ads", _exposure_ads]]:
        var label: String = entry[0]
        var data: Dictionary = entry[1]
        if data.is_empty():
            if not low_res_headless:
                failures.append("no se pudo medir la exposición del arma en %s" % label)
            continue
        if data["mean"] * 255.0 < 14.0:
            failures.append("el arma está sin luz en %s (media %.1f/255)" % [label, data["mean"] * 255.0])
        if data["p90"] * 255.0 < 32.0:
            failures.append("el arma no tiene zonas claras en %s (p90 %.1f/255)" % [label, data["p90"] * 255.0])
        if data["blown"] > 0.02:
            failures.append("brillo especular recortado en %s (%.1f%% de sus píxeles)" % [label, data["blown"] * 100.0])

    # Ciclo de corredera: recorrido completo y legible.
    if not cycle.is_empty():
        if cycle["peak"] < 0.0385 or cycle["peak"] > 0.041:
            failures.append("la corredera no completa su recorrido (%.1f mm)" % (cycle["peak"] * 1000.0))
        if cycle["above"] < 0.015:
            failures.append("la corredera pasa demasiado rápido por el fondo (%.1f ms sobre 25 mm)" % (cycle["above"] * 1000.0))
        if cycle["total"] < 0.045 or cycle["total"] > 0.09:
            failures.append("el ciclo de corredera sale del rango de alta velocidad (%.0f ms)" % (cycle["total"] * 1000.0))

    var passed := failures.is_empty()
    if low_res_headless:
        print("GEOMETRYDEBUG nota=viewport dummy de ", viewport,
            "; se omiten exposición y visibilidad en pantalla del cargador")
    var view := viewport
    print("ENCUADRE hip_centro_x=", snappedf((_hip_bbox.position.x + _hip_bbox.size.x * 0.5) / view.x * 100.0, 0.1),
        "% del ancho, ancho=", snappedf(_hip_bbox.size.x / view.x * 100.0, 0.1), "%",
        " alto=", snappedf(_hip_bbox.size.y / view.y * 100.0, 0.1), "%",
        " borde_sup=", snappedf(_hip_bbox.position.y / view.y * 100.0, 0.1), "%")
    print("GEOMETRYDEBUG passed=", passed, " caja=", size.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " slide=", slide.snapped(Vector3(0.001, 0.001, 0.001)),
        " cargador=", snappedf(float(mag.get("travel", 0.0)), 0.001), " m visible=", int(mag.get("on_screen", 0)), "/26")
    if not passed:
        push_error("GEOMETRYDEBUG falló: " + "; ".join(failures))
    get_tree().quit(0 if passed else 1)


## Tabla de encuadre de los huesos de los brazos: por cada hueso, donde cae en
## pantalla y con cuanto margen. Un margen negativo significa que el hueso queda
## FUERA del viewport; "detras" significa que esta por detras del plano de la
## camara. Esto es lo que decide si los hombros salen o no, sin discutirlo.
## ---------------------------------------------------------------------------
## Encuadre de brazos y silueta (--armdiag)
## ---------------------------------------------------------------------------
func run_armdiag() -> void:
    await get_tree().create_timer(0.8).timeout
    _player.weapon.set_aim(false)
    await common.settle_pose()
    _print_arm_frame("hip")
    _print_silhouette("hip")
    _player.weapon.set_aim(true)
    await common.settle_pose()
    _print_arm_frame("ads")
    _print_silhouette("ads")
    _player.weapon.set_aim(false)
    await common.settle_pose()
    _print_arm_screen_box("hip")
    print("ARM_DIAG_DONE")
    get_tree().quit()


## Cobertura real de silueta: cuánta pantalla ocupan los brazos y cuánta el
## arma, y en qué zonas. Es la medida que distingue "la persona sostiene la
## pistola" de "dos masas tapan las esquinas", un juicio que a ojo se pierde
## entre cambios. Rasteriza los triángulos de verdad (no sólo los vértices)
## sobre una rejilla gruesa: un triángulo grande con 3 vértices cuenta lo que
## ocupa en pantalla.
func _print_silhouette(label: String) -> void:
    var w = _player.weapon
    if w.viewmodel.arms_root == null or w.viewmodel.arms_skeleton == null or w.viewmodel.arms_mesh_visible == null:
        return
    var cam: Camera3D = _player.camera
    var vp := get_viewport().get_visible_rect().size
    const GW := 96
    const GH := 54
    var gun_meshes: Array = []
    for m in common.viewmodel_meshes(w):
        if m != w.viewmodel.arms_mesh_visible:
            gun_meshes.append(m)
    var arms := _raster_instances([w.viewmodel.arms_mesh_visible], cam, GW, GH)
    var gun := _raster_instances(gun_meshes, cam, GW, GH)
    var total := float(GW * GH)
    # Franjas laterales inferiores: es donde aterrizan los hombros cuando el
    # brazo no llega y el rig se ve obligado a entrar en el encuadre.
    var corners := 0
    var corner_hits := 0
    for gy in range(GH):
        for gx in range(GW):
            if gy < GH / 2 or (gx >= GW / 4 and gx < GW - GW / 4):
                continue
            corners += 1
            if arms["mask"][gy * GW + gx]:
                corner_hits += 1
    print("SILUETA ", label,
        " brazos=", snappedf(arms["hits"] / total * 100.0, 0.1), "%",
        " arma=", snappedf(gun["hits"] / total * 100.0, 0.1), "%",
        " laterales_inferiores=", snappedf(corner_hits / float(maxi(corners, 1)) * 100.0, 0.1), "%",
        " verts_brazos_detras_camara=", arms["behind"], "/", arms["onscreen"] + arms["behind"])


## Rasteriza las mallas dadas sobre una rejilla GW x GH en espacio de pantalla.
##
## La proyeccion se calcula a mano con aspect 16:9 FIJO en vez de usar
## `unproject_position`: en headless el viewport es de 64x64 (aspect 1:1) y con
## esa relacion de aspecto los hombros caen fuera del encuadre cuando en el
## juego real (1920x1080) entran de lleno. La medida tiene que describir la
## pantalla del juego, no la ventana dummy del test.
func _raster_instances(meshes: Array, cam: Camera3D, gw: int, gh: int) -> Dictionary:
    const ASPECT := 16.0 / 9.0
    var mask := []
    mask.resize(gw * gh)
    mask.fill(false)
    var hits := 0
    var behind := 0
    var onscreen := 0
    var half_h_scale := tan(deg_to_rad(cam.fov) * 0.5)
    var origin: Vector3 = cam.global_transform.origin
    var fwd: Vector3 = -cam.global_transform.basis.z
    var right: Vector3 = cam.global_transform.basis.x
    var up: Vector3 = cam.global_transform.basis.y
    for m: MeshInstance3D in meshes:
        if m == null or not is_instance_valid(m) or not m.visible or m.mesh == null:
            continue
        # _skinned_verts devuelve en espacio del esqueleto: la piel se aplica
        # como skeleton.global * (pose * rest^-1) * v, asi que falta ese paso.
        # Las mallas RIGIDAS (la OWK) no tienen huesos y su sitio es su propio
        # transform global.
        var skel_xf: Transform3D = _player.weapon.viewmodel.arms_skeleton.global_transform
        var local: PackedVector3Array = _skinned_verts(m, _player.weapon.viewmodel.arms_skeleton, m)
        var world := PackedVector3Array()
        if local.is_empty():
            var xf: Transform3D = m.global_transform
            for si in range(m.mesh.get_surface_count()):
                var ra: Array = m.mesh.surface_get_arrays(si)
                if ra.is_empty() or ra[Mesh.ARRAY_VERTEX] == null:
                    continue
                for v in (ra[Mesh.ARRAY_VERTEX] as PackedVector3Array):
                    world.append(xf * v)
        else:
            world.resize(local.size())
            for i in range(local.size()):
                world[i] = skel_xf * local[i]
        if world.is_empty():
            continue
        var pts := PackedVector2Array()
        var depth := PackedFloat32Array()
        pts.resize(world.size())
        depth.resize(world.size())
        for i in range(world.size()):
            var rel: Vector3 = world[i] - origin
            var d: float = rel.dot(fwd)
            depth[i] = d
            if d <= cam.near:
                behind += 1
                pts[i] = Vector2(NAN, NAN)
                continue
            onscreen += 1
            var half_h: float = d * half_h_scale
            var half_w: float = half_h * ASPECT
            pts[i] = Vector2((0.5 + 0.5 * rel.dot(right) / half_w) * gw,
                (0.5 - 0.5 * rel.dot(up) / half_h) * gh)
        for si in range(m.mesh.get_surface_count()):
            var arrays: Array = m.mesh.surface_get_arrays(si)
            if arrays.is_empty():
                continue
            if arrays[Mesh.ARRAY_INDEX] == null:
                continue
            var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            var t := 0
            while t + 2 < idx.size():
                _fill_tri(mask, gw, gh, Vector2(gw, gh), pts, depth, cam.near,
                    idx[t], idx[t + 1], idx[t + 2])
                t += 3
    for c in mask:
        if c:
            hits += 1
    return {"mask": mask, "hits": hits, "behind": behind, "onscreen": onscreen}


func _fill_tri(mask: Array, gw: int, gh: int, vp: Vector2, pts: PackedVector2Array,
        depth: PackedFloat32Array, near: float, a: int, b: int, c: int) -> void:
    if a >= pts.size() or b >= pts.size() or c >= pts.size():
        return
    # Un triángulo que cruza el plano cercano no existe en la imagen, y uno con
    # un vertice pegado a el se proyecta a coordenadas enormes: en los dos casos
    # lo correcto es descartarlo, no dejar que su caja llene la rejilla.
    if depth[a] <= near or depth[b] <= near or depth[c] <= near:
        return
    var pa: Vector2 = pts[a]
    var pb: Vector2 = pts[b]
    var pc: Vector2 = pts[c]
    if not (is_finite(pa.x) and is_finite(pa.y) and is_finite(pb.x) and is_finite(pb.y)
            and is_finite(pc.x) and is_finite(pc.y)):
        return
    # Un triangulo mucho mas grande que la rejilla es casi siempre un poligono
    # que roza la camara: se recorta al encuadre antes de rasterizar.
    var lim := 40.0
    if (absf(pa.x) > gw * lim and absf(pb.x) > gw * lim and absf(pc.x) > gw * lim):
        return
    var sx := vp.x / float(gw)
    var sy := vp.y / float(gh)
    var minx := maxi(int(floor(minf(pa.x, minf(pb.x, pc.x)) / sx)), 0)
    var maxx := mini(int(ceil(maxf(pa.x, maxf(pb.x, pc.x)) / sx)), gw - 1)
    var miny := maxi(int(floor(minf(pa.y, minf(pb.y, pc.y)) / sy)), 0)
    var maxy := mini(int(ceil(maxf(pa.y, maxf(pb.y, pc.y)) / sy)), gh - 1)
    if maxx < minx or maxy < miny:
        return
    if absf((pb - pa).cross(pc - pa)) < 0.0001:
        return
    for gy in range(miny, maxy + 1):
        for gx in range(minx, maxx + 1):
            var p := Vector2((gx + 0.5) * sx, (gy + 0.5) * sy)
            var w0 := (pb - pa).cross(p - pa)
            var w1 := (pc - pb).cross(p - pb)
            var w2 := (pa - pc).cross(p - pc)
            if (w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0) or (w0 <= 0.0 and w1 <= 0.0 and w2 <= 0.0):
                mask[gy * gw + gx] = true


func _print_arm_frame(label: String) -> void:
    var w = _player.weapon
    var sk: Skeleton3D = w.viewmodel.arms_skeleton
    var cam: Camera3D = _player.camera
    if sk == null:
        print("ARM ", label, " sin esqueleto de brazos")
        return
    var vp := get_viewport().get_visible_rect().size
    var cam_t: Transform3D = cam.global_transform
    print("ARM_FRAME ", label, " viewport=", vp)
    for prefix in ARM_BONES:
        var idx := -1
        for b in range(sk.get_bone_count()):
            if sk.get_bone_name(b).begins_with(prefix):
                idx = b
                break
        if idx < 0:
            continue
        var world: Vector3 = sk.global_transform * sk.get_bone_global_pose(idx).origin
        # Distancia a lo largo del eje de vision: negativa = delante de la camara.
        var depth: float = (world - cam_t.origin).dot(-cam_t.basis.z)
        var side: float = (world - cam_t.origin).dot(cam_t.basis.x)
        var up: float = (world - cam_t.origin).dot(cam_t.basis.y)
        var screen := cam.unproject_position(world)
        var margin := minf(minf(screen.x, vp.x - screen.x), minf(screen.y, vp.y - screen.y))
        print("ARM ", label, " ", prefix, " #", idx, " depth=", snappedf(depth, 0.001),
            " side=", snappedf(side, 0.001), " up=", snappedf(up, 0.001),
            " px=(", snappedf(screen.x, 1.0), ",", snappedf(screen.y, 1.0), ")",
            " margen=", snappedf(margin, 1.0),
            " ", ("DETRAS" if depth <= 0.0 else ("DENTRO" if margin > 0.0 else "FUERA")))
    _print_bore(label)
    _print_bone_axes(label)


## Direccion real de la boca del arma respecto al eje de vision, y donde cae el
## extremo de cada punta en pantalla. Es lo que decide si el arma "apunta hacia
## arriba" o hacia abajo: la perspectiva sola enganya, porque el extremo lejano
## sube hacia el horizonte aunque el arma este inclinada hacia el suelo.
func _print_bore(label: String) -> void:
    var w = _player.weapon
    if w.viewmodel.muzzle == null or w.viewmodel.sight_marker == null:
        return
    var cam: Camera3D = _player.camera
    var world_muzzle: Vector3 = (w.viewmodel.muzzle as Node3D).global_transform.origin
    var world_sight: Vector3 = (w.viewmodel.sight_marker as Node3D).global_transform.origin
    var dir := (world_muzzle - world_sight)
    if dir.length() < 0.0001:
        return
    dir = dir.normalized()
    var en_cam: Vector3 = cam.global_transform.basis.inverse() * dir
    var elevacion := rad_to_deg(asin(clampf(en_cam.y, -1.0, 1.0)))
    var y_mira := cam.unproject_position(world_sight).y
    var y_boca := cam.unproject_position(world_muzzle).y
    print("BORE ", label, " elevacion=", snappedf(elevacion, 0.1), " grados (positivo=arriba)",
        " profundidad_boca=", snappedf((world_muzzle - cam.global_transform.origin).dot(-cam.global_transform.basis.z), 0.001),
        " px_y_mira=", snappedf(y_mira, 1.0), " px_y_boca=", snappedf(y_boca, 1.0),
        " ", ("BOCA_ARRIBA" if y_boca < y_mira else "BOCA_ABAJO"))


## Caja en pantalla de cada malla de los brazos: dice si la masa grande (hombro)
## asoma por algun borde, que es lo que se ve como "sale el hombro".
func _print_arm_screen_box(label: String) -> void:
    var w = _player.weapon
    if w.viewmodel.arms_root == null:
        return
    var cam: Camera3D = _player.camera
    var stack: Array = [w.viewmodel.arms_root]
    var vp := get_viewport().get_visible_rect().size
    while not stack.is_empty():
        var n = stack.pop_back()
        if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh != null:
            var mi := n as MeshInstance3D
            var box := common.screen_bbox(_bind_aabb(mi), mi.global_transform, cam)
            var smin: Vector2 = box["min"]
            var smax: Vector2 = box["max"]
            var dentro := smax.x > 0.0 and smax.y > 0.0 and smin.x < vp.x and smin.y < vp.y
            print("ARM_BOX ", label, " ", mi.name, " px_min=(", snappedf(smin.x, 1.0), ",", snappedf(smin.y, 1.0),
                ") px_max=(", snappedf(smax.x, 1.0), ",", snappedf(smax.y, 1.0), ")",
                " ", ("TOCA_ENCUADRE" if dentro else "FUERA_ENCUADRE"))
        for c in n.get_children():
            stack.append(c)


## Orientacion real del arma leida de los HUESOS del rig (no de los marcadores,
## que en el paquete coherente caen lejos de la pistola visible). `Rif` es el
## hueso del arma y `Pmag` el del cargador: el cargador entra hacia ARRIBA en la
## empuñadura, asi que su eje es la vertical del arma, y la boca es
## perpendicular a esa vertical. Los tres ejes se dan en espacio de CAMARA
## (x=derecha, y=arriba, z=hacia atras), que es donde "apunta arriba o abajo"
## tiene sentido.
func _print_bone_axes(label: String) -> void:
    var w = _player.weapon
    var sk: Skeleton3D = w.viewmodel.arms_skeleton
    if sk == null:
        return
    var cam: Camera3D = _player.camera
    var inv_cam := cam.global_transform.basis.inverse()
    for bone_name in ["Rif", "Pmag"]:
        var idx := -1
        for b in range(sk.get_bone_count()):
            if sk.get_bone_name(b).begins_with(bone_name):
                idx = b
                break
        if idx < 0:
            continue
        var world_b: Basis = sk.global_transform.basis * sk.get_bone_global_pose(idx).basis
        var cb: Basis = inv_cam * world_b
        print("BONE_AXES ", label, " ", bone_name,
            " x=", cb.x.snapped(Vector3(0.001, 0.001, 0.001)),
            " y=", cb.y.snapped(Vector3(0.001, 0.001, 0.001)),
            " z=", cb.z.snapped(Vector3(0.001, 0.001, 0.001)))


## Vértices de una malla ESQUELETIZADA en la pose viva, en el espacio del nodo
## indicado. Para una malla con piel, `mesh.surface_get_arrays()[VERTEX]` está en
## el espacio de BIND: transformarlos por la cadena del nodo da la pose de
## reposo, no la que se ve. La deformación real es
##   p = suma_i  w_i * (pose_i * rest_i^-1) * v
## y es la única forma de saber dónde está de verdad la pistola que el autor
## esculpió dentro del rig de los brazos.
func _skinned_verts(mi: MeshInstance3D, sk: Skeleton3D, space: Node3D) -> PackedVector3Array:
    var out := PackedVector3Array()
    var inv_rest: Array = []
    for b in range(sk.get_bone_count()):
        inv_rest.append(sk.get_bone_global_rest(b).affine_inverse())
    for si in range(mi.mesh.get_surface_count()):
        var arrays := mi.mesh.surface_get_arrays(si)
        if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
            continue
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
            continue
        var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
        var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
        for i in range(verts.size()):
            var v: Vector3 = verts[i]
            if bones.size() < (i + 1) * 4:
                out.append(v)
                continue
            var acc := Vector3.ZERO
            var total := 0.0
            for k in range(4):
                var w := weights[i * 4 + k]
                if w <= 0.0:
                    continue
                var b := bones[i * 4 + k]
                acc += w * ((sk.get_bone_global_pose(b) * inv_rest[b]) * v)
                total += w
            if total > 0.0:
                out.append(acc / total)
            else:
                out.append(v)
    return out


## ---------------------------------------------------------------------------
## Geometria del rig: piel, miras y muñeca (--gundiag)
## ---------------------------------------------------------------------------
func run_gundiag() -> void:
    await get_tree().create_timer(0.8).timeout
    var w = _player.weapon
    var sk: Skeleton3D = w.viewmodel.arms_skeleton
    if sk == null or w.viewmodel.arms_root == null:
        print("GUNDIAG sin esqueleto")
        get_tree().quit(1)
        return
    print("GUNDIAG huesos=", sk.get_bone_count(),
        " anims=", w.viewmodel.arms_player.get_animation_list() if w.viewmodel.arms_player != null else [])
    if w.viewmodel.arms_player != null:
        for an in w.viewmodel.arms_player.get_animation_list():
            var a: Animation = w.viewmodel.arms_player.get_animation(an)
            print("GUNDIAG anim=", an, " dur=", snappedf(a.length, 0.001),
                "s pistas=", a.get_track_count())
        var af: Animation = w.viewmodel.arms_player.get_animation(w.viewmodel.arms_player.get_animation_list()[1])
        for ti in range(af.get_track_count()):
            var tp := str(af.track_get_path(ti))
            if "lidder" in tp or "rigger" in tp or "agazine" in tp or "eapon" in tp or "arrel" in tp or "ullet" in tp:
                print("GUNDIAG pista Fire ", ti, " ", tp)
    _gundiag_mount(w)
    for pose in ["hip", "ads"]:
        w.set_aim(pose == "ads")
        await common.settle_pose()
        if w.viewmodel.arms_player != null:
            w.viewmodel.arms_player.play(w.viewmodel.resolve_idle())
            w.viewmodel.arms_player.seek(0.0, true)
        await get_tree().process_frame
        await get_tree().process_frame
        _gundiag_bones(w, pose)
        _gundiag_skin(w, pose)
        _gundiag_sight(w, pose)
    w.set_aim(false)
    await common.settle_pose()
    _gundiag_idle_drift(w)
    _gundiag_wrist(w)
    print("GUNDIAG_DONE")
    get_tree().quit()


func _gun_bone(w, bone_name: String) -> int:
    var sk: Skeleton3D = w.viewmodel.arms_skeleton
    for b in range(sk.get_bone_count()):
        if sk.get_bone_name(b) == bone_name:
            return b
    return -1


## Cómo está montado el conjunto bajo la cámara: escala y giro totales.
func _gundiag_mount(w) -> void:
    var m: Transform3D = (w.viewmodel.arms_mount as Node3D).transform
    var s := m.basis.get_scale()
    var e := m.basis.get_rotation_quaternion().get_euler()
    print("GUNDIAG montaje escala=", s.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " rot_deg=", (e * 180.0 / PI).snapped(Vector3(0.1, 0.1, 0.1)),
        " pos=", m.origin.snapped(Vector3(0.0001, 0.0001, 0.0001)))


## Ejes de los huesos del arma en espacio de CÁMARA (x=derecha, y=arriba,
## z=hacia atrás): aquí "corredera vertical" y "cañón al frente" se leen
## sin ambigüedad.
func _gundiag_bones(w, label: String) -> void:
    var sk: Skeleton3D = w.viewmodel.arms_skeleton
    var cam: Camera3D = _player.camera
    var inv_cam := cam.global_transform.basis.inverse()
    for bn in GUNDIAG_GUN_BONES:
        var idx := _gun_bone(w, bn)
        if idx < 0:
            print("GUNDIAG hueso ", bn, " AUSENTE")
            continue
        var world_b: Basis = sk.global_transform.basis * sk.get_bone_global_pose(idx).basis
        var cb: Basis = inv_cam * world_b
        var org: Vector3 = sk.global_transform * sk.get_bone_global_pose(idx).origin
        var rel: Vector3 = cam.global_transform.affine_inverse() * org
        print("GUNDIAG hueso ", label, " ", bn,
            " x=", cb.x.snapped(Vector3(0.001, 0.001, 0.001)),
            " y=", cb.y.snapped(Vector3(0.001, 0.001, 0.001)),
            " z=", cb.z.snapped(Vector3(0.001, 0.001, 0.001)),
            " pos_cam=", rel.snapped(Vector3(0.001, 0.001, 0.001)))


## AABB de piel por familia de malla, en espacio del ESQUELETO (misma pose,
## misma escala, mismos transforms): la única comparación de tamaños honesta.
func _gundiag_skin(w, label: String) -> void:
    var sk: Skeleton3D = w.viewmodel.arms_skeleton
    var fams := {"arma": [], "manos": [], "antebrazos": []}
    var stack: Array = [w.viewmodel.arms_root]
    while not stack.is_empty():
        var n = stack.pop_back()
        if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh != null:
            var key := ""
            if n.name in ["Object_938", "Object_939", "Object_940"]:
                key = "arma"
            elif n.name == "Object_8":
                key = "manos"
            elif n.name == "Object_7":
                key = "antebrazos"
            if key != "":
                fams[key].append(n)
        for c in n.get_children():
            stack.append(c)
    for key in ["arma", "manos", "antebrazos"]:
        var pts := PackedVector3Array()
        for m in fams[key]:
            pts.append_array(_skinned_verts(m, sk, w.viewmodel.arms_root))
        # _skinned_verts devuelve en espacio del esqueleto: es el marco común.
        var box := common.bounds_of(pts)
        print("GUNDIAG piel ", label, " ", key, " verts=", pts.size(),
            " tam=", box.size.snapped(Vector3(0.001, 0.001, 0.001)),
            " ancho_mm=", snappedf(box.size.x * 1000.0, 0.1))
    # El cociente que importa, medido en el mismo marco:
    var pa := PackedVector3Array()
    var pm := PackedVector3Array()
    for m in fams["arma"]:
        pa.append_array(_skinned_verts(m, sk, w.viewmodel.arms_root))
    for m in fams["manos"]:
        pm.append_array(_skinned_verts(m, sk, w.viewmodel.arms_root))
    if not pa.is_empty() and not pm.is_empty():
        var ba := common.bounds_of(pa)
        var bm := common.bounds_of(pm)
        print("GUNDIAG cociente manos/arma ancho=",
            snappedf(bm.size.x / maxf(ba.size.x, 0.0001), 0.01), "x",
            " (mismo espacio, misma pose)")


## Línea de mira real (hueso corredera + puntos offline) frente al eje óptico:
## desvío en mm/mrad y canto de la corredera. Es lo que el ADS debe anular.
func _gundiag_sight(w, label: String) -> void:
    var sk: Skeleton3D = w.viewmodel.arms_skeleton
    var cam: Camera3D = _player.camera
    var idx := _gun_bone(w, "Slidder_919")
    if idx < 0:
        return
    var slide_xf: Transform3D = sk.global_transform * sk.get_bone_global_pose(idx)
    var rear: Vector3 = slide_xf * GUNDIAG_REAR
    var front: Vector3 = slide_xf * GUNDIAG_FRONT
    var muzzle: Vector3 = slide_xf * GUNDIAG_MUZZLE_SLIDE
    var eye: Vector3 = cam.global_position
    var fwd: Vector3 = -cam.global_transform.basis.z.normalized()
    for entry in [["trasera", rear], ["delantera", front]]:
        var to: Vector3 = (entry[1] as Vector3) - eye
        var mrad: float = acos(clampf(to.normalized().dot(fwd), -1.0, 1.0)) * 1000.0
        var mm: float = tan(mrad * 0.001) * to.length() * 1000.0
        print("GUNDIAG mira ", label, " ", entry[0], " desvio_mm=", snappedf(mm, 0.1),
            " mrad=", snappedf(mrad, 0.01), " dist_ojo=", snappedf(to.length(), 0.003))
    var bore: Vector3 = (muzzle - rear).normalized()
    var en_cam: Vector3 = cam.global_transform.basis.inverse() * bore
    var elev := rad_to_deg(asin(clampf(en_cam.y, -1.0, 1.0)))
    # Canto: eje X de la corredera (su anchura) contra la horizontal de cámara.
    var slide_x: Vector3 = (cam.global_transform.basis.inverse()
        * (sk.global_transform.basis * sk.get_bone_global_pose(idx).basis).x).normalized()
    var cant := rad_to_deg(asin(clampf(slide_x.y, -1.0, 1.0)))
    print("GUNDIAG linea ", label, " elevacion_bore=", snappedf(elev, 0.1),
        " canto_corredera=", snappedf(cant, 0.1),
        " boca_delante=", snappedf((muzzle - eye).dot(fwd), 0.003))


## Cuánto se mueve el alza trasera a lo largo del Idle (4.167 s): si la deriva
## supera el criterio del aimtest, la pose de ADS no puede resolverse en un
## instante y olvidarse; hay que saberlo antes de prometer 6 mm.
func _gundiag_idle_drift(w) -> void:
    var sk: Skeleton3D = w.viewmodel.arms_skeleton
    var idx := _gun_bone(w, "Slidder_919")
    if idx < 0 or w.viewmodel.arms_player == null:
        return
    w.viewmodel.arms_player.play(w.viewmodel.resolve_idle())
    var pts: Array[Vector3] = []
    for t in [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]:
        w.viewmodel.arms_player.seek(t, true)
        sk.force_update_all_bone_transforms()
        pts.append(sk.global_transform * sk.get_bone_global_pose(idx).origin)
    var diam := 0.0
    for a in pts:
        for b in pts:
            diam = maxf(diam, a.distance_to(b))
    print("GUNDIAG deriva_idle hueso_corredera diametro=",
        snappedf(diam * 1000.0, 0.1), "mm muestras=", pts.size())


## Dónde está la muñeca que sostiene el arma, en espacio de recoil_node: es el
## punto físicamente razonable para el pivote del retroceso procedural.
func _gundiag_wrist(w) -> void:
    var sk: Skeleton3D = w.viewmodel.arms_skeleton
    var inv: Transform3D = (w.viewmodel.recoil_node as Node3D).global_transform.affine_inverse()
    for bn in ["DEF-hand.R_842", "hand_ik.R_871", "DEF-forearm.R_844", "Weapon_922"]:
        var idx := _gun_bone(w, bn)
        if idx < 0:
            print("GUNDIAG muneca ", bn, " AUSENTE")
            continue
        var p: Vector3 = inv * (sk.global_transform * sk.get_bone_global_pose(idx).origin)
        print("GUNDIAG muneca ", bn, " en_recoil=",
            p.snapped(Vector3(0.0001, 0.0001, 0.0001)))
