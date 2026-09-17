class_name WeaponFX
extends Node3D

## Presentación del fogonazo: geometría, luz de boca y humo.
##
## NO tiene autoridad mecánica: no conoce munición, cadencia, corredera ni
## recarga. La autoridad es `Glock.gd`, que avisa cuando se dispara (`fire()`) y
## este módulo anima el evento visual. El humo lo sigue haciendo `ImpactFX`.
##
## Cuelga de la BOCA REAL de la corredera (`Muzzle`, BoneAttachment sobre
## `Slidder_919`), no del marco: hereda posición y orientación del arma durante
## todo el ciclo, incluido su retroceso.
##
## El fogonazo son 12 triángulos en UNA ArrayMesh con StandardMaterial3D emisivo,
## sin shader propio. Los quads con shader custom se eliminaron tras 20+ capturas
## A/B: en el renderer Mobile sobre Mesa/Intel su rasterización no era
## determinista (runs idénticos pintan o no pintan, sin errores de compilación).
## Malla normal = la misma ruta que el resto del arma.

## Duración del fogonazo. Es el mismo valor que dura la luz: 40 ms, un evento
## extremadamente corto, no una llama que se pueda mirar.
const FLASH_TIME := 0.04

var muzzle_light: OmniLight3D
var flash_mesh: MeshInstance3D
var timer := 0.0


func build() -> void:
	muzzle_light = OmniLight3D.new()
	# La luz de flash sólo aclara el volumen cercano. Una fuente cálida grande
	# convertía la tela negra en cuero dorado durante el disparo.
	muzzle_light.light_color = Color(1.0, 0.97, 0.92)
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 1.6
	muzzle_light.shadow_enabled = false
	add_child(muzzle_light)

	flash_mesh = MeshInstance3D.new()
	flash_mesh.name = "FlashMesh"
	flash_mesh.mesh = _build_flash_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Un núcleo HDR amarillo pálido se comprimía a blanco bajo ACES y parecía
	# una lámina junto al alza. El rojo sigue por encima del umbral de glow, pero
	# verde/azul bajos conservan una llama ámbar legible.
	mat.albedo_color = Color.WHITE
	# El color por vértice concentra amarillo en el cuerpo y apaga la punta:
	# conserva volumen desde la lateral sin otra malla ni textura.
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.20, 0.01)
	mat.emission_energy_multiplier = 0.65
	mat.disable_receive_shadows = true
	# Son volúmenes muy cortos vistos desde cualquier lado durante el retroceso;
	# no se puede perder la mitad por el orden de las caras del ArrayMesh.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash_mesh.material_override = mat
	flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_mesh.visible = false
	add_child(flash_mesh)
	print("WEAPONFX fogonazo listo en la boca de la corredera")


func update(delta: float) -> void:
	timer = maxf(0.0, timer - delta)
	var flash_visible := timer > 0.0
	if flash_mesh != null and flash_mesh.visible != flash_visible:
		flash_mesh.visible = flash_visible
	if muzzle_light != null:
		# Pulso corto sobre el entorno, no una segunda fuente de iluminación
		# amarilla que convierta tela y piel en metal dorado.
		muzzle_light.light_energy = randf_range(0.30, 0.55) if flash_visible else 0.0


## Evento de disparo completo: fogonazo + humo de boca.
func fire(origin: Vector3, cam_fwd: Vector3) -> void:
	pop_flash()
	ImpactFX.spawn_muzzle_smoke(origin, cam_fwd)


## Muestra el fogonazo con tamaño y una desviación leve irregulares. La llama
## nace por encima del cañón; un roll de 360° la metía de nuevo detrás de la
## corredera en algunos disparos de ADS.
func pop_flash() -> void:
	if flash_mesh == null:
		return
	timer = FLASH_TIME
	flash_mesh.rotation = Vector3(0.0, 0.0, randf_range(-0.32, 0.32))
	# Mantiene el máximo físico de ocho centímetros incluso en la variante más
	# grande; la aleatoriedad es de gesto, no un fogonazo que cambia de escala a
	# cada tiro.
	var s := randf_range(0.90, 1.05)
	flash_mesh.scale = Vector3(s, randf_range(0.90, 1.08), randf_range(0.90, 1.00))
	flash_mesh.visible = true


## Llama hexagonal dentro de una sola malla. Un anillo irregular, desplazado
## sobre el cañón, se estrecha hasta la punta; así la lateral lee una lengua y
## no un rombo plano. La irregularidad entre disparos la pone pop_flash().
func _build_flash_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	# La boca es el origen. El anillo ancho queda a 18 mm y ligeramente arriba;
	# la punta llega a 55 mm locales (máximo 80 mm ya escalado), con 28 mm de
	# alto. La mitad baja cae tras la corredera: en ADS se ve la llama, no una
	# tapa que oculte la mira.
	var root := Vector3(0.0, 0.010, 0.002)
	var ring := PackedVector3Array([
		Vector3(-0.011, 0.010, 0.018),
		Vector3(-0.006, 0.003, 0.018),
		Vector3(0.007, 0.004, 0.018),
		Vector3(0.012, 0.014, 0.018),
		Vector3(0.004, 0.028, 0.018),
		Vector3(-0.008, 0.024, 0.018),
	])
	var ring_colors := PackedColorArray([
		Color(1.0, 0.34, 0.035), Color(0.78, 0.12, 0.008),
		Color(0.92, 0.20, 0.012), Color(1.0, 0.46, 0.055),
		Color(1.0, 0.78, 0.20), Color(1.0, 0.58, 0.09),
	])
	var tip := Vector3(0.001, 0.016, 0.055)
	verts.append(root)
	colors.append(Color(1.0, 0.55, 0.10))
	for i in range(ring.size()):
		verts.append(ring[i])
		colors.append(ring_colors[i])
	verts.append(tip)
	colors.append(Color(0.62, 0.07, 0.004))
	# Cono hacia la boca y cono hacia la punta: seis caras de cada uno.
	for i in range(ring.size()):
		var a: int = 1 + i
		var b: int = 1 + ((i + 1) % ring.size())
		idx.append(0)
		idx.append(b)
		idx.append(a)
		idx.append(7)
		idx.append(a)
		idx.append(b)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
