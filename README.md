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
| mallas | 1 (`Arms_DJ`) |
| triángulos | 13.536 |
| materiales | 1 (`arms`), con baseColor, metallicRoughness y normal |
| texturas | 3, todas 1024²; Godot las extrae a `fps_arms_arms_*.png` al importar |
| huesos | 51, todos deform, sin IK ni helpers, con nombres legibles (`forearm.R`, `hand.L`…) |
| clips | `Idle` 3,00 s · `Fire` 0,26 s · `Reload` 2,10 s · `ReloadEmpty` 2,35 s · `Inspect` 2,00 s |
| tamaño | 6,2 MB |

Su origen y licencia están en `CREDITS_MODELS.md`. El GLB de producción actual
proviene de DJMaesen, "animated pistol", normalizado y verificado mediante
`tools/build_arms.py` (`VERIFY OK`, `check_weapon.tscn OK`).

**El asset se autora en el espacio del arma** (el mismo sistema que
`g19_pistol.glb`: +Y arriba, −Z al morro, origen en la raíz del arma) con la mano
derecha empuñando y la izquierda acoplada en un agarre firme a dos manos.
Por eso no hay calibración en runtime: `mount_arms()` iguala la raíz del brazo a
la del arma con **una** operación medida, y `GRIP_POS` / `GRIP_ROT` siguen siendo
`(0,0,0)`. Cambiar la malla del brazo no obliga a tocar `GlockViewmodel.gd`.

**Los brazos no escriben el transform del arma.** `ArmsRig` cuelga de
`BodyGive`, así que recibe la cesión lenta del conjunto pero **no** el retroceso
rápido: el arma cabecea dentro del agarre, que es lo que hay que leer.
`WeaponSocket` sigue siendo la única autoridad del retroceso completo.

**El `AnimationPlayer` solo anima huesos humanos y no decide nada.** Reproduce
cinco clips —`Idle`, `Fire`, `Reload`, `ReloadEmpty`, `Inspect`— y quien los pide
es `Glock.gd` en sus propios hitos, que siguen siendo la autoridad de corredera,
gatillo y cargador. No hay `HandManager`, ni `ArmController` ni IK runtime.
Los clips actuales son ventanas retimadas del donante DJMaesen a la duración
total de cada hito. La normalización métrica de armadura en `tools/build_arms.py`
elimina las traslaciones explosivas heredadas de la escala de origen (0.01) y
asegura que las mallas permanezcan a escala humana (~0.60 m) en todo el ciclo.

**Agarre a dos manos y presencia continua**: ambas manos enguantadas permanecen
visibles en el 100% de los fotogramas en todas las acciones (`Idle`, `Fire`,
`Reload`, `ReloadEmpty`, `Inspect`), verificado visualmente en las hojas de
contacto (`captures/review/*_sheet.png`) y en video (`captures/hero_*.mp4`).
La orientación de cadera (`HIP_ROT` en `GlockViewmodel.gd`) expone sutilmente
el flanco superior/derecho del arma, haciendo que la corredera bloqueada a 39 mm
y la recámara abierta sean nítidamente visibles para el jugador.



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
atravesando el techo. El ambiente está controlado. Las luces del mundo excluyen deliberadamente la
capa 13 del viewmodel mediante `light_cull_mask = 4095`; Glock y brazos reciben
únicamente el KEY/FILL tenue definido en `GlockViewmodel.gd`, además del
postproceso fullscreen.

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
de 12,6–14,2 dB (un disparo real tiene cuerpo, no sólo pico), RMS de −13,3 a
−15,1 dBFS, y su ataque de 40 ms es idéntico en los cinco (dispersión 0,00 dB,
para que ningún tiro suene flojo). En la mezcla el estampido domina sobre los
impactos y es el pico más alto del proyecto.


**Headroom, medido en vez de supuesto.** Como prueba de estrés acústica se
simulan hasta ~13 disparos/s y, por tanto, unos cinco estampidos de 382 ms
solapados. **Eso NO describe el funcionamiento semiautomático real con el
gatillo sostenido**; es un límite artificial para comprobar margen de mezcla.
Los WAV se suman alineados y sin decorrelación (caso peor absoluto, porque en el
juego el tono varía y los picos no suman en fase):

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
- `tools/build_arms.py`: constructor oficial de los brazos de producción
  a partir del donante "animated pistol" de DJMaesen. Normaliza la armadura a
  metros, limpia geometrías ajenas, orienta y alinea el túnel de puño y hornea
  los cinco clips a 100 fps en el espacio del arma con la raíz en identidad.
- `tools/build_range_shell.py`: reconstruye la arquitectura del rango (geometría
  con UV a densidad física, sin texturas dentro del GLB).
- `tools/medir.sh` + `tools/bench_render.gd`: frame time REAL del render (delta
  entre frames con vsync off), con `--view=WxH` para medir a 1080p en un
  viewport interno, y `--skin=0` para apagar sólo los brazos y poder atribuirles
  un coste (dos pasadas del mismo build, no un número de otra máquina).
- `tools/captura.sh` + `tools/shot.gd`: el ÚNICO capturador. Guarda frames de
  una acción concreta, nombrados por su tiempo de juego real en ms, y admite
  cámara lenta (`--time-scale`), así como grabación de video real
  (`record_normal` y `record_slow`) con audio sincronizado.
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
  grabaciones reales distintas mediante alineación de transitorio y ecualización
  espectral adaptativa en 5 bandas para homogeneidad tímbrica total (0,00 dB de
  dispersión de ataque a 40 ms, 23–25% de energía en cuerpo 120–400 Hz, cola
  suave y 0 muestras de clipping). Idempotente.
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
calentamiento, en la máquina de prueba (Intel HD 520):

```text
Pass actual (producción)  47,70 ms/frame  p50 47,62  p95 47,92  draws 278  prims 70.236
Baseline anterior         46,47 ms/frame  p50 46,67  p95 49,23  draws 315  prims 125.940
```

Con la geometría completa del rango cubriendo los 72 metros continuos de suelo
(sin vacío negro), 12 luminarias de relleno y el nuevo rig de brazos de 51 huesos,
el render mantiene un presupuesto sumamente limpio: 278 llamadas de dibujo y 70.236
primitivas (un 44% menos de primitivas frente a los 125.940 del baseline original).


Para regenerar los assets Blender:

```text
blender --background --python tools/build_range_shell.py   # carcasa del rango
blender --background --python tools/build_arms.py          # brazos (necesita el donante)
```

## Fuera de alcance

Multijugador, lobby, mapa, controles Android finales, vida/puntuación de
blancos, IK y más de una arma.

FlowFire busca más realidad con menos arquitectura: una Glock bien montada, dos
brazos que la agarran como una persona, un rango legible y una cadena
física/audiovisual que se pueda seguir sin buscar quién manda.

