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
  piezas flotantes que son parte del expositor. `tools/build_g19_parts.py`, en un
  solo paso de Blender, se queda con la copia armada, la reparte por islas de
  malla, recorta el gatillo del armazón, reasienta los orígenes (el gatillo
  sobre su pasador, el cargador sobre el brocal, el cañón sobre la recámara),
  endereza el arma al convenio del motor (morro a -Z, arriba +Y, cargador
  cayendo a -Y) y la escala al largo de la malla. El cañón es del autor: no hay
  geometría inventada.
- Medidas del resultado, comprobadas con `tools/check_weapon.gd`: 174,0 mm de
  largo (malla), 127,0 mm de alto, 31,0 mm de ancho y 146,3 mm entre miras.
  REFERENCIA: G19 Gen5 stock (185 x 128 x 30, ~152 mm entre miras, 15 tiros,
  ~12,5 mm de disparador). La malla es aproximacion visual, 11 mm corta; se
  dibuja a su medida en metros y no se estira. Sockets por AABB pendientes de
  medida manual en Blender; Muzzle ya cuelga de Barrel en runtime.
- El resultado son mallas rígidas —`Frame`, `Slide`, `Magazine`, `Trigger`,
  `Barrel`— sin esqueleto y sin animaciones.
- GLB canonicalizado (2026-09-18, Blender headless desde el propio GLB):
  arma recentrada (fuera la herencia -19,8 mm en X), `Muzzle` en la boca del
  cañón a 0,0 mm colgando de `Barrel`, miras sobre la corredera (146,3 mm),
  `Grip` en el centroide de la empuñadura y `Magwell` en la boca del cargador.
  El arma compensa el recentrado moviendo el pivote (`GRIP_POS.x`); el ADS se
  resuelve solo desde las miras. `tools/build_g19_parts.py` cumplió y se retiró
  al historial de Git (el GLB es la fuente canónica).

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
