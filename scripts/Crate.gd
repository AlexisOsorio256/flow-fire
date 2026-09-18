class_name Crate
extends RigidBody3D

## Caja de madera HUECA (6 paneles de 12 mm): se deja empujar y voltear.
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
    # Pino en paneles de 12 mm: la 9 mm pasa dos paredes sin frenarse.
    set_meta("penetration_resistance", 7.0)


## Fisica centralizada en Ballistics (delta-p). Aqui solo material/geometria.
func take_bullet_hit(_point: Vector3, _normal: Vector3, _speed: float, _energy: float, _direction := Vector3.ZERO) -> void:
    pass
func bullet_flash() -> void:
    pass
