class_name Springs
extends RefCounted

## Resortes amortiguados con integración estable.
##
## El arma (retroceso, corredera, cargador) y la cámara usan resortes integrados
## con Euler explícito. Con un frame normal eso va bien, pero con un frame largo
## —cargar una textura, guardar una captura, un hitch en Android— ese esquema se
## vuelve inestable y los valores se disparan: el arma y la cámara acababan
## girando sin control (medido: roll de la cámara a 122888°).
##
## Aquí el paso se parte en subpasos de como mucho MAX_STEP segundos, que es
## estable de sobra para los k que usa el juego (hasta 8800 en la corredera).

const MAX_STEP := 0.008  # 8 ms
const MAX_STEPS := 16    # techo: un frame de más de 128 ms no aporta precisión


## Resorte escalar. Devuelve Vector2(posición, velocidad).
static func scalar(pos: float, vel: float, k: float, c: float, delta: float) -> Vector2:
    var steps := clampi(ceili(delta / MAX_STEP), 1, MAX_STEPS)
    var h := delta / float(steps)
    for _i in range(steps):
        vel += (-k * pos - c * vel) * h
        pos += vel * h
    return Vector2(pos, vel)


## Resorte vectorial (3 ejes independientes). Devuelve [posición, velocidad].
static func vector(pos: Vector3, vel: Vector3, k: float, c: float, delta: float) -> Array:
    var steps := clampi(ceili(delta / MAX_STEP), 1, MAX_STEPS)
    var h := delta / float(steps)
    var p := pos
    var v := vel
    for _i in range(steps):
        v += (-k * p - c * v) * h
        p += v * h
    return [p, v]
