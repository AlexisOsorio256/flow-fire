class_name GlockRecoil
extends RefCounted

## Retroceso del arma DENTRO de la mano, mas una respuesta lenta y pequena de
## las manos. La camara sigue siendo responsabilidad de Player.gd.
##
## Una sola autoridad de presentacion por capa:
##   arma/cargador .... `rot` + `pos`, aplicados por GlockViewmodel a los huesos
##   manos/brazos ..... `arm_rot` + `arm_pos`, aplicados al WristPivot
##   camara/cuerpo ..... Player.gd
##   corredera ......... Glock.gd (`slide_pos`)
##
## En la captura real el problema era el contrario al antiguo "doble recoil":
## el mundo/camara se movia, pero el conjunto de manos quedaba demasiado fijo y
## la pistola apenas tenia recorrido lineal. El resultado se leia liviano. Esta
## capa lenta NO repite el latigazo del arma: solo deja que las manos cedan unos
## milimetros y ~1 grado despues del golpe, y vuelvan con mas masa.

# Cabeceo rapido del ARMA. Con k=520/c=18 da un pico de ~7.7 grados a ~55 ms.
const MAIN_RECOIL_KICK := 5.10
const WEAPON_K := 520.0
const WEAPON_C := 18.0
# Respuesta de manos: mas lenta, casi criticamente amortiguada. Pico aproximado
# de 2-3 mm y ~1 grado; suficiente para que el agarre absorba sin convertirse en
# una segunda animacion de disparo.
const ARM_K := 72.0
const ARM_C := 13.6

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var rot := Vector3.ZERO
var rot_vel := Vector3.ZERO
var arm_pos := Vector3.ZERO
var arm_vel := Vector3.ZERO
var arm_rot := Vector3.ZERO
var arm_rot_vel := Vector3.ZERO
# Pivote del agarre, en el espacio del hueso padre del arma (lo mide el
# viewmodel con el rig real). Arma y cargador comparten padre y pivote.
var pivot := Vector3.ZERO


## El disparo tiene dos tiempos: primero el arma gira/hunde dentro del agarre;
## despues las manos ceden una fraccion. La dispersion lateral es simetrica y
## pequena: no hay un giro sistematico de videojuego.
func kick_shot() -> void:
	rot_vel += Vector3(
		MAIN_RECOIL_KICK + randf() * 0.30,
		(randf() - 0.5) * 0.14,
		(randf() - 0.5) * 0.18
	)
	# ~3 mm de recorrido pico hacia el tirador, no el milimetro casi invisible
	# de la version anterior.
	vel += Vector3((randf() - 0.5) * 0.012, 0.018, 0.095 + randf() * 0.015)
	# Las manos responden despues, mas blandas que el arma.
	arm_vel += Vector3((randf() - 0.5) * 0.010, 0.012, 0.052 + randf() * 0.008)
	arm_rot_vel += Vector3(0.34 + randf() * 0.05, 0.0, (randf() - 0.5) * 0.07)


## Asentar un cargador transmite masa al agarre, pero no parece otro disparo.
func kick_mag_seat() -> void:
	rot_vel.x += 0.24
	vel.z += 0.010
	arm_vel += Vector3(0.0, -0.006, 0.018)
	arm_rot_vel.x -= 0.06


## Pivote de giro del arma, en el espacio de su hueso padre.
func set_wrist_pivot(point: Vector3) -> void:
	pivot = point


## La capa lenta mueve el conjunto desde la muneca; la rapida sigue siendo de
## los huesos del arma/cargador. `node.position = -pivot` mantiene el mismo
## pivote geometrico al rotar WristPivot.
func apply(wrist: Node3D, node: Node3D) -> void:
	wrist.position = pivot + arm_pos
	wrist.rotation = arm_rot
	node.position = -pivot
	node.rotation = Vector3.ZERO


func update(delta: float) -> void:
	var res_p := Springs.vector(pos, vel, WEAPON_K, WEAPON_C, delta)
	pos = res_p[0]
	vel = res_p[1]
	var res_r := Springs.vector(rot, rot_vel, WEAPON_K, WEAPON_C, delta)
	rot = res_r[0]
	rot_vel = res_r[1]
	pos = Vector3(clampf(pos.x, -0.012, 0.012), clampf(pos.y, -0.012, 0.018), clampf(pos.z, -0.018, 0.020))
	rot = Vector3(clampf(rot.x, -0.22, 0.22), clampf(rot.y, -0.055, 0.055), clampf(rot.z, -0.065, 0.065))

	var res_ap := Springs.vector(arm_pos, arm_vel, ARM_K, ARM_C, delta)
	arm_pos = res_ap[0]
	arm_vel = res_ap[1]
	var res_ar := Springs.vector(arm_rot, arm_rot_vel, ARM_K, ARM_C, delta)
	arm_rot = res_ar[0]
	arm_rot_vel = res_ar[1]
	arm_pos = Vector3(clampf(arm_pos.x, -0.008, 0.008), clampf(arm_pos.y, -0.008, 0.008), clampf(arm_pos.z, -0.008, 0.010))
	arm_rot = Vector3(clampf(arm_rot.x, -0.035, 0.035), 0.0, clampf(arm_rot.z, -0.018, 0.018))