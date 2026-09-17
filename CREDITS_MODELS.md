# Créditos de modelos 3D

## 9mm Pistol — Urpo  (ARMA VISIBLE)

- Archivo: `assets/models/glock_urpo.glb` (15,9 MB).
- Fuente: Sketchfab — https://sketchfab.com/3d-models/9mm-pistol-30222f9a59104426ba526a6b20cd7532
- Autor: **Urpo** — https://sketchfab.com/Urpo
- Licencia: **CC-BY 4.0**, declarada en `asset.extras` del propio GLB.
  Atribución: *"9mm Pistol" by Urpo, licensed under CC-BY 4.0, via Sketchfab*.
- La pistola llega ya separada en tres nodos por el autor: `Gun_Slide`,
  `Gun_Body` y `Magazine`. `tools/make_weapon_parts.py` les da a cada uno su
  propio origen y añade los puntos de boca, miras y puerto de expulsión medidos
  sobre la malla. Resultado: el arma es un árbol de piezas rígidas, sin
  esqueleto, y mover una pieza es escribir un `transform`.

Es la MISMA geometría de pistola que trae el asset de 1Matzh de abajo (que la
usa como base), así que la sustitución no cambia el aspecto del arma.

---

## 9mm Pistol | First Person Animations — 1Matzh  (BRAZOS)

- Archivo: `assets/models/full9mm_2k.glb` (38,26 MB).
- Fuente: Sketchfab — https://sketchfab.com/3d-models/9mm-pistol-first-person-animations-c26d7f5aa72f4b01a6da4578caa8f07f
- Autor: **1Matzh** — https://sketchfab.com/1Matzh
- Licencia: **Creative Commons Attribution 4.0 (CC-BY 4.0)**, declarada en
  `asset.extras` del propio GLB (que se conserva) y verificada por API antes de
  integrar. Atribución: *"9mm Pistol | First Person Animations" by 1Matzh,
  licensed under CC-BY 4.0, via Sketchfab*.
- **Cadena de licencia comprobada hasta la malla original**: la pistola es
  `9mm Pistol` de **Urpo** (`30222f9a59104426ba526a6b20cd7532`, CC-BY 4.0) y los
  brazos, `Modern Soldier` de **Blue-Spirit**
  (`358b4fb07f0146cb9b9063342db5897a`, CC-BY 4.0). Acreditar también a ambos.
- Del asset se usan **solo los brazos**: la malla de la pistola que trae dentro
  se apaga en runtime, porque el arma visible es la de Urpo.
- 29 321 triángulos: brazos 6 164 (`Object_0`, antebrazos) + 14 312 (`Object_1`,
  manos con guantes), pistola 8 357 (`Object_2/3/4`). **928 huesos** y **10
  animaciones**: Equip, Idle, Idle_2, Walk, Run, Fire, Reload, Reload_Empty,
  Inspect, Unequip. Materiales con albedo, metallic-roughness y normal.
- Ese esqueleto es SOLO de los brazos: el arma ya no cuelga de él.
- Procesado reproducible con `tools/trim_glb.py` (materiales y texturas
  huérfanas fuera) y `tools/downscale_glb_textures.py` (4096 -> 2048 para el
  perfil Mobile). El skybox de presentación y los ayudantes de apuntado se apagan
  en runtime.
- Escala: la pistola y las manos son coherentes entre sí. En el mismo espacio y
  misma pose, el cociente de anchos manos/arma es **0,96x**
  (101,8 mm de manos / 105,5 mm de arma en hip). Una cifra anterior de "12x" era
  falsa: comparaba espacios distintos y ya no aplica.

---

## Assets evaluados y descartados

Nada de esto está en el repo. Se conserva únicamente como registro de **qué se
midió y por qué se descartó**, para no repetir la busqueda.

- **OWK 19 Pistol 9mm (G19)** — OKgamedev, CC-BY 4.0. Fue la unica arma visible
  hasta sustituirse por el viewmodel completo de 1Matzh. 11 568 tris en 9 piezas
  rigidas; no traia esqueleto ni animaciones a proposito. **Eliminada del repo.**
- **FPS pistol animations** — Cransh, etiquetada CC-BY 4.0 pero **la malla de
  brazos es `FP Arms` de bumstrum, que se publica CC-BY-NC**, y la descripcion
  del propio pack lo dice. Una CC-BY sobre un derivado no puede sustituir la
  licencia del original, asi que **no era utilizable en un producto comercial**.
  Curiosamente el mismo autor publica otra version de esa malla como CC-BY 4.0.
  **Eliminada del repo.**
- **Godot FPS Hands** (addon de Godot, modelos de DJMaesen, CC-BY 4.0): su malla
  de brazos son manos y antebrazos muy cortos — para un encuadre FPS el corte
  queda mas cerca de la camara que el del asset actual. Descartado por forma.
- **Desert Eagle | First Person Animations** (1Matzh, CC-BY 4.0): mismo autor y
  misma calidad de manos, pero es una Desert Eagle y FlowFire es de Glock.
- **GDQuest `godot-4-FPS-arms`**: el mejor aspecto de los gratuitos (3 152 tris,
  8 animaciones) y el mas peligroso. Su LICENSE pone los **modelos** en
  CC-BY-NC-SA 4.0 aunque el codigo sea MIT.
- **bukkbeek/GodotFPS-Template** (MIT, 636 tris) y **NovemberDev** (MIT, 286
  tris): licencia limpia pero **cero texturas** y una decima parte de la
  geometria; serian una regresion visual.
- **wwwriks/wrad-arms** (CC0): la licencia mas limpia de todas, pero es un asset
  retro PSX de 512² y sin animaciones.

