extends Node3D

signal target_hit(zone: String)

const PROJECTILE_MASS := 0.008
const DRAG_K := 0.00142
const GRAVITY := 9.81
const MAX_DISTANCE := 520.0
const COLLISION_MASK := 1
const PENETRATION_EPSILON := 0.0015
const PENETRATION_SEARCH_DISTANCE := 4.0

var bullets: Array = []
var tracer_pool: Array[MeshInstance3D] = []
var tracer_material: StandardMaterial3D
var penetration_events := 0


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE
    tracer_material = StandardMaterial3D.new()
    tracer_material.albedo_color = Color(1.0, 0.55, 0.16, 0.95)
    tracer_material.emission_enabled = true
    tracer_material.emission = Color(1.0, 0.5, 0.1)
    tracer_material.emission_energy_multiplier = 4.0
    tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    tracer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func fire(origin: Vector3, direction: Vector3, speed: float = 372.0, tracer_chance: float = 0.42) -> void:
    var dir := direction.normalized()
    var mesh: MeshInstance3D = null
    if randf() < tracer_chance:
        mesh = _take_tracer()
        mesh.visible = true
    var b := {
        "active": true,
        "mesh": mesh,
        "pos": origin + dir * 0.055,
        "vel": dir * speed,
        "life": 0.0,
        "distance": 0.0,
        "penetrations": 0,
        "ricochets": 0,
        "flyby": false,
    }
    bullets.append(b)
    if mesh != null:
        _sync_mesh(b)


func _physics_process(delta: float) -> void:
    if bullets.is_empty():
        return
    var space := get_world_3d().direct_space_state
    for i in range(bullets.size() - 1, -1, -1):
        var b: Dictionary = bullets[i]
        if not b.active:
            _release_bullet(b)
            bullets.remove_at(i)
            continue

        b.life += delta
        # Silbido de paso: solo cuando la trayectoria cruza el espacio del oido
        # (no por disparar). Se calcula de la recta del proyectil al jugador y
        # suena una sola vez por bala, al pasar el punto mas cercano.
        if not b.flyby and _passes_near_player(b):
            b.flyby = true
            GameAudio.play_3d("bullet_flyby", _closest_point(b), -4.0, randf_range(0.94, 1.08))
        var remaining: float = delta
        var iterations := 0
        while b.active and remaining > 0.0001 and iterations < 16:
            iterations += 1
            var speed: float = b.vel.length()
            if speed < 45.0:
                b.active = false
                break
            var step: float = min(remaining, 1.15 / speed)
            _step_bullet(b, step, space)
            remaining -= step

        if b.life > 2.2 or b.distance > MAX_DISTANCE:
            b.active = false
        if b.mesh != null and b.active:
            _sync_mesh(b)


func _step_bullet(b: Dictionary, h: float, space: PhysicsDirectSpaceState3D) -> void:
    var speed: float = b.vel.length()
    var accel: Vector3 = b.vel * (-DRAG_K * speed) + Vector3.DOWN * GRAVITY
    b.vel = b.vel + accel * h
    var delta_pos: Vector3 = b.vel * h
    var dist: float = delta_pos.length()
    if dist < 0.00001:
        return
    var dir: Vector3 = delta_pos / dist
    var query := PhysicsRayQueryParameters3D.create(b.pos, b.pos + delta_pos, COLLISION_MASK)
    query.collide_with_areas = false
    query.collide_with_bodies = true
    query.hit_from_inside = true
    var hit := space.intersect_ray(query)
    if hit.is_empty():
        b.pos = b.pos + delta_pos
        b.distance += dist
        return

    var point: Vector3 = hit.position
    var normal: Vector3 = hit.normal.normalized()
    if normal.length_squared() < 0.5:
        normal = -dir
    var collider: Object = hit.collider
    b.distance += point.distance_to(b.pos)
    var surface := "concrete"
    if collider is Node:
        surface = str(collider.get_meta("surface", "concrete"))

    var energy: float = 0.5 * PROJECTILE_MASS * speed * speed
    ImpactFX.spawn_impact(point, normal, collider, surface, false)

    if collider is Node and collider.has_method("take_bullet_hit"):
        collider.call("take_bullet_hit", point, normal, speed, energy, dir)
        var zone := "TORSO"
        if collider.has_meta("last_hit_zone"):
            zone = str(collider.get_meta("last_hit_zone"))
        target_hit.emit(zone)

    var penetrable := false
    var penetration_resistance := 0.0
    if collider is Node:
        penetrable = bool(collider.get_meta("penetrable", false))
        if penetrable:
            penetration_resistance = float(collider.get_meta("penetration_resistance", 0.0))

    if penetrable:
        if penetration_resistance <= 0.0:
            # Un volumen penetrable sin resistencia calibrada no tiene una
            # propiedad física completa: no inventamos una pérdida ni una
            # salida. La entrada sí ocurrió; el proyectil se detiene aquí.
            push_warning("Penetrable sin penetration_resistance: " + str(collider))
            b.active = false
            return

        var exit := _find_exit_geometry(point, dir, collider)
        if exit.is_empty():
            # Sin segunda cara del mismo volumen no existe una penetración
            # demostrable. Esto evita el antiguo punto de salida fabricado a
            # partir de metadata de grosor.
            b.active = false
            return

        var exit_point: Vector3 = exit["point"]
        var exit_normal: Vector3 = exit["normal"]
        var actual_thickness: float = exit["distance"]
        if actual_thickness <= PENETRATION_EPSILON:
            b.active = false
            return

        ImpactFX.spawn_impact(exit_point, exit_normal, collider, surface, true)
        # La resistencia es material; el espesor recorrido viene de la
        # geometría. La pérdida, por tanto, cambia de forma continua si el
        # panel se rota o el tiro entra oblicuo.
        var retained_energy := exp(-penetration_resistance * actual_thickness)
        b.vel *= clampf(sqrt(retained_energy), 0.05, 0.98)
        # Dejamos sólo una separación numérica de la cara de salida: la próxima
        # colisión debe ser con la geometría que haya detrás, no con el mismo
        # panel por redondeo del raycast.
        b.pos = exit_point + dir * PENETRATION_EPSILON
        b.distance += actual_thickness + PENETRATION_EPSILON
        b.penetrations += 1
        penetration_events += 1
        if b.penetrations > 4 or b.vel.length() < 75.0:
            b.active = false
        return

    var incidence: float = abs(dir.dot(normal))
    if incidence < 0.31 and speed > 110.0 and b.ricochets < 2 and (surface == "metal" or surface == "concrete"):
        if randf() < 0.55:
            var reflected: Vector3 = b.vel - 2.0 * b.vel.dot(normal) * normal
            reflected = reflected.normalized()
            b.vel = reflected * speed * randf_range(0.42, 0.62)
            b.pos = point + reflected * 0.012
            b.ricochets += 1
            GameAudio.play_3d("ricochet", point, 0.0, randf_range(0.9, 1.1))
            return

    b.active = false


## Busca la cara de salida en la geometría de la forma de colisión. Para cada
## BoxShape3D del collider se transforma la trayectoria al espacio local y se
## resuelve el intervalo de intersección de los tres slabs; la cara lejana es
## la salida real. No se usa grosor de metadata para fabricar un punto.
func _find_exit_geometry(entry: Vector3, direction: Vector3, collider: Object) -> Dictionary:
    if not collider is CollisionObject3D:
        return {}
    var body := collider as CollisionObject3D
    var best := {}
    var best_distance := PENETRATION_SEARCH_DISTANCE
    for owner_id in body.get_shape_owners():
        var shape_transform: Transform3D = body.global_transform * body.shape_owner_get_transform(owner_id)
        for shape_index in range(body.shape_owner_get_shape_count(owner_id)):
            var shape := body.shape_owner_get_shape(owner_id, shape_index)
            if not shape is BoxShape3D:
                continue
            var box := shape as BoxShape3D
            var inv := shape_transform.affine_inverse()
            var local_entry := inv * entry
            var local_direction := (inv * (entry + direction)) - local_entry
            var half := box.size * 0.5
            var t_near := -INF
            var t_far := INF
            var valid := true
            for axis in 3:
                var origin_axis := local_entry[axis]
                var direction_axis := local_direction[axis]
                if absf(direction_axis) < 0.000001:
                    if absf(origin_axis) > half[axis] + PENETRATION_EPSILON:
                        valid = false
                        break
                    continue
                var t1 := (-half[axis] - origin_axis) / direction_axis
                var t2 := (half[axis] - origin_axis) / direction_axis
                t_near = maxf(t_near, minf(t1, t2))
                t_far = minf(t_far, maxf(t1, t2))
            if not valid or t_far <= PENETRATION_EPSILON or t_near > PENETRATION_EPSILON * 4.0:
                continue
            var local_exit := local_entry + local_direction * t_far
            var world_exit := shape_transform * local_exit
            var distance := entry.distance_to(world_exit)
            if distance <= PENETRATION_EPSILON or distance >= best_distance:
                continue

            var exit_axis := 0
            var axis_error := absf(absf(local_exit.x) - half.x)
            var y_error := absf(absf(local_exit.y) - half.y)
            var z_error := absf(absf(local_exit.z) - half.z)
            if y_error < axis_error:
                exit_axis = 1
                axis_error = y_error
            if z_error < axis_error:
                exit_axis = 2
            var local_normal := Vector3.ZERO
            local_normal[exit_axis] = 1.0 if local_exit[exit_axis] >= 0.0 else -1.0
            var world_normal := (shape_transform.basis * local_normal).normalized()
            best = {"point": world_exit, "normal": world_normal, "distance": distance}
            best_distance = distance
    return best


## Punto mas cercano de la recta del proyectil a la camara del jugador.
func _closest_point(b: Dictionary) -> Vector3:
    var eye := _listener_position()
    var dir: Vector3 = b.vel.normalized()
    var to_bullet: Vector3 = b.pos - eye
    var along: float = to_bullet.dot(dir)
    return b.pos + dir * maxf(0.0, -along)


## Distancia minima de la trayectoria del proyectil al oido. El radio es amplio
## (1.1 m): el silbido tiene que sentirse cuando la bala pasa cerca, no solo
## cuando roza la cabeza.
func _passes_near_player(b: Dictionary) -> bool:
    var eye := _listener_position()
    var dir: Vector3 = b.vel.normalized()
    var to_bullet: Vector3 = b.pos - eye
    var along: float = to_bullet.dot(dir)
    # Solo si aun no ha pasado el punto mas cercano: el aviso suena en el paso.
    if along > 0.0:
        return false
    var closest: Vector3 = b.pos + dir * (-along)
    return closest.distance_to(eye) < 1.1


func _listener_position() -> Vector3:
    var viewport := get_viewport()
    if viewport != null:
        var cam := viewport.get_camera_3d()
        if cam != null:
            return cam.global_position
    return Vector3.ZERO


func _take_tracer() -> MeshInstance3D:
    if not tracer_pool.is_empty():
        var pooled: MeshInstance3D = tracer_pool.pop_back()
        pooled.visible = true
        return pooled
    var box := BoxMesh.new()
    box.size = Vector3(0.008, 0.008, 0.26)
    box.material = tracer_material
    var mesh := MeshInstance3D.new()
    mesh.mesh = box
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mesh)
    return mesh


func _release_bullet(b: Dictionary) -> void:
    var mesh: MeshInstance3D = b.mesh
    if mesh != null:
        mesh.visible = false
        tracer_pool.append(mesh)
        b.mesh = null


func _sync_mesh(b: Dictionary) -> void:
    var mesh: MeshInstance3D = b.mesh
    if mesh == null:
        return
    mesh.global_position = b.pos
    var dir: Vector3 = b.vel.normalized()
    if dir.length_squared() > 0.1:
        mesh.look_at(b.pos + dir, Vector3.UP)
        mesh.scale = Vector3(1, 1, 0.75 + clamp(b.vel.length() / 330.0, 0.0, 1.4))
