extends RigidBody3D

var life := 0.0
var last_ping := 0.0


func _ready() -> void:
    contact_monitor = true
    max_contacts_reported = 4
    body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
    life += delta
    if life > 14.0:
        queue_free()


func _on_body_entered(_body: Node) -> void:
    if life < 0.06 or life - last_ping < 0.12:
        return
    var speed := linear_velocity.length()
    if speed > 0.65:
        last_ping = life
        GameAudio.play_3d("shell_drop", global_position, -11.0, randf_range(0.92, 1.12))
