extends Node

## Captura del mix final para escucharlo fuera del juego (`--audiocapture`).

var _player: CharacterBody3D
var _hud: CanvasLayer
var common: DevCommon


func setup(main_node: Node3D, player_node: CharacterBody3D, hud_node: CanvasLayer, common_node) -> void:
    _player = player_node
    _hud = hud_node
    common = common_node


## Vuelca a WAV lo que sale por Master durante una secuencia guionizada
## (disparos, recarga, pasos). Sirve para revisar el mix con el oído y para
## medirlo (pico, clipping) sin depender de la placa de sonido de la máquina.
## Uso: godot4 --path . --rendering-driver vulkan -- --audiocapture
func run_audiocapture() -> void:
    var capture := AudioEffectCapture.new()
    capture.buffer_length = 12.0
    AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), capture)
    await get_tree().create_timer(1.0).timeout
    capture.clear_buffer()
    for i in range(6):
        var before: int = _player.weapon.chamber
        _player.weapon.force_fire_once()
        print("AUDIOCAP shot ", i, " chamber ", before, "->", _player.weapon.chamber,
            " mag=", _player.weapon.mag, " slide=", snappedf(_player.weapon.slide_pos, 0.0001))
        await get_tree().create_timer(0.22).timeout
    common.force_reloadable_state()
    _player.weapon.start_reload()
    await get_tree().create_timer(2.6).timeout
    for _i in range(4):
        GameAudio.play_2d("footstep", 0.0, randf_range(0.92, 1.08))
        await get_tree().create_timer(0.5).timeout
    # Comprobación de routing: cada voz debe sonar por el bus que dice el diseño.
    print("AUDIOCAPTURE estado arma mag=", _player.weapon.mag, " chamber=", _player.weapon.chamber,
        " slide=", snappedf(_player.weapon.slide_pos, 0.0001), " reloading=", _player.weapon.reloading)
    _player.weapon.force_fire_once()
    GameAudio.play_2d("footstep")
    GameAudio.play_3d("impact_concrete", _player.global_position + Vector3(0, 0, -2))
    await get_tree().create_timer(0.1).timeout
    var routed := {}
    for child in GameAudio.get_children():
        if child is AudioStreamPlayer and child.playing:
            routed[child.stream.resource_path.get_file()] = child.bus
    for child in get_tree().current_scene.get_children():
        if child is AudioStreamPlayer3D and child.playing:
            routed[child.stream.resource_path.get_file()] = child.bus
    for key in routed:
        print("AUDIOCAPTURE routing ", key, " -> ", routed[key])
    var buffer := capture.get_buffer(capture.get_frames_available())
    var path := ProjectSettings.globalize_path("res://captures/mix.wav")
    _save_wav(buffer, path)
    print("AUDIOCAPTURE frames=", buffer.size(), " path=", path)
    get_tree().quit()


func _save_wav(buffer: PackedVector2Array, path: String) -> void:
    var data := PackedByteArray()
    data.resize(buffer.size() * 4)
    var offset := 0
    for i in range(buffer.size()):
        data.encode_s16(offset, int(clampf(buffer[i].x, -1.0, 1.0) * 32767.0))
        data.encode_s16(offset + 2, int(clampf(buffer[i].y, -1.0, 1.0) * 32767.0))
        offset += 4
    var wav := AudioStreamWAV.new()
    wav.format = AudioStreamWAV.FORMAT_16_BITS
    wav.stereo = true
    wav.mix_rate = int(AudioServer.get_mix_rate())
    wav.data = data
    wav.save_to_wav(path)
