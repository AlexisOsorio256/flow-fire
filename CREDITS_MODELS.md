# Créditos de modelos 3D

## OWK 19 Pistol 9mm (G19) — OKgamedev

- Archivo: `assets/models/owk19_pistol.glb` (28.5 MB, md5 `b26c4f52f481aea04475ce35847bf9d4`).
- Fuente: Sketchfab — https://sketchfab.com/3d-models/owk-19-pistol-9mm-g19-3a773b0f46f246dc855742ef413bf4a6
- Autor: **OKgamedev** — https://sketchfab.com/OKgamedev
- Licencia: **Creative Commons Attribution 4.0 (CC-BY 4.0)**, declarada en la metadata `asset.extras` del propio GLB y verificada antes de integrar.
- Atribución a incluir: *"OWK 19 Pistol 9mm (G19)" by OKgamedev, licensed under CC-BY 4.0, via Sketchfab*.
- 11 568 triángulos en 9 piezas rígidas separadas (`Slide`, `Frame`, `SlideLock`, `Barrel`, `Sight`, `Magazine`, `Shell`, `Bullet`, `Trigger`) y 4 materiales PBR (`GlockSlide`, `GlockFrame`, `GlockMag`, `Bullet`) con albedo, metallic-roughness y normal; `GlockSlide` lleva además emisivo.
- **No trae esqueleto ni animaciones a propósito**: la mecánica de FlowFire (recorrido de corredera, gatillo, recámara, cargador, expulsión) es la autoridad y mueve las piezas como nodos rígidos.
- La metadata de licencia se conserva dentro del GLB; no se ha eliminado al copiarlo al repositorio.

---

## FPS pistol animations — Cransh

- Archivo: `assets/models/fps_pistol_arms.glb` (12.39 MB, md5 `8f0dd2f35061ca4442e22e24701fa25d`).
- Fuente: Sketchfab — https://sketchfab.com/3d-models/fps-pistol-animations-0d7a343dcb6f401197a73c91aee93f6d
- Autor: **Cransh** — https://sketchfab.com/ccransh
- Licencia: **Creative Commons Attribution 4.0 (CC-BY 4.0)**, declarada en `asset.extras` del GLB.
- Atribución a incluir: *"FPS pistol animations" by Cransh, licensed under CC-BY 4.0, via Sketchfab*.
- 32 670 triángulos en 4 mallas, **81 huesos**, 5 animaciones propias:
  `FPS_Pistol_Idle`, `FPS_Pistol_Walk`, `FPS_Pistol_Fire`, `FPS_Pistol_Reload_easy`
  y `FPS_Pistol_Reload_full`.
- El rig trae huesos específicos de pistola: **`Rif`** (arma), **`Pmag`** (cargador) y
  **`Trigger`** (gatillo), además de cadenas de dedos completas y huesos de IK.
- Las dos recargas se corresponden con las dos que ya tiene FlowFire: `Reload_easy`
  (conserva la recámara) con la recarga táctica y `Reload_full` (libera la
  corredera) con la de vacío.
- **Optimización aplicada**: se pasó de 114.55 MB a 12.39 MB limitando las
  texturas a 1024 con `gltf-transform resize`, y se podaron 8 nodos con `prune`.
  Comprobado después de optimizar que **la metadata de licencia sigue dentro del
  GLB**: `asset.extras` conserva autor, licencia y fuente, así que la atribución
  viaja con el fichero y no depende sólo de este documento.
- Contiene además una pistola propia (`xd_frame`, 17 818 tris) que **no se
  renderiza**: sirve como referencia de autoría (posición de la empuñadura,
  boca y alza respecto a las manos) para montar la OWK 19. La única pistola
  visible es la OWK 19.
- **Integrado y activo:** este rig proporciona los brazos de dos manos y las
  animaciones del viewmodel. El cuerpo del arma cuelga del hueso `PBody` y el
  cargador del hueso `Pmag`; el montaje usa escala uniforme derivada de la
  empuñadura medida y su encuadre se valida mediante capturas.

El viewmodel activo es, por tanto, la combinación única de `owk19_pistol.glb`
con los brazos y animaciones de `fps_pistol_arms.glb`, sin ningún rig legacy
en runtime.

---

No documentar assets que ya no existan en el repo. Antes de sustituir o añadir un
modelo, comprobar la licencia específica del asset y actualizar este archivo en el
mismo cambio. No asumir que la licencia de un repositorio cubre automáticamente
assets de terceros.
