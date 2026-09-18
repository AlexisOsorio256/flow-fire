class_name Crate
extends RigidBody3D

## Caja de madera HUECA (6 paneles de 12 mm): se deja empujar y voltear.
##
## La bala la atraviesa igual (ver Ballistics: penetracion con agujeros reales). Los agujeros viajan con la caja
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
    # Caja HUECA de 6 paneles: cascara fina de 12 mm, dos paredes por tiro.
    set_meta("thin_shell", true)
    set_meta("wall_thickness", 0.012)
