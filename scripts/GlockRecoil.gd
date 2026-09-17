class_name GlockRecoil
extends RefCounted

## Retroceso del arma, en dos capas con escala de tiempo propia (mas la camara,
## que la lleva Player.gd):
##   1) el ARMA en la mano: este objeto, girando sobre el pivote de la munece
##      (~240 ms). Es el latigazo.
##   2) brazos/viewmodel: la pose entera, mas lenta y blanda (~660 ms).
##
## Este archivo POSEE su estado de resortes: esa es su responsabilidad. No
## conoce municion, recamara, cadencia ni recarga. La autoridad mecanica le avisa
## del evento fisico (`kick_shot`, `kick_mag_seat`) y el viewmodel le pide que
## aplique su transformacion al rig.
##
## QUIEN SE MUEVE: en un disparo real la mano NO retrocede con el arma. El arma
## gira y se hunde DENTRO del agarre (la munece absorbe) y el brazo entero
## acompana despues, blando. Por eso la capa rapida NO toca los brazos: `rot` es
## la rotacion del ARMA alrededor del pivote y el viewmodel la escribe en el
## hueso del arma (ver `bone_offset`); solo la capa lenta (`arm_rot`/`arm_pos`)
## mueve el viewmodel completo, manos incluidas, y siempre despues.

# Impulso de cabeceo del ARMA en el disparo (rad/s). Es la unica fuente del
# latigazo visible desde que el clip Fire no mueve el hueso del arma: medido
# la animacion del asset daba 0.24 grados en los primeros 40 ms y subia en
# rampa hasta 180 ms, que es lo que hacia que la vaina pareciese moverse mas
# que la pistola. Con 4.2 rad/s la boca sube ~8 grados con pico
# a ~50 ms.
const MAIN_RECOIL_KICK := 4.2
# El pivote del giro va detras y debajo de la empunadura (lo mide el viewmodel
# con el rig real), asi que la boca sube mientras la empunadura casi no se
# mueve. Con k=700/zeta 0.75 el arma volvia a casa en 150 ms y no llegaba a
# subir; con k=520/c=18 (zeta 0.39) el pico cae a ~50 ms y la recuperacion es
# controlada hacia 250 ms.
const WEAPON_K := 520.0
const WEAPON_C := 18.0
# Capa de brazos: mas lenta y mas blanda. Da sensacion de masa del brazo, no
# un segundo latigazo. Es la UNICA capa que mueve las manos.
const ARM_K := 90.0
const ARM_C := 15.2

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var rot := Vector3.ZERO
var rot_vel := Vector3.ZERO
var arm_pos := Vector3.ZERO
var arm_vel := Vector3.ZERO
var arm_rot := Vector3.ZERO
var arm_rot_vel := Vector3.ZERO
var wrist_local := Vector3.ZERO  # pivote medido, en el frame del esqueleto


## Impulso del disparo. Dos escalas: el arma cabecea sobre el pivote de la mano
## (~50 ms) y los brazos absorben despues, con menos amplitud y mas lentos.
func kick_shot() -> void:
	rot_vel += Vector3(MAIN_RECOIL_KICK + randf() * 0.35, (randf() - 0.5) * 0.2, (randf() - 0.5) * 0.3)
	arm_vel += Vector3((randf() - 0.5) * 0.03, 0.05, 0.22 + randf() * 0.03)
	arm_rot_vel += Vector3(0.8 + randf() * 0.16, 0.0, (randf() - 0.5) * 0.16)


## El cargador asienta en el brocal: fraccion deliberada del retroceso de un
## disparo (~1 mm / ~0,2 grados de pico, no otro latigazo). Reutiliza el resorte
## fisico existente en vez de anadir coreografia.
func kick_mag_seat() -> void:
	arm_vel += Vector3(0.0, -0.012, 0.040)
	arm_rot_vel.x -= 0.14


## Pivote de giro del arma, en el frame del ESQUELETO (lo mide el viewmodel con
## el rig real). En ese mismo frame se escribe la rotacion del arma en el hueso.
func set_wrist_pivot(point: Vector3) -> void:
	wrist_local = point


## Desplazamiento LOCAL que hay que sumar a la posicion de reposo del hueso del
## arma para que gire `rot_by` alrededor del pivote medido. En espacio del
## esqueleto el hueso esta en `rest_bone`; girarlo sobre el pivote lo lleva a
## pivot + R*(rest_bone - pivot) y el hueso, cuyo frame tiene la misma
## orientacion que el esqueleto, solo necesita la diferencia. Con rot_by = 0 el
## offset es exactamente cero: el arma se queda donde la dejo su animacion.
func bone_offset(rot_by: Vector3, rest_bone: Vector3) -> Vector3:
	if rot_by.length_squared() < 1e-12:
		return Vector3.ZERO
	var lever := rest_bone - wrist_local
	return (Basis.from_euler(rot_by) * lever) - lever


## Escribe la capa LENTA en el rig completo: brazos y manos acompanan al arma
## desde el hombro. La capa rapida del arma NO se escribe aqui: rotar este nodo
## arrastraria las manos hacia atras, que es justo lo que no hace un retroceso
## real (el arma se mueve dentro del agarre, la mano no).
func apply(wrist: Node3D, node: Node3D) -> void:
	wrist.position = wrist_local + arm_pos
	wrist.rotation = arm_rot
	node.position = -wrist_local
	node.rotation = Vector3.ZERO


func update(delta: float) -> void:
	# Capa 1: el arma gira y se hunde dentro de la mano. El pivote va detras y
	# debajo de la empunadura (medido con el rig real), asi que la boca sube
	# mientras la empunadura casi no se mueve: es lo que hace un retroceso real
	# y lo que antes se sentia "forzado" (giro sobre el centro del arma).
	# k=520/c=18 (zeta 0.39): pico del cabeceo a ~50 ms y recuperacion
	# controlada hacia 250 ms. Con el resorte anterior (k=700, zeta 0.75) el
	# arma volvia a casa en 150 ms y no llegaba a subir.
	var res_p := Springs.vector(pos, vel, WEAPON_K, WEAPON_C, delta)
	pos = res_p[0]
	vel = res_p[1]
	var res_r := Springs.vector(rot, rot_vel, WEAPON_K, WEAPON_C, delta)
	rot = res_r[0]
	rot_vel = res_r[1]
	pos = Vector3(clampf(pos.x, -0.04, 0.04), clampf(pos.y, -0.03, 0.03), clampf(pos.z, -0.03, 0.055))
	rot = Vector3(clampf(rot.x, -0.24, 0.24), clampf(rot.y, -0.08, 0.08), clampf(rot.z, -0.1, 0.1))

	# Capa 2: brazos y viewmodel entero, mas lento y blando.
	var res_ap := Springs.vector(arm_pos, arm_vel, ARM_K, ARM_C, delta)
	arm_pos = res_ap[0]
	arm_vel = res_ap[1]
	var res_ar := Springs.vector(arm_rot, arm_rot_vel, ARM_K, ARM_C, delta)
	arm_rot = res_ar[0]
	arm_rot_vel = res_ar[1]
	arm_pos = Vector3(clampf(arm_pos.x, -0.02, 0.02), clampf(arm_pos.y, -0.02, 0.02), clampf(arm_pos.z, -0.02, 0.03))
	arm_rot = Vector3(clampf(arm_rot.x, -0.08, 0.08), 0.0, clampf(arm_rot.z, -0.04, 0.04))
