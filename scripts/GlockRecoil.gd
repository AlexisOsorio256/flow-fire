class_name GlockRecoil
extends RefCounted

## RETROCESO Y PESO DEL ARMA. Dos capas separadas, nunca sumadas a lo loco:
##
##   1. EL ARMA dentro del agarre -> `pos` + `rot` sobre WeaponSocket.
##      Rapida y corta: la pistola cabecea y se hunde unos milimetros.
##   2. LAS MANOS ceden despues  -> `arm_pos` + `arm_rot` sobre WristPivot.
##      Mas lenta y mas blanda: los brazos absorben. No es un segundo latigazo,
##      es la masa del conjunto.
##
## La camara NO se toca aqui: eso es Player.gd.
##
## PARA QUE EL ARMA PESE MAS, se toca la seccion de abajo y nada mas. Las tres
## palancas que de verdad cambian la sensacion de masa:
##   RECOIL_KICK     cuanto golpea al disparar (impulso)
##   WEAPON_K        cuanto tarda en volver (rigidez; mas bajo = mas pesada)
##   ARM_GIVE        cuanto ceden las manos (mas alto = el agarre absorbe mas)
## El resto son limites de seguridad.

# --- 1. arma ---------------------------------------------------------------
const RECOIL_KICK := 5.10        # grados/s de cabeceo por disparo
const RECOIL_KICK_SIDE := 0.14   # dispersion lateral, simetrica
const WEAPON_K := 520.0          # rigidez del resorte del arma
const WEAPON_C := 18.0           # amortiguacion
const PUSH_HIP := 0.095          # recorrido hacia el tirador (m)
const PUSH_RISE := 0.018         # subida (m)

# --- 2. manos --------------------------------------------------------------
const ARM_GIVE := 0.55           # fraccion del empuje que cede la mano
const ARM_K := 72.0              # mucho mas blando que el arma
const ARM_C := 13.6

# --- limites ---------------------------------------------------------------
const POS_LIMIT := Vector3(0.012, 0.018, 0.020)
const ROT_LIMIT := Vector3(0.22, 0.055, 0.065)
const ARM_POS_LIMIT := Vector3(0.008, 0.008, 0.010)
const ARM_ROT_LIMIT := Vector3(0.035, 0.0, 0.018)

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var rot := Vector3.ZERO
var rot_vel := Vector3.ZERO
var arm_pos := Vector3.ZERO
var arm_vel := Vector3.ZERO
var arm_rot := Vector3.ZERO
var arm_rot_vel := Vector3.ZERO
## Punto de giro del cabeceo, en espacio del WeaponSocket. Lo coloca el
## viewmodel para que el arma rote sobre la empuñadura y no sobre su centro.
var pivot := Vector3.ZERO


## El disparo tiene dos tiempos: primero el arma gira y se hunde en el agarre;
## despues las manos ceden una fraccion.
func kick_shot() -> void:
	rot_vel += Vector3(
		RECOIL_KICK + randf() * 0.30,
		(randf() - 0.5) * RECOIL_KICK_SIDE,
		(randf() - 0.5) * 0.18)
	vel += Vector3((randf() - 0.5) * 0.012, PUSH_RISE, PUSH_HIP + randf() * 0.015)
	arm_vel += Vector3((randf() - 0.5) * 0.010, 0.012, PUSH_HIP * ARM_GIVE)
	arm_rot_vel += Vector3(0.34 + randf() * 0.05, 0.0, (randf() - 0.5) * 0.07)


## Asentar un cargador transmite masa al agarre, pero no parece otro disparo.
func kick_mag_seat() -> void:
	rot_vel.x += 0.24
	vel.z += 0.010
	arm_vel += Vector3(0.0, -0.006, 0.018)
	arm_rot_vel.x -= 0.06


func set_pivot(point: Vector3) -> void:
	pivot = point


func update(delta: float) -> void:
	var rp := Springs.vector(pos, vel, WEAPON_K, WEAPON_C, delta)
	pos = rp[0]
	vel = rp[1]
	var rr := Springs.vector(rot, rot_vel, WEAPON_K, WEAPON_C, delta)
	rot = rr[0]
	rot_vel = rr[1]
	pos = Vector3(clampf(pos.x, -POS_LIMIT.x, POS_LIMIT.x), clampf(pos.y, -POS_LIMIT.y, POS_LIMIT.y), clampf(pos.z, -POS_LIMIT.z, POS_LIMIT.z))
	rot = Vector3(clampf(rot.x, -ROT_LIMIT.x, ROT_LIMIT.x), clampf(rot.y, -ROT_LIMIT.y, ROT_LIMIT.y), clampf(rot.z, -ROT_LIMIT.z, ROT_LIMIT.z))

	var ap := Springs.vector(arm_pos, arm_vel, ARM_K, ARM_C, delta)
	arm_pos = ap[0]
	arm_vel = ap[1]
	var ar := Springs.vector(arm_rot, arm_rot_vel, ARM_K, ARM_C, delta)
	arm_rot = ar[0]
	arm_rot_vel = ar[1]
	arm_pos = Vector3(clampf(arm_pos.x, -ARM_POS_LIMIT.x, ARM_POS_LIMIT.x), clampf(arm_pos.y, -ARM_POS_LIMIT.y, ARM_POS_LIMIT.y), clampf(arm_pos.z, -ARM_POS_LIMIT.z, ARM_POS_LIMIT.z))
	arm_rot = Vector3(clampf(arm_rot.x, -ARM_ROT_LIMIT.x, ARM_ROT_LIMIT.x), 0.0, clampf(arm_rot.z, -ARM_ROT_LIMIT.z, ARM_ROT_LIMIT.z))


## Escribe las dos capas. `wrist` recibe la cesion de los brazos; `socket`
## recibe el cabeceo del arma. Cada nodo tiene UN dueno y solo este metodo
## escribe en ellos.
func apply(wrist: Node3D, socket: Node3D) -> void:
	wrist.position = arm_pos
	wrist.rotation = arm_rot
	var r := Basis.from_euler(rot)
	socket.position = pivot + (r * -pivot) + pos
	socket.basis = r
