extends Node

## Audio mixto con mix por buses: CC0, Sonniss (EULA sin atribucion) y sintesis propia.
## El disparo actual es placeholder compuesto de alta calidad (G18C+Beretta93R+Sintesis),
## no una G19 pura. Los WAV son secos; una sola sala la pone el bus Range.
##
## Los WAV de `assets/audio/` están normalizados por familia con
## `tools/process_audio.sh` (mismo ataque, cola corta, pico < -1.2 dBFS). Si se
## reemplaza un sonido hay que volver a pasar ese script: este mix da por hecha
## esa normalización y los niveles de abajo están medidos sobre ella.
##
## Ruta verdadera: Weapons y World envian a Range; Range envia a Master y es el
## unico lugar con reverberacion. El layout vive en `default_bus_layout.tres`, no
## se reconstruye ni se corrige en runtime.
##
## No hay +6 dB de buses ni HardLimiter usado como diseño de mezcla. Los niveles
## de cada familia se miden y se dejan en el master PCM; el bus sólo representa
## la sala.

const BUS_WEAPONS := "Weapons"
const BUS_WORLD := "World"
const BUS_RANGE := "Range"

# Tabla única de sonidos: archivo + nivel base en dB. `play_2d` sirve tanto para
# arma como para sonidos locales del jugador (pasos); el BUS de cada entrada es
# la autoridad que decide a qué mezcla pertenece. `play_3d` se usa para eventos
# posicionales del mundo. El segundo argumento de ambos es un *ajuste* en dB
# sobre este nivel base.
# `slide_rear` y `slide_battery` son los DOS golpes de la corredera, que son dos
# eventos fisicos distintos (tope trasero a ~12 ms y vuelta a bateria a ~54 ms) y
# por eso son dos grabaciones distintas:
#
#   slide_rear     Glock 19 real. Pico -0.85 dBFS y 85% de su energia por encima
#                  de 2,5 kHz: chasquido de acero, sin cuerpo.
#   slide_battery  Sig P229 real. Pico -9,82 dBFS y 75% de su energia por debajo
#                  de 800 Hz (centroide 774 Hz): golpe sordo y pesado.
#
# El master del blast ya trae mecanismo enterrado a 1 m, pero estos dos son los
# transitorios cercanos cronometrados a la fisica (tope trasero y bateria, ver
# Glock.gd): sin ellos la corredera se mueve muda. Niveles bajos a proposito
# para no duplicar el blast. Antes los dos usaban el mismo `slide.wav`: su energia vive
# en agudos, donde el estampido ya no compite (medido: a -14 dB el trasero caia
# a solo -6,9 dB del blast en >2,5 kHz y se leia como segundo golpe; a -17 dB
# queda ~10 dB por debajo, presente sin competir). La bateria sube 3 dB porque
# quedaba 27 dB bajo la cola del disparo: inaudible, y el tiro perdia su peso.
const SOUNDS := {
    "empty": {"stream": preload("res://assets/audio/empty_b.wav"), "db": -8.0, "bus": BUS_WEAPONS},
    "slide_rear": {"stream": preload("res://assets/audio/slide_rear.wav"), "db": -17.0, "bus": BUS_WEAPONS},
    "slide_battery": {"stream": preload("res://assets/audio/slide_battery.wav"), "db": -15.0, "bus": BUS_WEAPONS},
    # Mano sobre la corredera: no es un disparo mecanico, es un golpe de acero
    # seco y corto (SoundHolder, Metal Contact). Antes no existia y el gesto de
    # agarrar la corredera era mudo hasta que volvia a bateria.
    "slide_hand": {"stream": preload("res://assets/audio/slide_hand.wav"), "db": -16.0, "bus": BUS_WEAPONS},
    "trigger_reset": {"stream": preload("res://assets/audio/trigger_reset.wav"), "db": -18.0, "bus": BUS_WEAPONS},
    "magin": {"stream": preload("res://assets/audio/magin.wav"), "db": -10.0, "bus": BUS_WEAPONS},
    "magout": {"stream": preload("res://assets/audio/magout.wav"), "db": -10.0, "bus": BUS_WEAPONS},
    # Mecanica de recarga: reten, insercion, asiento y reten de corredera.
    # Sin Foley de manos/ropa/palma mientras no haya mano (ver Glock.gd).
    "slide_release": {"stream": preload("res://assets/audio/slide_release.wav"), "db": -18.0, "bus": BUS_WEAPONS},
    # El cargador cae al mundo, no al arma: bus de mundo y 3D en el suelo.
    "mag_drop": {"stream": preload("res://assets/audio/mag_drop.wav"), "db": -13.0, "bus": BUS_WORLD},
    # El roce del cargador contra el brocal mientras sube: es el tramo que iba
    # mudo entre que el lleno entra en cuadro y asienta. Suena al entrar y su
    # cola muere justo en el clack del asiento.
    "mag_insert": {"stream": preload("res://assets/audio/mag_insert.wav"), "db": -13.0, "bus": BUS_WEAPONS},
    "footstep": {"stream": preload("res://assets/audio/footstep.wav"), "db": -14.0, "bus": BUS_WORLD},
    # Impactos: grabaciones reales de impacto de bala (Gamemaster Audio, Bullet
    # Impact Sounds). Cada material tiene su propia grabacion; antes hormigon,
    # pladur y papel compartian el mismo WAV "generico".
    "impact_concrete": {"stream": preload("res://assets/audio/impact_concrete.wav"), "db": -6.0, "bus": BUS_WORLD},
    "impact_drywall": {"stream": preload("res://assets/audio/impact_drywall.wav"), "db": -7.0, "bus": BUS_WORLD},
    "impact_metal": {"stream": preload("res://assets/audio/impact_metal.wav"), "db": -6.0, "bus": BUS_WORLD},
    "impact_aluminum": {"stream": preload("res://assets/audio/impact_aluminum.wav"), "db": -8.0, "bus": BUS_WORLD},
    "impact_wood": {"stream": preload("res://assets/audio/impact_wood.wav"), "db": -6.0, "bus": BUS_WORLD},
    "ricochet": {"stream": preload("res://assets/audio/ricochet.wav"), "db": -8.0, "bus": BUS_WORLD},
    # Silbido de paso de bala: solo cuando el proyectil cruza cerca del oido
    # (ver Ballistics.gd), nunca por disparar.
    "bullet_flyby": {"stream": preload("res://assets/audio/bullet_flyby.wav"), "db": -12.0, "bus": BUS_WORLD},
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

# Voces simultáneas del arma: cada disparo son 3 voces (blast + tope + bateria).
# El blast DRY dura 360 ms (crack+cuerpo, ver `tools/build_shot.py --dry`),
# así que a la cadencia máxima de la pistola (~13 tiros/s con el gatillo
# mantenido) viven a la vez ~6 blasts y ~3 golpes de mecánica. Con 8 voces se
# cortaban las colas más viejas justo a esa cadencia; 16 las deja enteras y
# sigue siendo un puñado de reproductores.
const MAX_WEAPON_VOICES := 16
const VOICE_FADE := 0.06

var _weapon_voices: Array[AudioStreamPlayer] = []


func _ready() -> void:
    _validate_buses()


## El layout es una dependencia de produccion. Si falta o alguien rompe un
## envio, se grita: no se crea una sala de repuesto ni se hornea reverb en WAV.
func _validate_buses() -> void:
    for bus_name in [BUS_RANGE, BUS_WEAPONS, BUS_WORLD]:
        if AudioServer.get_bus_index(bus_name) < 0:
            push_error("Falta el bus de audio obligatorio: " + bus_name)
    var range_index := AudioServer.get_bus_index(BUS_RANGE)
    var weapons_index := AudioServer.get_bus_index(BUS_WEAPONS)
    var world_index := AudioServer.get_bus_index(BUS_WORLD)
    if weapons_index >= 0 and AudioServer.get_bus_send(weapons_index) != BUS_RANGE:
        push_error("Weapons debe enviar a Range")
    if world_index >= 0 and AudioServer.get_bus_send(world_index) != BUS_RANGE:
        push_error("World debe enviar a Range")
    if range_index >= 0 and AudioServer.get_bus_send(range_index) != "Master":
        push_error("Range debe enviar a Master")


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
    # El limite protege SOLO las voces del arma. Un sonido 2D puede pertenecer
    # al mundo (los pasos locales son el caso actual) y no debe consumir el
    # presupuesto ni provocar que se corte blast/mecanica.
    if cap_voices and bus == BUS_WEAPONS:
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
