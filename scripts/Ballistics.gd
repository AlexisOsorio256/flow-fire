extends Node3D

signal target_hit(zone: String)

const PROJECTILE_MASS := 0.008
const DRAG_K := 0.00142
const GRAVITY := 9.81
const MAX_DISTANCE := 520.0
const COLLISION_MASK := 1

var bullets: Array = []
var tracer_pool: Array[MeshInstance3D] = []
var tracer_material: StandardMaterial3D


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
    var thickness := 0.02
    var penetration_factor := 0.78
    if collider is Node:
        penetrable = bool(collider.get_meta("penetrable", false))
        thickness = float(collider.get_meta("thickness", 0.02))
        penetration_factor = float(collider.get_meta("penetration_factor", 0.78))

    if penetrable:
        var exit_point: Vector3 = point + dir * thickness
        ImpactFX.spawn_impact(exit_point, dir, collider, surface, true)
        b.vel = b.vel * penetration_factor
        b.pos = exit_point + dir * 0.012
        b.penetrations += 1
        if b.penetrations > 3 or b.vel.length() < 90.0:
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
            GameAudio.play_3d("ricochet", point, -1.0, randf_range(0.9, 1.1))
            return

    b.active = false


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
