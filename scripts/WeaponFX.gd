class_name WeaponFX
extends Node3D

## Presentación del fogonazo: núcleo caliente + gases de boca + luz + humo.
##
## NO tiene autoridad mecánica: no conoce munición, cadencia, corredera ni
## recarga. La autoridad es `Glock.gd`, que avisa cuando se dispara (`fire()`) y
## este módulo anima el evento visual. El humo lo sigue haciendo `ImpactFX`.
##
## Cuelga de la BOCA REAL de la corredera (`Muzzle`, BoneAttachment sobre
## `Slidder_919`), no del marco: hereda posición y orientación del arma durante
## todo el ciclo, incluido su retroceso.
##
## Dos volúmenes, dos trabajos:
##   FlashCore  ~10 mm emisivos sobre el eje del cañón. Es el fogonazo: cae a
##              plomo en pocos milisegundos y es lo único que brilla (glow).
##   FlashGas   nube irregular de ~18 mm alrededor de la boca con blend aditivo.
##              Sus colores por vértice SON su opacidad: la cola casi negra no
##              aporta nada, así que la silueta se apaga sola y no hay borde de
##              polígono.
##
## Malla normal, no quads con shader custom: en el renderer Mobile sobre
## Mesa/Intel la rasterizacion de estos ultimos no era determinista (runs
## identicos pintan o no, sin errores de compilacion), y la malla es la misma
## ruta que el resto del arma.

## Duración visible del evento. 40 ms: extremadamente corto, no una llama que se
## pueda mirar.
const FLASH_TIME := 0.04
## Apagado relativo. El núcleo es un fogonazo de milisegundos (cae a plomo); los
## gases son lo único que sobrevive hasta el final del evento.
const CORE_DECAY := 4.0
const GAS_DECAY := 1.4
const CORE_EMISSION := 1.7

var muzzle_light: OmniLight3D
var flash_mesh: MeshInstance3D  # gases (aditivo)
var core_mesh: MeshInstance3D   # núcleo caliente (emisivo)
var timer := 0.0

var _gas_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D


func build() -> void:
	muzzle_light = OmniLight3D.new()
	# La luz de flash sólo aclara el volumen cercano. Una fuente cálida grande
	# convertía la tela negra en cuero dorado durante el disparo.
	muzzle_light.light_color = Color(1.0, 0.97, 0.92)
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 1.6
	muzzle_light.shadow_enabled = false
	# Ilumina el viewmodel, que es de quien es la luz: ni siquiera el fogonazo
	# puede alumbrar el mundo, o al disparar pegado a una pared el pulso se ve
	# como una linterna encendida. El fogonazo se ve por sus MALLAS, que están
	# en la capa del mundo delante de la boca; la luz solo define el arma.
	muzzle_light.light_cull_mask = GlockViewmodel.VIEWMODEL_LAYER_BIT
	add_child(muzzle_light)

	_gas_mat = StandardMaterial3D.new()
	_gas_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gas_mat.albedo_color = Color.WHITE
	# El color por vértice ES la opacidad con blend aditivo: donde el gas se
	# enfría (casi negro) no se dibuja nada. Eso borra el borde duro del
	# poliedro sin textura, sin alpha y sin shader.
	_gas_mat.vertex_color_use_as_albedo = true
	_gas_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_gas_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# Son volúmenes muy cortos vistos desde cualquier lado durante el retroceso;
	# no se puede perder la mitad por el orden de las caras del ArrayMesh.
	_gas_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_gas_mat.disable_receive_shadows = true
	flash_mesh = MeshInstance3D.new()
	flash_mesh.name = "FlashGas"
	flash_mesh.mesh = _build_gas_mesh()
	flash_mesh.material_override = _gas_mat
	flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_mesh.visible = false
	add_child(flash_mesh)

	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Un núcleo HDR amarillo pálido se comprimía a blanco bajo ACES y parecía una
	# lámina junto al alza. Emisión ámbar por encima del umbral de glow pero con
	# verde/azul bajos: conserva el color de combustión al florecer.
	_core_mat.albedo_color = Color(1.0, 0.86, 0.62)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(1.0, 0.62, 0.28)
	_core_mat.emission_energy_multiplier = CORE_EMISSION
	_core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_core_mat.disable_receive_shadows = true
	core_mesh = MeshInstance3D.new()
	core_mesh.name = "FlashCore"
	core_mesh.mesh = _build_core_mesh()
	core_mesh.material_override = _core_mat
	core_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core_mesh.visible = false
	add_child(core_mesh)

	print("WEAPONFX fogonazo nucleo+gas en la boca de la corredera")


func update(delta: float) -> void:
	timer = maxf(0.0, timer - delta)
	var lit := timer > 0.0
	if flash_mesh.visible != lit:
		flash_mesh.visible = lit
		core_mesh.visible = lit
	if not lit:
		if muzzle_light != null:
			muzzle_light.light_energy = 0.0
		return
	var f := timer / FLASH_TIME
	# Los dos volúmenes se apagan a ritmos distintos: el núcleo con pow alto
	# (desaparece en el primer frame o dos) y los gases con una caída suave.
	_gas_mat.albedo_color = Color(1.0, 1.0, 1.0) * pow(f, GAS_DECAY)
	_core_mat.emission_energy_multiplier = CORE_EMISSION * pow(f, CORE_DECAY)
	if muzzle_light != null:
		# Pico caliente que muere con el fogonazo, no franja fija: desde atras
		# (cadera) una luz sostenida parecia una linea encendida sobre la
		# corredera al disparar seguido.
		muzzle_light.light_energy = randf_range(0.35, 0.60) * f


## Evento de disparo completo: fogonazo + humo de boca.
func fire(origin: Vector3, cam_fwd: Vector3) -> void:
	pop_flash()
	ImpactFX.spawn_muzzle_smoke(origin, cam_fwd)


## Muestra el fogonazo con tamaño y desviación leves irregulares. Un roll de
## 360° metía la llama de nuevo detrás de la corredera en algunos disparos de
## ADS, así que el giro es corto y los dos volúmenes lo comparten.
func pop_flash() -> void:
	if flash_mesh == null:
		return
	timer = FLASH_TIME
	var roll := randf_range(-0.32, 0.32)
	flash_mesh.rotation = Vector3(0.0, 0.0, roll)
	core_mesh.rotation = Vector3(0.0, 0.0, roll)
	# La aleatoriedad es de gesto, no un fogonazo que cambia de escala a cada
	# tiro: la nube siempre muere a la misma distancia de la boca.
	var s := randf_range(0.90, 1.05)
	flash_mesh.scale = Vector3(s, randf_range(0.90, 1.08), randf_range(0.90, 1.00))
	core_mesh.scale = Vector3.ONE * randf_range(0.85, 1.15)
	_gas_mat.albedo_color = Color.WHITE
	_core_mat.emission_energy_multiplier = CORE_EMISSION
	flash_mesh.visible = true
	core_mesh.visible = true


## Gas: nube corta e irregular pegada a la boca. Los ocho vértices de cada anillo
## van a radios y alturas DESIGUALES a propósito (ni hexágono ni estrella) y el
## brillo cae del EJE hacia fuera: raíz caliente en la boca, anillo interior
## ámbar y anillo exterior casi negro. Con blend aditivo eso significa que el
## contorno del poliedro no dibuja nada, que es lo que convierte la silueta en
## gas y no en una pieza recortada.
##
## No hay punta ni aguja: el volumen muere a ~12 mm delante de la boca (desde
## atras se escorza a casi nada en vez de leerse como lapiz sobre la
## corredera) y abre un poco a los lados para que el halo asome por los
## cantos de la corredera en vez de apilarse encima.
func _build_gas_mesh() -> ArrayMesh:
	var inner := PackedVector3Array([
		Vector3(-0.0060, 0.0072, 0.004),
		Vector3(-0.0042, 0.0020, 0.008),
		Vector3(0.0008, 0.0004, 0.003),
		Vector3(0.0056, 0.0030, 0.009),
		Vector3(0.0050, 0.0102, 0.004),
		Vector3(0.0010, 0.0155, 0.010),
		Vector3(-0.0038, 0.0134, 0.005),
		Vector3(-0.0064, 0.0094, 0.007),
	])
	var inner_colors := PackedColorArray([
		Color(0.50, 0.17, 0.030), Color(0.34, 0.10, 0.016),
		Color(0.44, 0.14, 0.022), Color(0.28, 0.08, 0.012),
		Color(0.56, 0.20, 0.036), Color(0.38, 0.12, 0.020),
		Color(0.24, 0.07, 0.010), Color(0.46, 0.15, 0.026),
	])
	var outer := PackedVector3Array([
		Vector3(-0.0130, 0.0070, 0.010),
		Vector3(-0.0088, -0.0028, 0.016),
		Vector3(0.0018, -0.0072, 0.011),
		Vector3(0.0122, -0.0010, 0.017),
		Vector3(0.0108, 0.0120, 0.009),
		Vector3(0.0020, 0.0198, 0.016),
		Vector3(-0.0082, 0.0168, 0.010),
		Vector3(-0.0136, 0.0102, 0.014),
	])
	var outer_colors := PackedColorArray([
		Color(0.14, 0.035, 0.006), Color(0.06, 0.013, 0.002),
		Color(0.10, 0.024, 0.004), Color(0.04, 0.008, 0.001),
		Color(0.16, 0.040, 0.007), Color(0.07, 0.016, 0.003),
		Color(0.03, 0.006, 0.001), Color(0.12, 0.030, 0.005),
	])
	var n := inner.size()
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	# La boca es el origen: raíz caliente pegada al cañón, anillo interior a
	# media llama y exterior ya casi negro (el contorno no dibuja).
	verts.append(Vector3(0.0, 0.0085, 0.000))
	colors.append(Color(0.95, 0.42, 0.10))
	verts.append_array(inner)
	colors.append_array(inner_colors)
	verts.append_array(outer)
	colors.append_array(outer_colors)
	# De frente el chorro debe morir pronto y abrir halo: menos aguja en Z,
	# mas aire a los lados. La raiz (boca) no se toca.
	for i in range(1, verts.size()):
		var v: Vector3 = verts[i]
		verts[i] = Vector3(v.x * 1.2, v.y, v.z * 0.65)
	var idx := PackedInt32Array()
	for i in range(n):
		var a := 1 + i
		var b := 1 + ((i + 1) % n)
		idx.append(0)
		idx.append(b)
		idx.append(a)
		var c := 1 + n + i
		var d := 1 + n + ((i + 1) % n)
		idx.append(a)
		idx.append(b)
		idx.append(d)
		idx.append(a)
		idx.append(d)
		idx.append(c)
	return _mesh_from(verts, colors, idx)


## Núcleo: pequeño, sobre el eje del cañón y pegado a la boca. Cuatro caras
## irregulares bastan: lo que se ve es el resplandor, no su forma.
func _build_core_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	# Nace EN la boca y crece hacia delante, poco más de la mitad que el gas: lo
	# que queda dentro de la corredera no se ve y una punta larga se lee como
	# geometría. Cuatro caras irregulares bastan: lo que se ve es el resplandor.
	var root := Vector3(0.0, 0.008, -0.001)
	var ring := PackedVector3Array([
		Vector3(-0.0062, 0.0060, 0.004),
		Vector3(-0.0022, 0.0012, 0.002),
		Vector3(0.0058, 0.0022, 0.005),
		Vector3(0.0030, 0.0122, 0.003),
	])
	var tip := Vector3(0.0008, 0.0088, 0.011)
	verts.append(root)
	for p in ring:
		verts.append(p)
	verts.append(tip)
	# Como el gas: corto hacia delante para que desde atras no haga lapiz.
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		verts[i] = Vector3(v.x * 1.1, v.y, v.z * 0.65)
	for i in range(ring.size()):
		var a: int = 1 + i
		var b: int = 1 + ((i + 1) % ring.size())
		idx.append(0)
		idx.append(b)
		idx.append(a)
		idx.append(5)
		idx.append(a)
		idx.append(b)
	return _mesh_from(verts, PackedColorArray(), idx)


func _mesh_from(verts: PackedVector3Array, colors: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
