class_name Springs
extends RefCounted

## Resortes amortiguados con integración estable.
##
## El retroceso del arma (GlockRecoil) y el de la cámara (Player) usan resortes
## integrados con Euler explícito. Con un frame normal eso va bien, pero con un
## frame largo —cargar una textura, guardar una captura, un hitch en Android— ese
## esquema se vuelve inestable y los valores se disparan: el arma y la cámara
## acababan girando sin control (medido: roll de la cámara a 122888°).
##
## Aquí el paso se parte en subpasos de como mucho MAX_STEP segundos. La
## corredera NO usa este integrador: tiene su propio subpaso fijo en Glock.gd
## porque es un resorte mucho mas rapido.

const MAX_STEP := 0.02  # techo absoluto del subpaso
const MAX_STEPS := 96   # techo de subpasos por frame (con 2.7 ms son ~0.26 s)


## Paso máximo estable para un resorte (k, c).
## Hay que resolver las dos escalas: la oscilación (√k) y el amortiguamiento (c).
## Con el arma (k=520, c=18) un paso de 8 ms bastaba para desestabilizar el
## resorte; con el de la corredera (k=4000) el paso tiene que ser mucho mas fino,
## y por eso vive en su propio integrador.
static func _max_step(k: float, c: float) -> float:
    var by_spring := 0.25 / sqrt(maxf(k, 0.0001))
    var by_damping := 0.25 / maxf(c, 0.0001)
    return minf(minf(by_spring, by_damping), MAX_STEP)


## Resorte escalar. Devuelve Vector2(posición, velocidad).
static func scalar(pos: float, vel: float, k: float, c: float, delta: float) -> Vector2:
    var h_max := _max_step(k, c)
    # El tiempo que exceda h_max*MAX_STEPS se descarta a propósito: avanzar un
    # hitch de 1 s de golpe volvería a ser inestable. Mejor perder ese tiempo
    # que dejar que el resorte explote.
    var span := minf(delta, h_max * MAX_STEPS)
    var steps := maxi(1, ceili(span / h_max))
    var h := span / float(steps)
    for _i in range(steps):
        vel += (-k * pos - c * vel) * h
        pos += vel * h
    return Vector2(pos, vel)


## Resorte vectorial (3 ejes independientes). Devuelve [posición, velocidad].
static func vector(pos: Vector3, vel: Vector3, k: float, c: float, delta: float) -> Array:
    var h_max := _max_step(k, c)
    var span := minf(delta, h_max * MAX_STEPS)
    var steps := maxi(1, ceili(span / h_max))
    var h := span / float(steps)
    var p := pos
    var v := vel
    for _i in range(steps):
        v += (-k * p - c * v) * h
        p += v * h
    return [p, v]
