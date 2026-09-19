# FlowFire

Laboratorio FPS centrado en una sola Glock 19: ciclo mecánico, disparo,
proyectil, material, penetración, física, audio y feedback visual. El rango es
un instrumento pequeño de medición, no un mapa de juego.

## Contrato de producción

- Una autoridad por estado y por transformación. `Glock.gd` decide la mecánica;
  los demás scripts la representan o la hacen sonar.
- Una sola ruta de producción. Si falta un asset obligatorio, el arranque falla;
  no hay offsets históricos, piezas procedurales de reserva ni sistemas de
  armas genéricos. El arma y los brazos son obligatorios.
- Los problemas de asset se resuelven en Blender; los de gameplay, física y
  audio en Godot o en las herramientas offline que los producen.
- Los objetos declaran material y geometría. Los números de resistencia viven
  únicamente en `Ballistics.MATERIALS`.
- `CREDITS_MODELS.md`, `CREDITS_TEXTURES.md` y `CREDITS_AUDIO.md` son la fuente
  de atribución; Git conserva los assets y herramientas retirados.

## Arquitectura real

| Responsabilidad | Autoridad |
|---|---|
| Arranque y composición | `scripts/Main.gd` |
| Estado de Glock: munición, recámara, gatillo, corredera, recarga, inspección | `scripts/Glock.gd` |
| Piezas, sockets, escala y movimiento de la malla | `scripts/GlockWeapon.gd` |
| Montaje, pose, ADS, brazos y petición de clips | `scripts/GlockViewmodel.gd` |
| Retroceso rápido del arma y cesión lenta del conjunto | `scripts/GlockRecoil.gd` |
| Huesos humanos: cinco clips horneados | `AnimationPlayer` de `ArmsRig` (asset) |
| Fogonazo, humo y luz de boca | `scripts/WeaponFX.gd` |
| Proyectil, penetración, rebote e impulso | `scripts/Ballistics.gd` |
| Decals, partículas y sonidos de impacto | `scripts/ImpactFX.gd` + `GameAudio` |
| Cargador expulsado y casquillos | `scripts/MagazineDrop.gd`, `scripts/Shell.gd` |
| Arquitectura visual, colisiones de sala y luminarias | `scenes/RangeShell.tscn` |
| Materiales PBR de la sala (texturas externas) | `scripts/RangeShell.gd` |
| Estaciones balísticas, blancos y cuerpos físicos | `scripts/World.gd`, `scripts/Target.gd`, `scripts/Crate.gd` |

La escena principal es `scenes/Main.tscn`. Los autoloads son `GameAudio`,
`ImpactFX` y `Ballistics`. El renderer es Mobile y la física es Jolt.

## Glock 19: referencia y asset

La referencia física es una Glock 19 Gen5 stock: 185 × 128 × 30 mm, cargador
estándar de 15 cartuchos, recorrido de disparador aproximado de 12,5 mm y
recorrido de corredera de 39 mm. Esos datos no se modifican para hacerlos
coincidir con la malla.

El `g19_pistol.glb` canónico es una aproximación visual: mide aproximadamente
174 mm de largo, 127 mm de alto y 31 mm de ancho. Godot la importa en metros,
valida ese contrato y mantiene escala 1; no la estira ni corrige sus orígenes en
runtime. La diferencia de largo frente a la referencia real queda declarada,
no escondida.

Su árbol obligatorio es:

```text
Glock
├── Frame
├── Slide
├── Barrel
├── Trigger
├── Magazine
├── Muzzle
├── EjectionPort
├── SightRear
├── SightFront
├── Grip
└── Magwell
```

`Muzzle` cuelga de `Barrel`; `Grip` y `Magwell` de `Frame`; `EjectionPort`,
`SightRear` y `SightFront` de `Slide`. Si falta una pieza o un padre es
incorrecto, `GlockWeapon.build()` devuelve error y el viewmodel no arranca.
El pivote de retroceso sale de `Grip`.

El GLB **no lleva ninguna imagen dentro**: es geometría con un material y sus
texturas son los `assets/models/g19_pistol_Image_*.png` que el importador
extrajo y que hoy son la fuente única de los mapas del arma.

La Glock no está en un esqueleto. `Slide`, `Barrel`, `Trigger` y `Magazine` son
piezas rígidas con transform propio. La corredera recorre 39 mm, el cañón
retrocede inicialmente y luego cae, el gatillo gira sobre su pasador y el
cargador sale por su eje medido.

## Brazos y viewmodel

El viewmodel es deliberadamente mínimo:

```text
Viewmodel
└── PoseRoot              cadera / ADS / sprint / bob / sway / respiración
    └── BodyGive          cesión lenta del conjunto (GlockRecoil.give_*)
        ├── ArmsRig       fps_arms.glb
        └── WeaponGrip
            └── WeaponSocket   retroceso: única transformación del arma
                └── Weapon
```

Los brazos son un único asset de producción, `assets/models/fps_arms.glb`, y son
**obligatorios**: si falta, el viewmodel no arranca. Medido sobre el GLB y
comprobado por `tools/check_weapon.tscn`:

| qué | valor |
|---|---|
| mallas | 2 (brazo y mano) |
| triángulos | 13.728 |
| materiales | 2 (`FPS_Arm`, `FPS_Hand`), con baseColor, metallicRoughness y normal |
| texturas | 6, todas 1024²; Godot las extrae a `fps_arms_FPS_*.png` al importar |
| huesos | 42, todos deform, sin IK ni helpers, con nombres legibles (`forearm.R`, `palm.L`…) |
| clips | `Idle` 3,00 s · `Fire` 0,26 s · `Reload` 2,10 s · `ReloadEmpty` 2,35 s · `Inspect` 2,00 s |
| tamaño | 8,0 MB |

Su origen, licencia y builder están en `CREDITS_MODELS.md`; el builder
reproducible es `tools/build_arms.py` (necesita el donante de BAMEN, que **no**
está en el repo y es **CC-BY-4.0**, o sea que **exige atribución**: la cadena de
crédito que pide el autor está literal en `CREDITS_MODELS.md`).

**El asset se autora en el espacio del arma** (el mismo sistema que
`g19_pistol.glb`: +Y arriba, −Z al morro, origen en la raíz del arma) con la mano
derecha ya agarrando la empuñadura. Por eso no hay calibración en runtime:
`mount_arms()` iguala la raíz del brazo a la del arma con **una** operación
medida, y `GRIP_POS` / `GRIP_ROT` siguen siendo `(0,0,0)`. Cambiar la malla del
brazo no obliga a tocar `GlockViewmodel.gd`.

**Los brazos no escriben el transform del arma.** `ArmsRig` cuelga de
`BodyGive`, así que recibe la cesión lenta del conjunto pero **no** el retroceso
rápido: el arma cabecea dentro del agarre, que es lo que hay que leer.
`WeaponSocket` sigue siendo la única autoridad del retroceso completo.

**El `AnimationPlayer` solo anima huesos humanos y no decide nada.** Reproduce
cinco clips —`Idle`, `Fire`, `Reload`, `ReloadEmpty`, `Inspect`— y quien los pide
es `Glock.gd` en sus propios hitos, los mismos que ya mueven la corredera, el
gatillo y el cargador. No hay `HandManager`, ni `ArmController`, ni IK, ni
retarget, ni temporizadores paralelos: la recarga y la inspección comparten
reloj con la mecánica porque cada clip dura exactamente lo que dura su hito.

No hay dos manos en el encuadre de tiro: la mano derecha agarra y el brazo
izquierdo descansa fuera de cuadro. La mano izquierda **sí** entra en
`Reload`, `ReloadEmpty` e `Inspect`, y llega al brocal y a la corredera en los
mismos instantes en que la mecánica llega allí.

## Rango de medición

`range_shell.glb` es sólo presentación estática: suelo, paredes, techo,
columnas, vigas, canaletas, luminarias, marcaciones y bullet trap. **No tiene
separadores de calle ni mamparas**: se quitaron a petición del dueño del repo
("no quiero que estén los fierros, debe estar sin eso para moverme por donde yo
quiero"). El rango es un pasillo abierto que se recorre entero.
Tiene pocas mallas y siete materiales PBR **sin una sola imagen dentro**: el GLB
es geometría con ranuras de material con nombre
(`Range_Concrete_Brushed`, `Range_Concrete_Floor`, `Range_Concrete_Wall`,
`Range_Luminaire`, `Range_Markings`, `Range_Oak_Trim`, `Range_Painted_Metal`) y
solo `baseColorFactor` como respaldo. Las texturas PBR reales son externas
(Poly Haven CC0, `CREDITS_TEXTURES.md`) y las enchufa `scripts/RangeShell.gd` al
arrancar, material por material. No contiene latas, cajas, drywall, blancos ni
metadatos balísticos. Sus colisiones, ReflectionProbe y luminarias viven en
`scenes/RangeShell.tscn`.

`World.gd` conserva únicamente las estaciones funcionales:

Distancias medidas sobre `World.gd` (la línea de tiro es z = 0):

- mesa de cargadores al puesto: **1,4 m** — 4 cargadores físicos de 15, única
  fuente de recarga; se regeneran solos porque es un banco de pruebas, no un
  inventario;
- **8–11 m**: barreras, muro de tablones de pino, torre de 4 cajas y bidones;
- **9,5–13,7 m**: latas, de pie sobre el bidón de 6,6 m y en el suelo (el caso
  de prueba de `thin_shell`);
- **14 y 18 m**: paneles de pladur penetrable, con entrada, salida y paso
  visibles;
- **18 m**: 5 blancos de papel;
- **27 m**: 3 placas de acero;
- **35 m**: 3 blancos de papel (agrupación);
- **50 m**: 1 placa de acero (caída y cero).

La sala es interior. `RangeShell.tscn` contiene **12 OmniLight3D de relleno**
distribuidas hasta z = -57 m y **1 SpotLight3D con sombra** sobre el puesto. Las
estaciones de 35 y 50 m quedan dentro de la cobertura del conjunto; no hay sol
atravesando el techo. El ambiente está controlado y la iluminación privada del
viewmodel es tenue: sólo evita que la Glock y los brazos desaparezcan; las luces
del mundo también alcanzan la capa del viewmodel.

## Audio

Los WAV de runtime viven en `assets/audio/`. Las fuentes que reconstruyen
disparos e impactos viven en `downloads/`, ignorado por Git y fuera del
importador de Godot; `assets/audio/source/` conserva únicamente el excerpt de
G36C que todavía usa el Foley de cargador y lleva `.gdignore`. La única sala
es el bus `Range`:

```text
Weapons ─┐
         ├── Range (único AudioEffectReverb) ── Master
World ───┘
```

La topología vive en `default_bus_layout.tres`; `GameAudio.gd` la valida y no
crea buses ni reverb de repuesto en runtime. No se usa +6 dB ni HardLimiter como
sustituto de mezcla. Cada material tiene **su propia grabación** y su procedencia
está en `CREDITS_AUDIO.md`: ningún impacto es un pitch-shift de otro.

Cada sonido corresponde a un evento que existe: el golpe del cargador y de los
casquillos nace del contacto físico, el reset del gatillo es propio, y los
golpes de corredera están ligados a sus umbrales mecánicos. El estampido domina
la mezcla; la mecánica vive por debajo y el casquillo aparece después y en su
sitio del espacio.

El disparo es **fuerte a propósito y por medida**: los cinco WAV tienen cresta
de 13,5–17,0 dB (un disparo real tiene cuerpo, no sólo pico), RMS de −14,7 a
−17,8 dBFS, y su ataque de 40 ms es idéntico en los cinco (dispersión 0,00 dB,
para que ningún tiro suene flojo). En la mezcla el estampido queda **13,7–17,8
dB por encima del impacto más fuerte** y es el pico más alto del proyecto.

**Headroom, medido en vez de supuesto.** A la cadencia máxima (~13 tiros/s) se
solapan unos cinco estampidos de 382 ms. Sumando los WAV reales con su ganancia
de mezcla, **alineados y sin decorrelación** (o sea, el caso peor absoluto,
porque en el juego el tono varía ±3,5 % y los picos no suman en fase):

```text
una sola voz ...................... pico  -7,62 dBFS
5 voces a 7 tiros/s ............... pico  -5,83 dBFS
5 voces a 13 tiros/s .............. pico  -4,48 dBFS   muestras al tope: 0
```

La suma seca se queda 4,5 dB por debajo del techo incluso en el peor caso
posible, así que **no hay recorte en el estampido mismo**. El bus `Range` añade
reverb después, que es lo único que puede acercar ese pico al techo; por eso el
`Master` NO lleva limitador: el contrato prohíbe el HardLimiter como sustituto
de mezcla y, medido, no hace falta. Si algún día hiciera falta, el sitio es
`default_bus_layout.tres`, no los WAV.

## Balística y física

`Ballistics.gd` es la única autoridad de:

```text
material + geometría + velocidad
→ penetración → velocidad de salida → impulso p_entrada - p_salida
```

La salida usa la forma de colisión que recibió el impacto. Una lata o un bidón
fino declara `thin_shell` y `wall_thickness`: se atraviesan sus dos paredes,
no el diámetro completo del cilindro. Una caja hueca está formada por seis
paneles reales; cada panel puede producir su propia entrada/salida y Jolt aporta
el torque por el punto de impacto. `Target` y `Crate` no inventan callbacks de
balística.

La tabla única mantiene separados `steel`, `aluminum`, `gypsum`, `pine`,
`paper` y `concrete`. ImpactFX conserva perfil, decal y partículas distintos para
cada uno, y audio propio para **acero, aluminio, pino, yeso y hormigón**. El
`paper` es la única excepción y está declarada: reutiliza la muestra del pino a
−10 dB, porque queda fuera de los materiales que el laboratorio pide diferenciar
y a 18 m lo que domina es la llegada del proyectil (`CREDITS_AUDIO.md`).

El proyectil nace en `Muzzle`, alineado con el ánima; fogonazo y humo usan la
misma dirección. El cero de miras es paralelo y explícito. La dispersión es
gaussiana, mecánica y con media cero: `SHOT_DISPERSION_SIGMA = 1,6 mrad` por
eje; se puede poner en cero para una comprobación.

## Herramientas y verificación

Las herramientas protegen preguntas objetivas, no una apariencia ceremonial:

- `tools/frame_probe.gd` + `.tscn`: imprime en JSON la transformación real de
  cada nodo del viewmodel en cada estado (cadera, ADS, recarga por hitos,
  inspección, pico de retroceso, sprint). Es la verdad del encuadre para el
  banco de Blender: sin esto el banco certifica una pose que el juego no dibuja.
- `tools/bench_arms.py`: **banco obligatorio antes del runtime**. Coloca la
  Glock y los brazos en el encuadre real (sacado del probe) y renderiza cadera,
  ADS, recarga, inspección y pico de retroceso desde el ojo y desde órbita
  sobre la empuñadura. Un AABB no certifica un brazo; una captura sí.
  **Sus vistas de órbita sobre la empuñadura son la autoridad para juzgar el
  agarre; su vista `eye` NO lo es**: reproduce el encuadre y la orientación del
  juego (con `--gunspace 1`, que es el valor por defecto, porque el importador
  glTF mete los assets en `(x, -z, y)`), pero queda un desplazamiento vertical
  residual de ~0,3 de cuadro respecto al juego, así que para juzgar el encuadre
  final manda la captura real (`tools/captura.sh`).
- `tools/build_arms.py`: reconstruye `assets/models/fps_arms.glb` en Blender.
- `tools/build_range_shell.py`: reconstruye la arquitectura del rango (geometría
  con UV a densidad física, sin texturas dentro del GLB).
- `tools/medir.sh` + `tools/bench_render.gd`: frame time REAL del render (delta
  entre frames con vsync off), con `--view=WxH` para medir a 1080p en un
  viewport interno, y `--skin=0` para apagar sólo los brazos y poder atribuirles
  un coste (dos pasadas del mismo build, no un número de otra máquina).
- `tools/captura.sh` + `tools/shot.gd`: el ÚNICO capturador. Guarda frames de
  una acción concreta, nombrados por su tiempo de juego real en ms, y admite
  cámara lenta (`--time-scale`).
- `tools/review_contact_sheet.py`: monta esos frames en una sola hoja de
  contacto por acción para mirarlos de una vez.
- `tools/check_weapon.tscn`: piezas obligatorias, contratos de escala,
  referencia mecánica de la Glock y contrato completo de los brazos (clips, sus
  duraciones, esqueleto sin huesos de autoría, raíz del brazo sobre la del
  arma, presupuesto de triángulos).
- `tools/check_reload.tscn`: la mesa de cargadores no se gasta si el arma
  rechaza la recarga, y se regenera sola.
- `tools/check_slide_lock.tscn`: el bloqueo de corredera es VISIBLE (39 mm y la
  ventana de expulsión abierta), no sólo correcto en el estado interno.
- `tools/check_range_shell.tscn`: pocas mallas/materiales, dimensiones del
  rango y separación de objetos funcionales.
- `tools/process_audio.sh`: procesamiento offline y medición de duración, peak,
  RMS, cresta y clipping. Los disparos y los impactos tienen sus propios
  constructores y este script no los toca.
- `tools/build_shot_real.py`: reconstruye los cinco disparos desde cinco
  grabaciones reales distintas (HPF 35 Hz → low-shelf 200 Hz por toma → pico
  −0,5 dBFS → recorte común de ataque). Idempotente.
- `tools/measure_shots.py`: mide la familia de disparos contra sus criterios
  (cresta 12–18 dB, RMS ≥ −18 dBFS, energía en 120–400 Hz y 400–1 kHz, cola que
  decae) para que "suena flojo" no sea una opinión.
- `tools/build_impacts.py` / `tools/measure_impacts.py`: reconstruyen y miden los
  seis impactos, uno por material y por grabación distinta.

Las fuentes que los builders de audio necesitan de verdad son **siete MP3 de
grabación y cuatro WAV de impacto**: los archivos grandes de `downloads/`
(la librería completa de sonido de armas, los volcados de investigación) no hacen
falta para reconstruir nada y se han borrado. Comprobado después del barrido:
reejecutar los dos builders da los mismos WAV, byte a byte.

De los builders de assets, los dos de audio están verificados
**reejecutándolos y comparando bytes**: los cinco `shot_*.wav` y los seis
`impact_*.wav` + `ricochet.wav` salen idénticos byte a byte, así que son
reconstrucciones de verdad y no andamiaje de migración. Además imprimen su tabla
de medidas al construir, para que "suena flojo" no sea una opinión. Los de
brazos y rango no se han reejecutado byte a byte en esta pasada.
- `tools/make_weapon_sounds.py`: sintetiza el Foley que no existe grabado
  (reset del gatillo, caída del cargador, roce del brocal, retén).

Los checks estructurales se pueden ejecutar con `godot --headless --path .`.
La revisión visual se hace en una ventana real de Godot; un PNG vacío o un
inspector headless no certifica un viewmodel.

### Rendimiento medido

`tools/bench_render.gd` a 1080p en el viewport interno, 120 frames tras 40 de
calentamiento, en la máquina de prueba (Intel HD 520), dos pasadas del MISMO
build para poder atribuirle un coste a los brazos:

```text
build actual      46,47 ms/frame  p50 46,67  draws 166  prims 114.768
sin brazos        47,88 ms/frame  p50 48,17  draws 162  prims  87.312  (--skin=0)

antes de limpiar el rango
brazos de BAMEN   55,49 ms/frame  p50 55,56  draws 181  prims 125.420
sin brazos        51,91 ms/frame  p50 51,39  draws 177  prims  97.964
```

Dos lecturas, y la primera es la que importa: **quitar los separadores de acero
del rango bajó el frame time de 55,5 a 46,5 ms (−14%)**, y eso paga de sobra las
once luminarias (antes eran siete y solo llegaban a 22 m) y los brazos nuevos. La
segunda: con los brazos y sin ellos la diferencia es de 1,4 ms **y de signo
contrario al esperado**, o sea que hoy el coste de los brazos está por debajo del
ruido entre pasadas. La cifra de +3,6 ms que se midió con el rango sucio era real
entonces; con el rango limpio ya no se puede reproducir, y decirlo es más honesto
que seguir citándola.

Lo que sí es sólido: los brazos añaden **+27.456 primitivas y +4 draw calls**
(13.728 triángulos, 2 materiales, 6 texturas de 1K). Si algún día hay que
recortar, lo primero es la resolución de las texturas (1K → 512 en brazos, que
ocupan menos del 15% del alto de cuadro), no la geometría de la mano.

Para regenerar los assets Blender:

```text
blender --background --python tools/build_range_shell.py   # carcasa del rango
blender --background --python tools/build_arms.py          # brazos (necesita el donante)
```

## Fuera de alcance

Multijugador, lobby, mapa, controles Android finales, vida/puntuación de
blancos, dos manos visibles en el encuadre de tiro, IK y más de una arma.

FlowFire busca más realidad con menos arquitectura: una Glock bien montada, dos
brazos que la agarran como una persona, un rango legible y una cadena
física/audiovisual que se pueda seguir sin buscar quién manda.
