# Créditos de modelos 3D

## G19 Pistol, Game Ready — Rotuma (EL ARMA)

- Archivo: `assets/models/g19_pistol.glb` (10,5 MB). Lleva sus texturas
  embebidas (2048² del arma, 512² de la bala): es la única representación del
  arma en el repo.
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

## RangeShell y mano derecha — geometria original de FlowFire

- `assets/models/range_shell.glb`: carcasa estatica del rango, con suelo, muros,
  columnas, vigas, separadores de lane, luminarias, rodapies, marcaciones de
  distancia y bullet trap visual. Reutiliza y embebe texturas CC0 de
  `CREDITS_TEXTURES.md`; no contiene latas, drywall, cajas, blancos ni metadata
  balistica. Sus colisiones funcionales viven en `scenes/RangeShell.tscn`.
- `assets/models/right_hand.glb`: mano derecha riggeada minima v1, horneada en
  la coordenada del socket `Grip`. Es `ArmsRig` con 20 deform bones (antebrazo,
  muneca, palma, 4x3 dedos, pulgar x3, 2 helpers), 1 malla de 3.360 triangulos
  (falanges rigidas por hueso, peso 1.0) y 1 material de guante. Agarre horneado
  sobre NUESTRA G19, clips Idle/Fire/Reload/ReloadEmpty/Inspect horneados (tiempos =
  mecanica Glock; donante historico arms.glb como referencia). `tools/build_hand_rig.py` es su
  fuente reproducible; no sustituye la Glock ni escribe su mecanica.

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
