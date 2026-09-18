extends Node3D

## Proyectiles, penetracion y rebote. NO decide presentacion: para cada impacto
## dice DONDE y CONTRA QUE (ImpactFX lo dibuja, GameAudio lo suena) y para cada
## cuerpo fisico que golpea deja el impulso en Jolt.
##
##   material + geometria -> resistencia -> velocidad de salida
##
## La geometria la da la forma de colision: una caja se recorre de cara a cara,
## un cilindro de pared a pared, una esfera de lado a lado. Un cuerpo FINO (una
## lata) declara `thin_shell` + `wall_thickness`: la bala atraviesa DOS paredes
## delgadas, no el volumen entero (el aire de dentro no frena nada).

const PROJECTILE_MASS := 0.00745   # 115 gr, la punta de una 9x19 de Glock 19
const DRAG_K := 0.00142
const GRAVITY := 9.81
const MAX_DISTANCE := 520.0
const COLLISION_MASK := 1
const PENETRATION_EPSILON := 0.0015
const PENETRATION_SEARCH_DISTANCE := 4.0
## Velocidad mínima para EMERGER con carácter de proyectil y no de gravilla.
## CALIBRADO: por debajo, la bala se queda dentro del material.
const EXIT_SPEED_MIN := 75.0
## Fraccion del momento del proyectil que se lleva un cuerpo sin script propio
## (una lata). Una bala que atraviesa una lata no le entrega todo su momento.
const IMPULSE_TRANSFER := 0.20

var bullets: Array = []


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE


func fire(origin: Vector3, direction: Vector3, speed: float = 372.0) -> void:
    var dir := direction.normalized()
    var b := {
        "active": true,
        "pos": origin + dir * 0.055,
        "vel": dir * speed,
        "life": 0.0,
        "distance": 0.0,
        "penetrations": 0,
        "ricochets": 0,
        "flyby": false,
    }
    bullets.append(b)


func _physics_process(delta: float) -> void:
    if bullets.is_empty():
        return
    var space := get_world_3d().direct_space_state
    for i in range(bullets.size() - 1, -1, -1):
        var b: Dictionary = bullets[i]
        if not b.active:
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
    var penetrable := false
    var penetration_resistance := 0.0
    var thin_shell := false
    var wall_thickness := 0.0
    if collider is Node:
        surface = str(collider.get_meta("surface", "concrete"))
        penetrable = bool(collider.get_meta("penetrable", false))
        penetration_resistance = float(collider.get_meta("penetration_resistance", 0.0))
        thin_shell = bool(collider.get_meta("thin_shell", false))
        wall_thickness = float(collider.get_meta("wall_thickness", 0.0))

    var energy: float = 0.5 * PROJECTILE_MASS * speed * speed
    ImpactFX.spawn_impact(point, normal, collider, surface, false)
    _push_body(collider, point, dir, energy, speed)

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
        var geometric_thickness: float = exit["distance"]
        if geometric_thickness <= PENETRATION_EPSILON:
            b.active = false
            return

        # Grosor BALISTICO: en un cuerpo macizo es la cuerda que recorre la bala;
        # en una cascara fina (una lata) son sus DOS paredes, no el hueco de aire
        # de dentro.
        var thickness := geometric_thickness
        if thin_shell:
            if wall_thickness <= 0.0:
                b.active = false
                return
            thickness = 2.0 * wall_thickness

        # La resistencia es material; el espesor recorrido viene de la
        # geometría. La pérdida, por tanto, cambia de forma continua si el
        # panel se rota o el tiro entra oblicuo. La decisión de perforar o
        # quedarse dentro se toma ANTES de dibujar la salida: un proyectil que
        # no conserva energía al salir no tiene salida visible.
        var retained_energy := exp(-penetration_resistance * thickness)
        var exit_speed := speed * sqrt(retained_energy)
        if exit_speed < EXIT_SPEED_MIN:
            # Se queda dentro: no hay cara de salida que representar.
            b.active = false
            return

        ImpactFX.spawn_impact(exit_point, exit_normal, collider, surface, true)
        b.vel *= sqrt(retained_energy)
        # Dejamos sólo una separación numérica de la cara de salida: la próxima
        # colisión debe ser con la geometría que haya detrás, no con el mismo
        # panel por redondeo del raycast.
        b.pos = exit_point + dir * PENETRATION_EPSILON
        b.distance += geometric_thickness + PENETRATION_EPSILON
        b.penetrations += 1
        if b.penetrations > 4:
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


## Deja el golpe en el cuerpo fisico. Los cuerpos con script propio (caja, blanco)
## lo reciben con sus reglas; los demas (una lata) reciben en Jolt el momento que
## el proyectil les cede al atravesarlos.
func _push_body(collider: Object, point: Vector3, dir: Vector3, energy: float, speed: float) -> void:
    if not collider is Node:
        return
    if collider.has_method("take_bullet_hit"):
        collider.call("take_bullet_hit", point, dir.normalized(), speed, energy, dir)
        return
    if collider is RigidBody3D:
        var body := collider as RigidBody3D
        body.apply_impulse(dir * (IMPULSE_TRANSFER * PROJECTILE_MASS * speed), point - body.global_position)


## Busca la cara de salida en la geometria de la forma de colision. Cada forma se
## transforma al espacio local y se resuelve la salida real; no se usa grosor de
## metadata para fabricar un punto.
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
            var hit := _exit_of_shape(shape, shape_transform, entry, direction)
            if hit.is_empty():
                continue
            var distance: float = hit["distance"]
            if distance <= PENETRATION_EPSILON or distance >= best_distance:
                continue
            best = hit
            best_distance = distance
    return best


func _exit_of_shape(shape: Shape3D, shape_transform: Transform3D, entry: Vector3, direction: Vector3) -> Dictionary:
    var inv := shape_transform.affine_inverse()
    var local_entry := inv * entry
    var local_direction := (inv * (entry + direction)) - local_entry
    if shape is BoxShape3D:
        return _exit_box(shape as BoxShape3D, shape_transform, entry, local_entry, local_direction)
    if shape is CylinderShape3D:
        return _exit_cylinder(shape as CylinderShape3D, shape_transform, entry, local_entry, local_direction)
    if shape is SphereShape3D:
        return _exit_sphere(shape as SphereShape3D, shape_transform, entry, local_entry, local_direction)
    # Otra forma (capsula, convexa): sin salida analitica no se inventa.
    return {}


func _exit_point(shape_transform: Transform3D, entry: Vector3, local_entry: Vector3,
        local_direction: Vector3, t: float, local_normal: Vector3) -> Dictionary:
    if t <= 0.0:
        return {}
    var world_exit: Vector3 = shape_transform * (local_entry + local_direction * t)
    return {
        "point": world_exit,
        "normal": (shape_transform.basis * local_normal).normalized(),
        "distance": entry.distance_to(world_exit),
    }


func _exit_box(box: BoxShape3D, shape_transform: Transform3D, entry: Vector3,
        local_entry: Vector3, local_direction: Vector3) -> Dictionary:
    var half := box.size * 0.5
    var t_near := -INF
    var t_far := INF
    for axis in 3:
        var origin_axis := local_entry[axis]
        var direction_axis := local_direction[axis]
        if absf(direction_axis) < 0.000001:
            if absf(origin_axis) > half[axis] + PENETRATION_EPSILON:
                return {}
            continue
        var t1 := (-half[axis] - origin_axis) / direction_axis
        var t2 := (half[axis] - origin_axis) / direction_axis
        t_near = maxf(t_near, minf(t1, t2))
        t_far = minf(t_far, maxf(t1, t2))
    if t_far <= PENETRATION_EPSILON or t_near > PENETRATION_EPSILON * 4.0:
        return {}
    var local_exit := local_entry + local_direction * t_far
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
    return _exit_point(shape_transform, entry, local_entry, local_direction, t_far, local_normal)


func _exit_cylinder(cyl: CylinderShape3D, shape_transform: Transform3D, entry: Vector3,
        local_entry: Vector3, local_direction: Vector3) -> Dictionary:
    var radius := cyl.radius
    var half_h := cyl.height * 0.5
    var epsilon := 0.000001
    var best_t := -INF
    var best_normal := Vector3.ZERO
    # Pared lateral: cilindro infinito en Y, recortado por las tapas.
    var a := local_direction.x * local_direction.x + local_direction.z * local_direction.z
    if a > epsilon:
        var b := 2.0 * (local_entry.x * local_direction.x + local_entry.z * local_direction.z)
        var c := local_entry.x * local_entry.x + local_entry.z * local_entry.z - radius * radius
        var disc := b * b - 4.0 * a * c
        if disc >= 0.0:
            var sq := sqrt(disc)
            var candidates: Array[float] = [(-b - sq) / (2.0 * a), (-b + sq) / (2.0 * a)]
            for t: float in candidates:
                var y := local_entry.y + local_direction.y * t
                if absf(y) <= half_h + epsilon and t > best_t:
                    best_t = t
                    best_normal = Vector3(
                        local_entry.x + local_direction.x * t, 0.0,
                        local_entry.z + local_direction.z * t).normalized()
    # Tapas.
    if absf(local_direction.y) > epsilon:
        for sign_y: float in [1.0, -1.0]:
            var t := (sign_y * half_h - local_entry.y) / local_direction.y
            var px := local_entry.x + local_direction.x * t
            var pz := local_entry.z + local_direction.z * t
            if px * px + pz * pz <= radius * radius + epsilon and t > best_t:
                best_t = t
                best_normal = Vector3(0.0, sign_y, 0.0)
    return _exit_point(shape_transform, entry, local_entry, local_direction, best_t, best_normal)


func _exit_sphere(sphere: SphereShape3D, shape_transform: Transform3D, entry: Vector3,
        local_entry: Vector3, local_direction: Vector3) -> Dictionary:
    var a := local_direction.dot(local_direction)
    if a < 0.0000000001:
        return {}
    var b := 2.0 * local_entry.dot(local_direction)
    var c := local_entry.dot(local_entry) - sphere.radius * sphere.radius
    var disc := b * b - 4.0 * a * c
    if disc < 0.0:
        return {}
    var t := (-b + sqrt(disc)) / (2.0 * a)
    return _exit_point(shape_transform, entry, local_entry, local_direction, t,
        (local_entry + local_direction * t).normalized())


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
