extends Node

## Audio real CC0 con mix por buses.
##
## Los WAV de `assets/audio/` están normalizados por familia con
## `tools/process_audio.sh` (mismo ataque, cola corta, pico < -1.5 dBFS). Si se
## reemplaza un sonido hay que volver a pasar ese script: este mix da por hecha
## esa normalización y los niveles de abajo están medidos sobre ella.
##
## Reparto: el arma suena en el bus `Weapons` y el mundo (impactos, rebotes,
## casquillos, pasos) en `World`. Cada bus tiene su compresor para que la suma de
## capas no sature, y en Master sólo queda un techo de seguridad.

const BUS_WEAPONS := "Weapons"
const BUS_WORLD := "World"

# Tabla única de sonidos: archivo + nivel base en dB. Los one-shots del arma se
# piden con `play_2d`, los del mundo con `play_3d`; el segundo argumento de
# ambos es un *ajuste* en dB sobre este nivel base.
const SOUNDS := {
    "empty": {"stream": preload("res://assets/audio/empty_b.wav"), "db": -8.0, "bus": BUS_WEAPONS},
    "slide": {"stream": preload("res://assets/audio/slide.wav"), "db": -10.0, "bus": BUS_WEAPONS},
    "magin": {"stream": preload("res://assets/audio/magin.wav"), "db": -10.0, "bus": BUS_WEAPONS},
    "magout": {"stream": preload("res://assets/audio/magout.wav"), "db": -10.0, "bus": BUS_WEAPONS},
    "footstep": {"stream": preload("res://assets/audio/footstep.wav"), "db": -14.0, "bus": BUS_WORLD},
    "impact_concrete": {"stream": preload("res://assets/audio/impact_concrete.wav"), "db": -6.0, "bus": BUS_WORLD},
    "impact_metal": {"stream": preload("res://assets/audio/impact_metal.wav"), "db": -6.0, "bus": BUS_WORLD},
    "impact_wood": {"stream": preload("res://assets/audio/impact_wood.wav"), "db": -6.0, "bus": BUS_WORLD},
    "ricochet": {"stream": preload("res://assets/audio/ricochet.wav"), "db": -8.0, "bus": BUS_WORLD},
    "shell_drop": {"stream": preload("res://assets/audio/shell_drop.wav"), "db": -14.0, "bus": BUS_WORLD},
}

const SHOT_STREAMS: Array[AudioStream] = [
    preload("res://assets/audio/shot_1.wav"),
    preload("res://assets/audio/shot_2.wav"),
    preload("res://assets/audio/shot_3.wav"),
    preload("res://assets/audio/shot_4.wav"),
    preload("res://assets/audio/shot_5.wav"),
]

const SHOT_DB := -6.0        # disparo (los 5 WAV comparten loudness de ataque)

# Voces simultáneas del arma: al disparar rápido las colas se apilaban y
# enfangaban el mix, así que se cortan las más viejas con un fade corto.
const MAX_WEAPON_VOICES := 4
const VOICE_FADE := 0.06

var _weapon_voices: Array[AudioStreamPlayer] = []


func _ready() -> void:
    _setup_buses()


## Crea los buses y su dinámica. Se hace por código para que el proyecto no
## dependa de un layout binario que nadie revisa.
func _setup_buses() -> void:
    var weapons := _ensure_bus(BUS_WEAPONS)
    AudioServer.set_bus_volume_db(weapons, 0.0)
    AudioServer.add_bus_effect(weapons, _compressor(-14.0, 3.0, 0.004, 0.12))

    var world := _ensure_bus(BUS_WORLD)
    AudioServer.set_bus_volume_db(world, -3.0)
    AudioServer.add_bus_effect(world, _compressor(-18.0, 2.5, 0.010, 0.20))

    # Master: sólo techo de seguridad, sin pre-ganancia (no debe bombear).
    var master := AudioServer.get_bus_index("Master")
    if master >= 0:
        var limiter := AudioEffectHardLimiter.new()
        limiter.ceiling_db = -1.0
        limiter.pre_gain_db = 0.0
        limiter.release = 0.08
        AudioServer.add_bus_effect(master, limiter)


func _ensure_bus(bus_name: String) -> int:
    var index := AudioServer.get_bus_index(bus_name)
    if index >= 0:
        return index
    AudioServer.add_bus()
    index = AudioServer.bus_count - 1
    AudioServer.set_bus_name(index, bus_name)
    AudioServer.set_bus_send(index, "Master")
    return index


func _compressor(threshold_db: float, ratio: float, attack: float, release: float) -> AudioEffectCompressor:
    var comp := AudioEffectCompressor.new()
    comp.threshold = threshold_db
    comp.ratio = ratio
    comp.attack_us = attack * 1000000.0
    comp.release_ms = release * 1000.0
    comp.gain = 0.0
    return comp


## Sólo el estampido. El golpe mecánico lo emite Glock.gd cuando la corredera
## llega físicamente al tope trasero; mantener ambas autoridades separadas evita
## que una cola fija de audio se despegue del movimiento a otro FPS.
func play_shot() -> void:
    var stream: AudioStream = SHOT_STREAMS[randi() % SHOT_STREAMS.size()]
    _spawn(BUS_WEAPONS, stream, SHOT_DB + randf_range(-1.0, 1.0), randf_range(0.965, 1.035))


## Sonido no posicional. El bus lo declara la tabla según el sonido (el arma va
## a Weapons y el mundo a World), no la función: antes los pasos acababan en el
## bus del arma aunque el diseño dijera lo contrario.
func play_2d(sound_name: String, adjust_db: float = 0.0, pitch: float = 1.0) -> void:
    if not SOUNDS.has(sound_name):
        return
    var entry: Dictionary = SOUNDS[sound_name]
    _spawn(entry["bus"], entry["stream"], entry["db"] + adjust_db, pitch)


## Sonido del mundo, posicional. `adjust_db` matiza el nivel base de la tabla.
func play_3d(sound_name: String, pos: Vector3, adjust_db: float = 0.0, pitch: float = 1.0) -> void:
    if not SOUNDS.has(sound_name):
        return
    var scene := get_tree().current_scene
    if scene == null:
        return
    var entry: Dictionary = SOUNDS[sound_name]
    var p := AudioStreamPlayer3D.new()
    p.stream = entry["stream"]
    p.volume_db = entry["db"] + adjust_db
    p.pitch_scale = pitch
    p.bus = entry["bus"]
    p.max_distance = 90.0
    p.unit_size = 3.0
    scene.add_child(p)
    p.global_position = pos
    p.finished.connect(p.queue_free)
    p.play()


func _spawn(bus: String, stream: AudioStream, volume_db: float, pitch: float, cap_voices := true, autoplay := true) -> AudioStreamPlayer:
    var p := AudioStreamPlayer.new()
    p.stream = stream
    p.volume_db = volume_db
    p.pitch_scale = pitch
    p.bus = bus
    add_child(p)
    p.finished.connect(p.queue_free)
    if cap_voices:
        _limit_weapon_voices(p)
    if autoplay:
        p.play()
    return p


## Corta las voces más viejas del arma cuando se dispara muy seguido.
func _limit_weapon_voices(newest: AudioStreamPlayer) -> void:
    var alive: Array[AudioStreamPlayer] = []
    for voice in _weapon_voices:
        if is_instance_valid(voice) and voice.playing:
            alive.append(voice)
    _weapon_voices = alive
    _weapon_voices.append(newest)
    while _weapon_voices.size() > MAX_WEAPON_VOICES:
        var oldest: AudioStreamPlayer = _weapon_voices.pop_front()
        if not is_instance_valid(oldest):
            continue
        # Fade corto para que el corte no chasquee.
        var fade := create_tween()
        fade.tween_property(oldest, "volume_db", -60.0, VOICE_FADE)
        fade.tween_callback(oldest.queue_free)
