class_name GlockRecoil
extends RefCounted

## Retroceso del arma, en tres capas con escala de tiempo propia:
##   1) mecanica: corredera/gatillo/cargador (la manda Glock.gd, ~60 ms)
##   2) el arma en la mano: este objeto, girando sobre la MUÑECA (~240 ms)
##   3) brazos/viewmodel: la pose entera, mas lento y blando (~660 ms)
##   4) camara: resortes de Player.gd, la mas lenta
##
## Este archivo POSEE su estado de resortes: esa es su responsabilidad. No
## conoce municion, recamara, cadencia ni recarga. La autoridad mecanica le
## avisa del evento fisico (`kick_shot`, `kick_mag_seat`) y el viewmodel le
## pide que aplique su transformacion a los dos nodos del rig.

# Impulso de cabeceo del ARMA en el disparo (rad/s). Es la unica fuente del
# latigazo visible desde que el clip Fire no mueve el hueso del arma: medido
# con --recoilprobe, la animacion daba 0.24 grados en los primeros 40 ms y
# subia en rampa hasta 180 ms, que es lo que hacia que la vaina pareciese
# moverse mas que la pistola. Con 4.2 rad/s la boca sube ~8 grados con pico
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
# un segundo latigazo.
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
var wrist_local := Vector3.ZERO  # punto de giro medido (frame del arma)


## Impulso del disparo. Tres escalas: la muneca recibe el golpe antes de que
## la mano pueda hacer nada (~10 ms), el arma cabecea sobre la muneca (~50 ms)
## y los brazos absorben despues, con menos amplitud.
func kick_shot() -> void:
	vel += Vector3((randf() - 0.5) * 0.02, 0.035, 0.22 + randf() * 0.02)
	rot_vel += Vector3(MAIN_RECOIL_KICK + randf() * 0.35, (randf() - 0.5) * 0.2, (randf() - 0.5) * 0.3)
	arm_vel += Vector3((randf() - 0.5) * 0.03, 0.05, 0.22 + randf() * 0.03)
	arm_rot_vel += Vector3(0.8 + randf() * 0.16, 0.0, (randf() - 0.5) * 0.16)


## El cargador asienta en el brocal: fraccion deliberada del retroceso de un
## disparo (~1 mm / ~0,2 grados de pico, no otro latigazo). Reutiliza el
## resorte fisico existente en vez de anadir coreografia.
func kick_mag_seat() -> void:
	vel += Vector3(0.0, -0.012, 0.040)
	rot_vel.x -= 0.14


## Pivote de muneca en el frame del arma (lo mide el viewmodel con el rig real).
func set_wrist_pivot(point: Vector3) -> void:
	wrist_local = point


## Escribe el retroceso en los DOS nodos del rig. Solo `wrist` rota: antes el
## mismo giro se escribia tambien en su hijo y la jerarquia lo componia DOS
## veces, asi que el angulo que llegaba al arma era el doble del pedido. Ahora
## la composicion es exacta: p -> R(rot)·(p - muneca) + muneca + pos.
## Con rot=0 y pos=0 los dos se cancelan y el conjunto queda en el origen de
## pose_root, que es lo que asume la pose de ADS resuelta una sola vez.
func apply(wrist: Node3D, node: Node3D) -> void:
	wrist.position = wrist_local + pos
	wrist.rotation = rot
	node.position = -wrist_local
	node.rotation = Vector3.ZERO


func update(delta: float) -> void:
	# Capa 2: el arma gira en la mano sobre la muñeca. El pivote va detrás y
	# debajo de la empuñadura (medido de la caja del arma), así que la boca sube
	# mientras la empuñadura casi no se mueve: es lo que hace un retroceso real y
	# lo que antes se sentía "forzado" (giro sobre el centro del arma).
	# k=520/c=18 (zeta 0.39): pico del cabeceo a ~50 ms y recuperación
	# controlada hacia 250 ms. Con el resorte anterior (k=700, zeta 0.75) el
	# arma volvía a casa en 150 ms y no llegaba a subir.
	var res_p := Springs.vector(pos, vel, WEAPON_K, WEAPON_C, delta)
	pos = res_p[0]
	vel = res_p[1]
	var res_r := Springs.vector(rot, rot_vel, WEAPON_K, WEAPON_C, delta)
	rot = res_r[0]
	rot_vel = res_r[1]
	pos = Vector3(clampf(pos.x, -0.04, 0.04), clampf(pos.y, -0.03, 0.03), clampf(pos.z, -0.03, 0.055))
	rot = Vector3(clampf(rot.x, -0.24, 0.24), clampf(rot.y, -0.08, 0.08), clampf(rot.z, -0.1, 0.1))

	# Capa 3: brazos y viewmodel entero, más lento y blando.
	var res_ap := Springs.vector(arm_pos, arm_vel, ARM_K, ARM_C, delta)
	arm_pos = res_ap[0]
	arm_vel = res_ap[1]
	var res_ar := Springs.vector(arm_rot, arm_rot_vel, ARM_K, ARM_C, delta)
	arm_rot = res_ar[0]
	arm_rot_vel = res_ar[1]
	arm_pos = Vector3(clampf(arm_pos.x, -0.02, 0.02), clampf(arm_pos.y, -0.02, 0.02), clampf(arm_pos.z, -0.02, 0.03))
	arm_rot = Vector3(clampf(arm_rot.x, -0.08, 0.08), 0.0, clampf(arm_rot.z, -0.04, 0.04))
