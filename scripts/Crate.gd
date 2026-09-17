class_name Crate
extends RigidBody3D

## Caja de madera reactiva: se deja empujar y voltear por los impactos.
##
## La bala la atraviesa igual (ver Ballistics: `take_bullet_hit` y despues la
## penetracion con sus agujeros reales). Los agujeros viajan con la caja
## (`dynamic_decal`): una caja volteada sigue ensenando sus tiros.


func _ready() -> void:
    collision_layer = 1
    collision_mask = 1
    continuous_cd = true
    linear_damp = 0.3
    angular_damp = 0.5
    set_meta("dynamic_decal", true)
    set_meta("surface", "wood")
    set_meta("penetrable", true)
    # Pino: 45 mm lo pasan sobrados, 35 cm salen al limite.
    set_meta("penetration_resistance", 7.0)


## Un 9 mm a 300 m/s trae ~360 J: empuja la caja y la hace girar sin
## lanzarla como un juguete. La escala es la misma norma que Target.
func take_bullet_hit(point: Vector3, normal: Vector3, speed: float, energy: float, direction := Vector3.ZERO) -> void:
    var push := direction.normalized() if direction.length_squared() > 0.1 else -normal.normalized()
    var strength := 1.2 + (energy / 520.0) * 2.0
    apply_impulse(push * strength + Vector3.UP * strength * 0.25, point - global_position)
    apply_torque_impulse(Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(-0.3, 0.3)))
