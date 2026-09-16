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

- Archivo: `assets/models/fps_pistol_arms.glb` (7.61 MB, md5 `96ba4cb2911339728a05c521fdd07227`).
- Fuente: Sketchfab — https://sketchfab.com/3d-models/fps-pistol-animations-0d7a343dcb6f401197a73c91aee93f6d
- Autor: **Cransh** — https://sketchfab.com/ccransh
- Licencia: **Creative Commons Attribution 4.0 (CC-BY 4.0)**, declarada en `asset.extras` del GLB.
- Atribución a incluir: *"FPS pistol animations" by Cransh, licensed under CC-BY 4.0, via Sketchfab*.
- **Atribución pendiente de aclarar:** la malla de brazos (`arms_arms_0`, 8 193
  vértices) coincide en recuento con **"FP Arms" de bumstrum (DJMaesen)**, que
  ese autor publica como **CC-BY-NC** (*no commercial*), y el propio Cransh
  acredita "Hands – FP Arms by @bumstrum". El pack se distribuye como CC-BY 4.0
  y una licencia CC concedida es irrevocable, pero **el proyecto prohíbe assets
  NC**, así que esto hay que resolverlo antes de un lanzamiento comercial
  (preguntar a Cransh/bumstrum, o sustituir la malla de brazos). Mientras tanto
  se acredita también a bumstrum: *"FP Arms" by bumstrum (DJMaesen)*.
- 32 670 triángulos en 4 mallas, de los que **sólo se dibujan 26 420**: la
  pistola `xd_frame` (17 818 tris) nunca se renderiza. **81 huesos**, 5 animaciones propias:
  `FPS_Pistol_Idle`, `FPS_Pistol_Walk`, `FPS_Pistol_Fire`, `FPS_Pistol_Reload_easy`
  y `FPS_Pistol_Reload_full`.
- El rig trae huesos específicos de pistola: **`Rif`** (arma), **`Pmag`** (cargador) y
  **`Trigger`** (gatillo), además de cadenas de dedos completas y huesos de IK.
- Las dos recargas se corresponden con las dos que ya tiene FlowFire: `Reload_easy`
  (conserva la recámara) con la recarga táctica y `Reload_full` (libera la
  corredera) con la de vacío.
- Contiene además una pistola propia (`xd_frame`, 17 818 tris) que **no se
  renderiza**: sirve como referencia de autoría (posición de la empuñadura,
  boca y alza respecto a las manos) para montar la OWK 19. La única pistola
  visible es la OWK 19.
- **Integrado y activo:** este rig proporciona los brazos de dos manos y las
  animaciones del viewmodel. El cuerpo del arma cuelga del hueso `PBody` y el
  cargador del hueso `Pmag`; el montaje usa escala uniforme derivada de la
  empuñadura medida y su encuadre se valida con `--armdiag`.

### Cómo se produjo este GLB (reproducible)

El asset original declaraba sus materiales con **`KHR_materials_pbrSpecularGlossiness`**,
una extensión **deprecada que Godot 4 no implementa**. El importador caía al
bloque `pbrMetallicRoughness`, que en este fichero venía **vacío**: albedo
blanco, `metallic 1.0`, y la textura de oclusión usada como metallic-roughness.
Resultado: **la textura difusa del autor (guantes de cuero, costuras, tejido) se
descartaba entera** y los brazos se dibujaban como geometría gris plana — de ahí
que el código los pintara a mano de negro.

Conversión aplicada, en este orden:

```bash
gltf-transform metalrough original.glb step1.glb   # specular-glossiness -> metallic-roughness
# cirugía: quita KHR_materials_specular/ior, da un material sin texturas a las
# 3 mallas xd_frame (patrón de medida, nunca dibujadas) y poda sus 4 texturas
gltf-transform prune step1.glb fps_pistol_arms.glb # compacta el buffer: 13.03 -> 7.61 MB
```

Comprobado después: **la metadata de licencia sigue dentro del GLB**
(`asset.extras` conserva autor, licencia y fuente, así que la atribución viaja
con el fichero y no depende sólo de este documento), las **5 animaciones
conservan sus duraciones exactas** (1.983 / 0.650 / 0.233 / 1.317 / 1.650 s) y
los 81 huesos. Godot extrae las 4 imágenes embebidas a `fps_pistol_arms_0..3.png`
(`gltf/embedded_image_handling=1`); las 3 texturas de la pistola de referencia
se eliminaron con el `prune`.

El viewmodel activo es, por tanto, la combinación única de `owk19_pistol.glb`
con los brazos y animaciones de `fps_pistol_arms.glb`, sin ningún rig legacy
en runtime.

---

No documentar assets que ya no existan en el repo. Antes de sustituir o añadir un
modelo, comprobar la licencia específica del asset y actualizar este archivo en el
mismo cambio. No asumir que la licencia de un repositorio cubre automáticamente
assets de terceros.
