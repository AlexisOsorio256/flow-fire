extends Node

const SHOT_STREAMS: Array[AudioStream] = [
    preload("res://assets/audio/shot_1.wav"),
    preload("res://assets/audio/shot_2.wav"),
    preload("res://assets/audio/shot_3b.wav"),
    preload("res://assets/audio/shot_4.wav"),
    preload("res://assets/audio/shot_5.wav"),
    preload("res://assets/audio/shot_6.wav"),
]

const SOUNDS := {
    "empty": preload("res://assets/audio/empty_b.wav"),
    "slide": preload("res://assets/audio/slide.wav"),
    "magin": preload("res://assets/audio/magin.wav"),
    "magout": preload("res://assets/audio/magout.wav"),
    "footstep": preload("res://assets/audio/footstep.wav"),
    "impact_concrete": preload("res://assets/audio/impact_concrete.wav"),
    "impact_metal": preload("res://assets/audio/impact_metal.wav"),
    "impact_wood": preload("res://assets/audio/impact_wood.wav"),
    "ricochet": preload("res://assets/audio/ricochet.wav"),
    "shell_drop": preload("res://assets/audio/shell_drop.wav"),
}


func _ready() -> void:
    var master := AudioServer.get_bus_index("Master")
    if master >= 0:
        var limiter := AudioEffectHardLimiter.new()
        limiter.ceiling_db = -0.6
        limiter.pre_gain_db = 0.0
        limiter.release = 0.12
        AudioServer.add_bus_effect(master, limiter)


func play_shot(volume_db: float = -3.0) -> void:
    var p := AudioStreamPlayer.new()
    p.stream = SHOT_STREAMS[randi() % SHOT_STREAMS.size()]
    p.volume_db = volume_db + randf_range(-1.2, 1.2)
    p.pitch_scale = randf_range(0.965, 1.035)
    add_child(p)
    p.finished.connect(p.queue_free)
    p.play()
    # Capa mecánica real de la corredera, un toque después del disparo.
    var mech := AudioStreamPlayer.new()
    mech.stream = SOUNDS["slide"]
    mech.volume_db = randf_range(-16.0, -12.5)
    mech.pitch_scale = randf_range(0.98, 1.06)
    add_child(mech)
    mech.finished.connect(mech.queue_free)
    get_tree().create_timer(0.045).timeout.connect(func() -> void:
        if is_instance_valid(mech):
            mech.play()
    )


func play_2d(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
    if not SOUNDS.has(sound_name):
        return
    var p := AudioStreamPlayer.new()
    p.stream = SOUNDS[sound_name]
    p.volume_db = volume_db
    p.pitch_scale = pitch
    add_child(p)
    p.finished.connect(p.queue_free)
    p.play()


func play_3d(sound_name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
    if not SOUNDS.has(sound_name):
        return
    var scene := get_tree().current_scene
    if scene == null:
        return
    var p := AudioStreamPlayer3D.new()
    p.stream = SOUNDS[sound_name]
    p.volume_db = volume_db
    p.pitch_scale = pitch
    p.max_distance = 90.0
    p.unit_size = 3.0
    scene.add_child(p)
    p.global_position = pos
    p.finished.connect(p.queue_free)
    p.play()
