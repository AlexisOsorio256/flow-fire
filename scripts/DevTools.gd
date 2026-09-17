extends Node

## Laboratorio de diagnostico: SOLO setup y despacho de flags. Cada tipo de
## diagnostico vive en su archivo, junto a lo que mide:
##
##   DevWeapon.gd     --armdiag  --gundiag  --geometrydebug  --recoilprobe
##   DevVisual.gd     --visualab  --slowmo
##   DevBenchmark.gd  --fpsbench
##   DevAudio.gd      --audiocapture
##   DevCommon.gd     utilidades que comparten dos o mas modulos
##
## Los TESTS (autotest, aimtest, reloadtest, pentest, penetrationdiag) viven en
## Main.gd, que es el juego. `--devhelp` lista todo lo disponible.
## Uso: godot4 --path . -- --devhelp

const DEV_BENCHMARK := preload("res://scripts/DevBenchmark.gd")
const DEV_VISUAL := preload("res://scripts/DevVisual.gd")
const DEV_WEAPON := preload("res://scripts/DevWeapon.gd")
const DEV_AUDIO := preload("res://scripts/DevAudio.gd")
const DEV_COMMON := preload("res://scripts/DevCommon.gd")

## Comandos del laboratorio: flag -> descripcion corta.
const TOOLS := {
    "--devhelp": "esta ayuda",
    "--armdiag": "encuadre de brazos y silueta en % de pantalla",
    "--gundiag": "geometria del rig: piel, miras, muñeca, escala manos/arma",
    "--geometrydebug": "geometria, encuadre, corredera y recarga",
    "--recoilprobe": "perfil de retroceso real del primer disparo",
    "--visualab": "capturas A/B deterministas (--visualout=, --visualonly=)",
    "--slowmo": "disparo y recarga en camara lenta",
    "--fpsbench": "rendimiento (--fpsvariant=, --fpsreps=, --fpsduration=)",
    "--audiocapture": "captura el mix final a WAV",
}

## Tests de Main.gd: se listan aqui para que la ayuda sea el unico punto de
## descubrimiento, pero su autoridad es Main.gd.
const TESTS := {
    "--autotest": "disparo, blanco, dano, recarga y recamarado",
    "--aimtest": "ADS: mira real centrada en el eje optico",
    "--reloadtest": "recarga en vacio y tactica",
    "--pentest": "penetracion, dano y decals",
    "--penetrationdiag": "salida por la segunda cara de la geometria",
}

var _main: Node3D
var _player: CharacterBody3D
var _hud: CanvasLayer
var _common: Node

var _bench
var _visual
var _weapon
var _audio


func setup(main_node: Node3D, player_node: CharacterBody3D, hud_node: CanvasLayer) -> void:
    _main = main_node
    _player = player_node
    _hud = hud_node


## Despacha los flags de linea de comandos. Sin flags no hace nada: el juego
## normal no carga ningun modulo de diagnostico.
func run(args: PackedStringArray) -> void:
    if args.has("--devhelp"):
        _print_help()
        get_tree().quit()
        return
    if args.has("--fpsbench"):
        _module("bench").run_fpsbench()
    if args.has("--visualab"):
        _module("visual").run_visualab()
    if args.has("--slowmo"):
        _module("visual").run_slowmo()
    if args.has("--recoilprobe"):
        _module("weapon").run_recoilprobe()
    if args.has("--geometrydebug"):
        _module("weapon").run_geometrydebug()
    if args.has("--armdiag"):
        _module("weapon").run_armdiag()
    if args.has("--gundiag"):
        _module("weapon").run_gundiag()
    if args.has("--audiocapture"):
        _module("audio").run_audiocapture()


func _module(which: String):
    match which:
        "bench":
            if _bench == null:
                _bench = _add(DEV_BENCHMARK, "DevBenchmark")
            return _bench
        "visual":
            if _visual == null:
                _visual = _add(DEV_VISUAL, "DevVisual")
            return _visual
        "weapon":
            if _weapon == null:
                _weapon = _add(DEV_WEAPON, "DevWeapon")
            return _weapon
        "audio":
            if _audio == null:
                _audio = _add(DEV_AUDIO, "DevAudio")
            return _audio
    return null


func _add(script, node_name: String):
    var node = script.new()
    node.name = node_name
    add_child(node)
    # DevCommon se crea solo si algun modulo lo necesita: el juego normal no
    # carga nada del laboratorio.
    if _common == null:
        _common = DEV_COMMON.new()
        _common.name = "DevCommon"
        add_child(_common)
        _common.setup(_main, _player, _hud, _common)
    node.setup(_main, _player, _hud, _common)
    return node


func _print_help() -> void:
    print("FlowFire: herramientas de diagnostico")
    print("  godot4 --path . -- --<comando>")
    for flag in TOOLS:
        print("  %-18s %s" % [flag, TOOLS[flag]])
    print("Tests (en Main.gd, con --headless):")
    for flag in TESTS:
        print("  %-18s %s" % [flag, TESTS[flag]])
