# Créditos de modelos 3D

## G19 Pistol, Game Ready — Rotuma (EL ARMA)

- Archivo: `assets/models/g19_pistol.glb` (321 KB). **No lleva ninguna imagen
  dentro**: es geometria con un solo material. Sus texturas son externas, en los
  `assets/models/g19_pistol_Image_*.png` que el importador extrajo del archivo
  original del autor (2048² del arma, 512² de la bala) y que hoy son la fuente
  unica de los mapas del arma. Se quitaron del GLB porque eran las MISMAS
  imagenes duplicadas (10 MB) y el runtime las carga del disco.
- Fuente: Sketchfab —
  https://sketchfab.com/3d-models/g19-pistol-game-ready-free-version-e3412d9803f04bdaa97ad9b68ed665d7
- Autor: **Rotuma** (Nathan Nilsen) — https://sketchfab.com/Rotuma
- Licencia: **CC-BY 4.0**, la que trae el `license.txt` del propio autor.
  Atribución literal:
  *This work is based on "G19 Pistol, Game Ready, Free version"
  (https://sketchfab.com/3d-models/g19-pistol-game-ready-free-version-e3412d9803f04bdaa97ad9b68ed665d7)
  by Rotuma (https://sketchfab.com/Rotuma) licensed under CC-BY-4.0
  (http://creativecommons.org/licenses/by/4.0/)*
- El archivo del autor trae la pistola **dos veces dentro de una sola malla**:
  una copia armada y otra despiezada, más un cargador de repuesto suelto y tres
  piezas flotantes que son parte del expositor. La herramienta histórica
  `tools/build_g19_parts.py`, en un solo paso de Blender, se quedó con la copia armada, la reparte por islas de
  malla, recorta el gatillo del armazón, reasienta los orígenes (el gatillo
  sobre su pasador, el cargador sobre el brocal, el cañón sobre la recámara),
  endereza el arma al convenio del motor (morro a -Z, arriba +Y, cargador
  cayendo a -Y) y la escala al largo de la malla. El cañón es del autor: no hay
  geometría inventada.
- Medidas del resultado, comprobadas con `tools/check_weapon.gd`: 174,0 mm de
  largo (malla), 127,0 mm de alto, 31,0 mm de ancho y 146,3 mm entre miras.
  REFERENCIA: G19 Gen5 stock (185 x 128 x 30, ~152 mm entre miras, 15 tiros,
  ~12,5 mm de disparador). La malla es aproximacion visual, 11 mm corta; se
  dibuja a su medida en metros y no se estira. Los sockets se leian por AABB
  hasta la canonicalizacion del parrafo siguiente; desde entonces vienen
  dentro del GLB y el runtime solo los lee (Muzzle bajo Barrel).
- El resultado son mallas rígidas —`Frame`, `Slide`, `Magazine`, `Trigger`,
  `Barrel`— sin esqueleto y sin animaciones.
- GLB canonicalizado (2026-09-18, Blender headless desde el propio GLB; la
  herramienta de canonicalización se conserva sólo en la historia):
  arma recentrada (fuera la herencia -19,8 mm en X), `Muzzle` en el centroide
  de la corona del cañón (1,3 mm, lo mide `tools/check_weapon.gd`) colgando de
  `Barrel`, miras sobre la corredera (146,3 mm), `Grip` en el centroide de la
  empuñadura y `Magwell` en la boca del cargador. El arma compensa el
  recentrado moviendo el pivote (`GRIP_POS.x`); el ADS se resuelve solo desde
  las miras. `tools/build_g19_parts.py` cumplió y se retiró al historial de Git
  (el GLB es la fuente canónica).
- Importador en extraccion (`embedded_image_handling=1`): el modo embebido
  BasisU lee el ORM como sRGB y la corredera sale cromada bajo los focos; en
  extraccion el metal sale satinado como el autor. Los `*_Image_*.png` son
  derivados ignorados que el importador regenera, no otra representacion. Ajustes de importacion de esas texturas (disco, los regenera el importador): VRAM + mipmaps en las cuatro; `Image_6` (normal) marcada como normal map.

## Brazos — Drillimpact (LOS BRAZOS)

- Archivo: `assets/models/fps_arms.glb` (2,6 MB). Lleva **1 malla** (`ArmsMesh`,
  **7.056 triangulos**), **1 material** (`Arms`) y **1 textura embebida de 512²**
  (`arms_01`). Esqueleto **deform-only de 47 huesos**; sin IK, sin constraints y
  sin huesos de autoria.
- Contiene **exactamente cinco clips**, con estos nombres y estas duraciones, que
  son las de la mecanica de `scripts/Glock.gd`:

  | clip | duracion | hito mecanico |
  |---|---|---|
  | `Idle` | 3,00 s | bucle de agarre |
  | `Fire` | 0,26 s | latigazo por disparo |
  | `Reload` | 2,10 s | `RELOAD_TOTAL` |
  | `ReloadEmpty` | 2,35 s | `RELOAD_EMPTY_TOTAL` |
  | `Inspect` | 2,00 s | `INSPECT_TOTAL` |

- Fuente del DONANTE: **Drillimpact**, "PSX First Person Arms" —
  https://drillimpact.itch.io/psx-first-person-arms-free. Licencia, textual de la
  pagina del autor: *"License: This asset is released under CC0 (Public
  Domain)."*, confirmada ademas por el autor en los comentarios de la misma
  pagina ("Yes CC0"). **CC0 1.0 Universal**: sin atribucion obligatoria, uso
  comercial permitido. Se le da igualmente, por cortesia.
- El donante original mide 1.176 triangulos, 52 huesos y textura de 512². El
  asset de produccion se construye con `tools/build_arms.py`: quita la malla
  `Icosphere` que el donante trae suelta, quita los cinco huesos que no deforman
  (`camera`, `handIK.*`, `elbowIK.*`), **subdivide Catmull-Clark x1** (1.176 →
  7.056 tris, que es lo que elimina el facetado PSX: subdividir un cilindro
  facetado no inventa detalle, lo redondea), y lo **autora en el espacio del
  arma** con la mano derecha agarrando NUESTRA `g19_pistol.glb`: la posicion del
  puño se mide sobre el tunel de la malla y el brazo se resuelve con IK analitico
  de dos huesos, no a ojo.
- **El donante NO esta en el repo** (`downloads/` esta ignorado por Git). Para
  reconstruir el asset hay que descargar el ZIP de la URL de arriba, descomprimirlo
  en `downloads/models/drillimpact_psx_fps_arms/extracted/` y ejecutar
  `blender --background --python tools/build_arms.py`. El builder aborta con un
  mensaje que dice exactamente eso si falta el donante. No es "reproducible desde
  un repo limpio": es reproducible desde un repo limpio **mas una descarga CC0**.
- Los 7.056 triangulos y la textura de 512² quedan **por debajo del objetivo
  declarado** (8k-20k tris, 1K). Se declara en vez de esconderse: subir a
  subdiv x2 daba 28.224 tris, por encima del techo, y a la escala real del
  viewmodel (la mano ocupa menos del 15% del alto de cuadro) no aportaba lectura.
  Cambiar de nivel es una linea de `tools/build_arms.py` (`--subdiv`).

## RangeShell — geometria original de FlowFire

- `assets/models/range_shell.glb`: carcasa estatica del rango, con suelo, muros,
  columnas, vigas, separadores de lane, luminarias, rodapies, marcaciones de
  distancia y bullet trap visual. **No lleva ninguna imagen dentro**: es
  geometria con siete materiales con nombre (`Range_Concrete_Brushed`,
  `Range_Concrete_Floor`, `Range_Concrete_Wall`, `Range_Luminaire`,
  `Range_Markings`, `Range_Oak_Trim`, `Range_Painted_Metal`) y solo
  `baseColorFactor` como respaldo. Las texturas PBR reales son externas
  (`assets/textures/real/*.jpg`, CC0 de Poly Haven, ver `CREDITS_TEXTURES.md`) y
  las enchufa `scripts/RangeShell.gd` al arrancar, material por material. No
  contiene latas, drywall, cajas, blancos ni metadata balistica. Sus colisiones
  funcionales viven en `scenes/RangeShell.tscn`.

## Retirado del runtime (Git es el museo)

- `assets/models/right_hand.glb`: mano derecha + antebrazo horneados sobre la
  coordenada del socket `Grip`, extraidos del rig CC0 "fps arms (rigged only)" de
  **para** (OpenGameArt, CC0) con `tools/build_hand_rig.py`. **Ya no esta en el
  runtime**: en una captura real el antebrazo quedaba mal orientado y tapaba el
  arma y el fogonazo, asi que se retiro en vez de seguir puliendolo. Su fuente y
  su builder viven en la historia de Git.

## Brazos: que se probo y que se descarto

La eleccion esta razonada, no es "lo primero que cargo". Todo lo de abajo se
comprobo con `curl` y con Blender 4.0.2 headless sobre el archivo descargado,
nunca sobre la ficha del autor.

**Descartado por exigir cuenta (HTTP 401 en `/v3/models/<uid>/download`).** Los
tres candidatos que pedia el encargo eran de Sketchfab y los tres piden login:
`296d30fc705b4dff85c2c8a2d2724e7f` ("FREE [FPS Arms] GameReady - RIGGED",
BAMEN, CC-BY-4.0, 13.728 caras), `e3c42c05b22944e5839deb8e003f0987` ("First
Person arms", DJMaesen) y `bd896167e7ca44f19597d3afe6a8d83f` ("animated
pistol", DJMaesen). Se probaron ademas otras diez referencias de Sketchfab
(Cransh, Tactical_Beard, RafaP, mrgyarmati, ian1518, BIGMACorSomething...): las
diez devuelven 401. Sin cuenta no hay asset, y la regla del proyecto es no usar
cuentas.

**Descartado por licencia o por higiene de rig.**

- `imaginais` "PSX FP Hands Pack": descargable sin cuenta, pero **no declara
  licencia**.
- `aravkp/godot-dungeon-crawler-fps` (`assets/hands/arms_rig.glb`): es una
  redistribucion **byte a byte** del pack de Drillimpact (`arms_01.png` con el
  mismo md5 `34f933b1f88116b7982e7046f7fdb7f4`) y su repositorio **no tiene
  archivo de licencia**: se rechaza como FUENTE, aunque el mismo asset si vale
  desde la pagina del autor.
- `sophixcg` "FPS Arms": sin licencia y con IK y `Copy Rotation` en el rig.
- `teamfuze` "3D Hands": su licencia prohibe redistribuir.
- Rig CC0 "fps arms (rigged only)" de **para** (OpenGameArt): buena malla (8.152
  tris) pero **no esta libre de constraints** (IK en ambos antebrazos y 20
  `COPY_ROTATION` en las falanges), y es el rig del experimento retirado.
- GDQuest `godot-4-FPS-arms`: CC-BY-NC-SA (no comercial) y un solo brazo sin
  materiales. `wrad-arms`: CC0 pero 1.196 tris y cero animaciones.

## Fuera del repo

Ya no se distribuye nada de estos assets; se conserva su atribución porque el
proyecto los usó y cualquiera puede recuperarlos desde Git.

- **Brazos — 1Matzh** (`assets/models/arms.glb`, hasta el commit de congelación).
  "Desert Eagle | First Person Animations" by 1Matzh, licensed under CC-BY 4.0,
  via Sketchfab —
  https://sketchfab.com/3d-models/desert-eagle-first-person-animations-09a213d8510a42d1b747135e85712eff
  El asset original (102 MB) y su poda viven en la historia de Git.
- **Fps Rig — J-Toastie**, CC-BY 3.0 (`fps_rig.glb`, commit `490f22a`).
- **OWK 19 Pistol 9mm (G19) — OKgamedev**, CC-BY 4.0.
- **Desert Eagle — ELIZION**, CC-BY 4.0
  (https://sketchfab.com/3d-models/desert-eagle-cabde59f5cf24effaf80536e35d04e95).
