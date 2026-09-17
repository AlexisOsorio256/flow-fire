class_name GlockRecoil
extends RefCounted

## Retroceso del arma DENTRO de la mano, mas la respuesta de camara (que la
## lleva Player.gd). Una sola autoridad: este resorte mueve el ARMA (huesos
## Weapon_922 y Magazine_924 via GlockViewmodel) y nada mas.
##
## Lo que NO mueve, a proposito:
##   manos/brazos .... el clip Fire ya trae su gesto; antes habia una segunda
##                     capa procedural (`arm_pos`/`arm_rot`) que empujaba TODO
##                     el viewmodel encima de la animacion. Fuera: una autoridad.
##   camara/cuerpo ... Player.gd.
##   corredera ....... Glock.gd (`slide_pos`).
##
## El estado es un resorte de posicion (`pos`, el arma se hunde en la palma)
## mas uno de rotacion (`rot`, cabeceo sobre el pivote del agarre). El
## viewmodel los aplica como UNA transformacion rigida sobre la pose animada
## de Idle: con resorte a cero la transformacion es identidad y el arma queda
## exactamente donde la deja su animacion.

# Impulso de cabeceo del ARMA en el disparo (rad/s). CALIBRADO a 4.2 rad/s:
# la boca sube ~8 grados con pico a ~50 ms.
const MAIN_RECOIL_KICK := 4.2
# Resorte del arma en la mano: k=520/c=18 (zeta 0.39), pico a ~50 ms y
# recuperacion controlada hacia 250 ms.
const WEAPON_K := 520.0
const WEAPON_C := 18.0

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var rot := Vector3.ZERO
var rot_vel := Vector3.ZERO
# Pivote del agarre, en el espacio del hueso padre del arma (lo mide el
# viewmodel con el rig real). Arma y cargador comparten padre y pivote.
var pivot := Vector3.ZERO


## Impulso del disparo: el arma cabecea sobre el agarre y se hunde unos
## milimetros en la palma. Los terminos Y/Z son dispersion simetrica tiro a
## tiro (media cero), no un giro sistematico.
func kick_shot() -> void:
	rot_vel += Vector3(MAIN_RECOIL_KICK + randf() * 0.35, (randf() - 0.5) * 0.2, (randf() - 0.5) * 0.3)
	vel += Vector3(0.0, 0.01, 0.035)


## El cargador asienta en el brocal: fraccion deliberada del retroceso de un
## disparo (~1 grado de pico, no otro latigazo). Va a la MISMA capa del arma,
## no a los brazos: es el arma la que recibe el golpe, en la mano.
func kick_mag_seat() -> void:
	rot_vel.x += 0.45
	vel.z += 0.008


## Pivote de giro del arma, en el espacio de su hueso padre.
func set_wrist_pivot(point: Vector3) -> void:
	pivot = point


## El par WristPivot/RecoilNode queda como pareja fija (traslacion y vuelta):
## efecto neto identidad. Se conservan los nodos porque de ellos cuelga el
## montaje (ArmsMount, GunFrame), no porque el retroceso los necesite.
func apply(wrist: Node3D, node: Node3D) -> void:
	wrist.position = pivot
	wrist.rotation = Vector3.ZERO
	node.position = -pivot
	node.rotation = Vector3.ZERO


func update(delta: float) -> void:
	var res_p := Springs.vector(pos, vel, WEAPON_K, WEAPON_C, delta)
	pos = res_p[0]
	vel = res_p[1]
	var res_r := Springs.vector(rot, rot_vel, WEAPON_K, WEAPON_C, delta)
	rot = res_r[0]
	rot_vel = res_r[1]
	pos = Vector3(clampf(pos.x, -0.04, 0.04), clampf(pos.y, -0.03, 0.03), clampf(pos.z, -0.03, 0.055))
	rot = Vector3(clampf(rot.x, -0.24, 0.24), clampf(rot.y, -0.08, 0.08), clampf(rot.z, -0.1, 0.1))
