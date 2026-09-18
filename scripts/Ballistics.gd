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

## TABLA UNICA DE MATERIALES BALISTICOS (resistencia por metro).
## Los objetos declaran material + geometria; nadie escribe numeros sueltos.
const MATERIALS := {"pine": 7.0, "gypsum": 27.0, "paper": 1.7, "aluminum": 200.0, "steel": 900.0, "concrete": 55.0}
const PROJECTILE_MASS := 0.00745   # 115 gr, la punta de una 9x19 de Glock 19
const DRAG_K := 0.00142
const GRAVITY := 9.81
const MAX_DISTANCE := 520.0
const COLLISION_MASK := 1
const PENETRATION_EPSILON := 0.0015
## Velocidad mínima para EMERGER con carácter de proyectil y no de gravilla.
## CALIBRADO: por debajo, la bala se queda dentro del material.
const EXIT_SPEED_MIN := 75.0
## El impulso disponible es p_in - p_out: lo que la bala pierde se lo lleva el
## cuerpo. Si se detiene, p_out = 0. Sin factores inventados.

var bullets: Array = []


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE


## CERO EXPLICITO: el anima sale paralela a la linea de miras, sin angulo de
## convergencia. La mira va 8,5 mm sobre el anima (medido en el GLB) y la
## gravedad hace el resto: a 18 m el tiro cae ~20 mm bajo el punto apuntado, a
## 50 m ~10 cm. Como una mira fija sin regular: se apunta al centro y se sabe
## donde pega, no se inventa convergencia.
func fire(origin: Vector3, direction: Vector3, speed: float = 372.0) -> void:
    var dir := direction.normalized()
    var b := {
        "active": true,
        "pos": origin + dir * 0.004,
        "vel": dir * speed,
        "life": 0.0,
        "distance": 0.0,
        "penetrations": 0,
        "ricochets": 0,
        "flyby": false,
        "charged": [],
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
    var collider: Object = hit.collider
    var normal: Vector3 = hit.normal.normalized()
    if normal.length_squared() < 0.5:
        push_error("Colision balistica sin normal valida: " + str(collider))
        b.active = false
        return
    b.distance += point.distance_to(b.pos)
    var surface := ""
    var penetrable := false
    var thin_shell := false
    var wall_thickness := 0.0
    if collider is Node:
        surface = str(collider.get_meta("surface", ""))
        penetrable = bool(collider.get_meta("penetrable", false))
        thin_shell = bool(collider.get_meta("thin_shell", false))
        wall_thickness = float(collider.get_meta("wall_thickness", 0.0))
    var p_in: float = PROJECTILE_MASS * speed
    if not MATERIALS.has(surface):
        push_error("Colision balistica sin material de Ballistics.MATERIALS: " + str(collider))
        _push_body(collider, point, dir, p_in)
        b.active = false
        return
    var penetration_resistance: float = MATERIALS[surface]
    var hit_shape := int(hit.get("shape", -1))
    # Un cuerpo, un cobro: la separacion de salida (1,5 mm) puede caer dentro
    # del slack de contacto de Jolt y el rayo repisa el mismo cuerpo en el
    # subpaso siguiente (medido: 5 cobros en una lata = 4,7x momento). El
    # transito ya se pago en el primer evento; repetirlo crea energia.
    var already_charged := false
    var body_id := 0
    if collider is RigidBody3D:
        body_id = (collider as Node).get_instance_id()
        already_charged = (b.charged as Array).has(body_id)

    if penetrable:
        var exit := _find_exit_geometry(point, dir, collider, hit_shape)
        if exit.is_empty():
            if already_charged:
                # Jolt puede devolver una segunda intersección con el mismo
                # cuerpo dentro del slack numérico de la cara de salida. Ya
                # se cobró el delta-p; sólo salimos del contacto y dejamos que
                # el siguiente paso busque la geometría que haya detrás.
                b.pos = point + dir * PENETRATION_EPSILON
                b.distance += PENETRATION_EPSILON
                return
            if not already_charged:
                ImpactFX.spawn_impact(point, normal, collider, surface, false)
                _push_body(collider, point, dir, p_in)
            b.active = false
            return
        var exit_point: Vector3 = exit["point"]
        var exit_normal: Vector3 = exit["normal"]
        var geometric_thickness: float = exit["distance"]
        if geometric_thickness <= PENETRATION_EPSILON:
            if not already_charged:
                ImpactFX.spawn_impact(point, normal, collider, surface, false)
                _push_body(collider, point, dir, p_in)
            b.active = false
            return
        # Grosor BALISTICO con angulo: macizo = cuerda; cascara fina = 2 paredes
        # corregidas por incidencia (1/cos). Sin angulo se subestima el oblicuo.
        # Medido en :0 con lata de 14 g a 2 m: de frente 4,68 m/s (predice 4,7),
        # rozando el filo (incidencia ~0,7) 6,52 m/s (predice 6,5).
        var incidence_in: float = absf(dir.dot(normal))
        var thickness := geometric_thickness
        if thin_shell:
            if wall_thickness <= 0.0:
                if not already_charged:
                    ImpactFX.spawn_impact(point, normal, collider, surface, false)
                    _push_body(collider, point, dir, p_in)
                b.active = false
                return
            thickness = 2.0 * wall_thickness / maxf(incidence_in, 0.3)
        var retained_energy := exp(-penetration_resistance * thickness)
        var exit_speed := speed * sqrt(retained_energy)
        if exit_speed < EXIT_SPEED_MIN:
            if not already_charged:
                ImpactFX.spawn_impact(point, normal, collider, surface, false)
                if surface == "pine":
                    ImpactFX.spawn_embedded(point, dir, collider)
                _push_body(collider, point, dir, p_in)
            # Chapa fina sin salida: la 9 mm no se queda dentro de 1,2 mm
            # de chapa. O la rompe (arriba) o resbala: SEGURO, sin dado y sin
            # pedir roce extremo (a >47 grados de oblicuidad ya no hay salida
            # posible y clavarse seria la mentira). En macizo el dado sigue:
            # ahi quedarse dentro si es real.
            if _try_ricochet(b, point, normal, surface, speed, true):
                return
            b.active = false
            return
        ImpactFX.spawn_impact(point, normal, collider, surface, false)
        ImpactFX.spawn_impact(exit_point, exit_normal, collider, surface, true)
        if already_charged:
            # Repisada del mismo cuerpo: el transito ya se cobro.
            # Avanza sin cobrar, sin perder energia y sin duplicar decal.
            b.pos = exit_point + dir * PENETRATION_EPSILON
            b.distance += geometric_thickness + PENETRATION_EPSILON
            return
        _push_body(collider, point, dir, p_in - PROJECTILE_MASS * exit_speed)
        if collider is RigidBody3D:
            (b.charged as Array).append(body_id)
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

    ImpactFX.spawn_impact(point, normal, collider, surface, false)
    _push_body(collider, point, dir, p_in)
    if _try_ricochet(b, point, normal, surface, speed):
        return

    b.active = false


## UNICA puerta de rebote: rapido (>110 m/s) sobre superficie dura.
## DETERMINISTA: la misma combinacion velocidad/material/espesor/angulo decide
## siempre lo mismo (penetrar/detenerse/rebotar). El roce (<0,31 de incidencia,
## ~72 grados+) sobre duro siempre resbala; en chapa fina sin salida (`force`)
## resbala siempre: una 9 mm no se queda dentro de 1,2 mm de chapa. Maximo 2
## por bala. La variacion vive en particulas/sonido, no en la decision.
func _try_ricochet(b: Dictionary, point: Vector3, normal: Vector3, surface: String, speed: float, force := false) -> bool:
    # `force` solo llega de chapa fina sin salida: ahi el roce ya es oblicuo
    # por construccion (>47 grados) y la puerta de incidencia sobra.
    var n := normal.normalized()
    var dir: Vector3 = (b.vel as Vector3).normalized()
    if (force or absf(dir.dot(n)) < 0.31) and speed > 110.0 and int(b.ricochets) < 2 \
            and (surface == "steel" or surface == "concrete" or surface == "aluminum"):
        var reflected: Vector3 = b.vel - 2.0 * (b.vel as Vector3).dot(n) * n
        reflected = reflected.normalized()
        # Retencion fija (centro del antiguo 0,42-0,62) + microvariacion
        # DETERMINISTA por punto de impacto (hash de mm): el mismo tiro da lo
        # mismo, otro punto varia un pelo sin dado.
        var h := float(absi(int(point.x * 1000.0) * 374761393 + int(point.y * 1000.0) * 668265263 + int(point.z * 1000.0) * 1274126177) % 1000) / 1000.0
        b.vel = reflected * speed * (0.50 + h * 0.06)
        b.pos = point + reflected * 0.012
        b.ricochets = int(b.ricochets) + 1
        GameAudio.play_3d("ricochet", point, 0.0, randf_range(0.9, 1.1))
        return true
    return false


## UNICA autoridad de momento balistico: delta-p (p_in - p_out) a Jolt.
## Los blancos/cajas solo declaran masa/material/geometria; nada de torques
## aleatorios ni callbacks fantasma (el impulso fuera del centro ya gira solo).
func _push_body(collider: Object, point: Vector3, dir: Vector3, impulse: float) -> void:
    if not collider is RigidBody3D:
        return
    var body := collider as RigidBody3D
    if impulse <= 0.0:
        return
    body.apply_impulse(dir.normalized() * impulse, point - body.global_position)


## Busca la cara de salida en la geometria de la forma de colision. Cada forma se
## transforma al espacio local y se resuelve la salida real; no se usa grosor de
## metadata para fabricar un punto.
func _find_exit_geometry(entry: Vector3, direction: Vector3, collider: Object, hit_shape := -1) -> Dictionary:
    if not collider is CollisionObject3D:
        return {}
    var body := collider as CollisionObject3D
    var shape_id := 0
    for owner_id in body.get_shape_owners():
        var shape_transform: Transform3D = body.global_transform * body.shape_owner_get_transform(owner_id)
        for shape_index in range(body.shape_owner_get_shape_count(owner_id)):
            if hit_shape >= 0 and shape_id != hit_shape:
                shape_id += 1
                continue
            var shape := body.shape_owner_get_shape(owner_id, shape_index)
            var hit := _exit_of_shape(shape, shape_transform, entry, direction)
            shape_id += 1
            if hit.is_empty():
                continue
            var distance: float = hit["distance"]
            if distance <= PENETRATION_EPSILON:
                continue
            return hit
    return {}


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
    if t_far <= PENETRATION_EPSILON or t_far <= t_near:
        return {}
    if t_near > PENETRATION_EPSILON * 4.0:
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
    assert(viewport != null, "Ballistics necesita un viewport")
    var cam := viewport.get_camera_3d()
    assert(cam != null, "Ballistics necesita la camara del jugador")
    return cam.global_position
