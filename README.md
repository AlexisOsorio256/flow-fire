# FlowFire

Laboratorio FPS centrado en una sola Glock 19: ciclo mecánico, disparo,
proyectil, material, penetración, física, audio y feedback visual. El rango es
un instrumento pequeño de medición, no un mapa de juego.

## Contrato de producción

- Una autoridad por estado y por transformación. `Glock.gd` decide la mecánica;
  los demás scripts la representan o la hacen sonar.
- Una sola ruta de producción. Si falta un asset obligatorio, el arranque falla;
  no hay offsets históricos, piezas procedurales de reserva ni sistemas de
  armas genéricos.
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
| Montaje, pose, ADS y mano | `scripts/GlockViewmodel.gd` |
| Retroceso rápido del arma y cesión lenta del conjunto | `scripts/GlockRecoil.gd` |
| Fogonazo, humo y luz de boca | `scripts/WeaponFX.gd` |
| Proyectil, penetración, rebote e impulso | `scripts/Ballistics.gd` |
| Decals, partículas y sonidos de impacto | `scripts/ImpactFX.gd` + `GameAudio` |
| Cargador expulsado y casquillos | `scripts/MagazineDrop.gd`, `scripts/Shell.gd` |
| Arquitectura visual, colisiones de sala y luminarias | `scenes/RangeShell.tscn` + `assets/models/range_shell.glb` |
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

La Glock no está en un esqueleto. `Slide`, `Barrel`, `Trigger` y `Magazine`
son piezas rígidas con transform propio. La corredera recorre 39 mm, el cañón
retrocede inicialmente y luego cae, el gatillo gira sobre su pasador y el
cargador sale por su eje medido.

## Mano y viewmodel

El rig es deliberadamente mínimo (5 clips horneados):

```text
BodyGive
├── RightHand       right_hand.glb: ArmsRig 20 huesos, 1 mesh 3.360 tris, 1 material
└── WeaponGrip
    └── WeaponSocket
        └── Glock
```

`right_hand.glb` es mano derecha + antebrazo/manga con 20 deform bones, pose
de agarre horneada sobre el `Grip` de NUESTRA Glock (falanges rígidas, un hueso
por segmento) y 5 clips horneados Idle/Fire/Reload/ReloadEmpty/Inspect (tiempos =
linea mecanica; la pose gruesa la pone el codigo, los huesos el microgesto). La mano no escribe ningún transform del arma; `WeaponSocket`
aplica el retroceso rápido y `BodyGive` la cesión lenta (la mano RESISTE: el
arma cabecea rápido dentro del agarre y el conjunto cede después). No hay mano
izquierda, IK ni retarget en runtime: los 5 clips van horneados en el GLB y
`GlockViewmodel` los dispara (Fire al tiro, Reload/Empty al recargar, Inspect
a F). Durante la recarga el cargador puede moverse solo:
la mecánica visible sigue siendo coherente y no se inventan Foley de manos
inexistentes.

## Rango de medición

`range_shell.glb` es sólo presentación estática: suelo, paredes, techo,
columnas, vigas, separadores, canaletas, luminarias, marcaciones y bullet trap.
Tiene pocas mallas y materiales PBR embebidos; no contiene latas, cajas,
drywall, blancos ni metadatos balísticos. Sus colisiones, ReflectionProbe y
luminarias viven en `scenes/RangeShell.tscn`.

`World.gd` conserva únicamente las estaciones funcionales:

- mesa al puesto: 4 cargadores físicos de 15 (única fuente de recarga);
- cerca de 5 m: latas y objetos ligeros;
- 10–15 m: madera, cajas, bidones y drywall penetrable;
- 18 m: papel;
- 27 m: acero y ángulos;
- 35 m: agrupación;
- 50 m: caída y cero.

La sala es interior. Las luminarias de `RangeShell.tscn` son la fuente directa,
el ambiente está controlado y no hay sol atravesando el techo. La iluminación
privada del viewmodel es tenue y sólo evita que la Glock desaparezca; las luces
del mundo también alcanzan la capa del arma.

## Audio

Los WAV hero son secos y los masters permanecen fuera del importador en
`assets/audio/source/`. La única sala es el bus `Range`:

```text
Weapons ─┐
         ├── Range (único AudioEffectReverb) ── Master
World ───┘
```

La topología vive en `default_bus_layout.tres`; `GameAudio.gd` la valida y no
crea buses ni reverb de repuesto en runtime. No se usa +6 dB ni HardLimiter como
sustituto de mezcla. El aluminio tiene `impact_aluminum.wav`, un derivado PCM
offline más brillante y más bajo que el acero, no un pitch hack en runtime.

Cada sonido corresponde a un evento que existe: el golpe del cargador y de los
casquillos nace del contacto físico, el reset del gatillo es propio, y los
golpes de corredera están ligados a sus umbrales mecánicos. No se añaden manos,
ropa ni rebotes pregrabados.

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
`paper` y `concrete`. ImpactFX conserva perfiles, decals, partículas y audio
distintos para esos materiales.

El proyectil nace en `Muzzle`, alineado con el ánima; fogonazo y humo usan la
misma dirección. El cero de miras es paralelo y explícito. La dispersión es
gaussiana, mecánica y con media cero: `SHOT_DISPERSION_SIGMA = 1,6 mrad` por
eje; se puede poner en cero para una comprobación.

## Herramientas y verificación

Las herramientas protegen preguntas objetivas, no una apariencia ceremonial:

- `tools/build_range_assets.py`: reconstruye en Blender el shell.
- `tools/build_hand_rig.py`: reconstruye en Blender la mano riggeada (20 huesos, 5 clips).
- `tools/check_weapon.tscn`: piezas obligatorias, contratos de escala y
  referencia mecánica de la Glock, incluida la mano.
- `tools/check_range_shell.tscn`: pocas mallas/materiales, dimensiones del
  rango y separación de objetos funcionales.
- `tools/check_fps.tscn`: sonda CPU pequeña para detectar regresiones obvias.
- `tools/review_contact_sheet.py`: ejecuta acciones reales (`fire`, `ads`,
  `reload`, `inspect`, `pen`, `steel`, `can`, etc.) y cuenta la señal
  `shot_fired`; las capturas sólo son evidencia local y no se versionan.
- `tools/process_audio.sh` y `tools/build_shot.py`: procesamiento offline y
  medición de duración, peak, RMS, cresta y clipping.

Los checks estructurales se pueden ejecutar con `godot --headless --path .`.
La revisión visual se hace en una ventana real de Godot; un PNG vacío o un
inspector headless no certifica un viewmodel.

Para regenerar los dos assets Blender:

```text
blender --background --python tools/build_range_assets.py  # shell
blender --background --python tools/build_hand_rig.py      # mano riggeada
```

## Fuera de alcance

Multijugador, lobby, mapa, controles Android finales, vida/puntuación de
blancos, mano izquierda, rigs complejos y más de una arma.

FlowFire busca más realidad con menos arquitectura: una Glock bien montada,
un rango legible y una cadena física/audiovisual que se pueda seguir sin
buscar quién manda.
