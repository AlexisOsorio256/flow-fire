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

## FPS pistol animations — Cransh  ⚠️ NO UTILIZABLE EN PRODUCTO COMERCIAL

- Archivo: `assets/models/fps_pistol_arms.glb` (7.61 MB, md5 `96ba4cb2911339728a05c521fdd07227`).
- Fuente: Sketchfab — https://sketchfab.com/3d-models/fps-pistol-animations-0d7a343dcb6f401197a73c91aee93f6d
- Autor: **Cransh** — https://sketchfab.com/ccransh
- Licencia declarada: **Creative Commons Attribution 4.0 (CC-BY 4.0)**, en `asset.extras` del GLB y en la página.
- **PROBLEMA DE LICENCIA — comprobado, no supuesto.** La descripción de esa misma página dice literalmente: *"Hands - FP Arms by @bumstrum; Pistol - Springfield Armory XD Mod.2 Sub-Compact by @raimeiyonke."* Y `FP Arms` de bumstrum/DJMaesen (https://sketchfab.com/3d-models/8416c380544949bb9b224278819cbe6b) está publicado como **CC Attribution-NonCommercial** (`http://creativecommons.org/licenses/by-nc/4.0/`, requisito literal: *"No commercial use"*), con **14 852 caras**, el mismo recuento que la malla de brazos de este GLB.
- Por qué la etiqueta CC-BY no salva la situación: una licencia CC concedida sobre un derivado no puede sustituir la del original. Cransh relicencia como CC-BY 4.0 algo que aguas arriba es NC. No es un caso aislado: ocurre igual en "Animated FPS hands (rifle animation pack)", "SMG FPS Animations", "FPS Saiga animations" y "FPS Arms remington" (todos citan `@bumstrum`); **no** ocurre en "FPS Animations LowPoly MP5", "FPS animations VSK", "P9 Manny" ni "FPS Silicone gun animations (LP)", que no lo acreditan.
- FlowFire será comercial ⇒ **NC no es aceptable**. Esta malla debe sustituirse antes de un lanzamiento.

### Estado técnico (lo que sí se aprovechó)

- 32 670 triángulos en 4 mallas, de los que **sólo se dibujan 16 304**: la pistola `xd_frame` (17 818 tris) nunca se renderiza. **81 huesos**, 5 animaciones propias: `FPS_Pistol_Idle`, `FPS_Pistol_Walk`, `FPS_Pistol_Fire`, `FPS_Pistol_Reload_easy` y `FPS_Pistol_Reload_full`.
- El rig trae huesos específicos de pistola: **`Rif`** (arma), **`Pmag`** (cargador) y **`Trigger`** (gatillo), además de cadenas de dedos completas, huesos de IK y **cadenas de torsión de antebrazo** (`BoneTwist_01/02/03.L|R`).
- Las dos recargas se corresponden con las dos que ya tiene FlowFire: `Reload_easy` (conserva la recámara) con la recarga táctica y `Reload_full` (libera la corredera) con la de vacío.
- Contiene además una pistola propia (`xd_frame`, 17 818 tris) que **no se renderiza**: sirve como referencia de autoría (posición de la empuñadura, boca y alza respecto a las manos) para montar la OWK 19.

### Defectos geométricos medidos (motivo del reemplazo, además de la licencia)

- **20 bucles de frontera, 1 502 aristas sin cara**: los antebrazos son una cáscara abierta. En ADS se mira el extremo del antebrazo de canto y se ve el corte.
- **Manga corta en proporción al arma**: el tramo hombro→mano mide ~24 cm escalado, cuando un tirador real tiene el hombro a 45-55 cm de la empuñadura. Por eso el hombro entra en encuadre si se quiere que el arma domine.
- La masa de las esquinas inferiores **no son los hombros**: son las cadenas de antebrazo y sus huesos de torsión (`BoneTwist_01.R_013`, 550 vértices, es la región más grande de la malla). Los huesos llamados `Forearm_L/R` sólo llevan ~180 vértices cada uno.
- Reescribir el GLB en Blender para tapar los agujeros **rompe el rig** (la silueta cae a 0,0% y 6 071 vértices acaban detrás de la cámara): el round-trip de Blender 4.0 no conserva bien este asset. Vía descartada con evidencia.

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

Comprobado después: las **5 animaciones conservan sus duraciones exactas**
(1.983 / 0.650 / 0.233 / 1.317 / 1.650 s) y los 81 huesos. Godot extrae las 4
imágenes embebidas a `fps_pistol_arms_0..3.png`
(`gltf/embedded_image_handling=1`); las 3 texturas de la pistola de referencia
se eliminaron con el `prune`.

---

## Candidatos de reemplazo verificados (no integrados)

Los tres tienen licencia **CC-BY 4.0** (comercial permitido, con atribución) y su
cadena de licencia está **comprobada hasta la malla original**, que es lo que
descarta la contaminación NC. Las especificaciones vienen de la API pública
`api.sketchfab.com/v3/models/<uid>`, no de la memoria de nadie.

| # | Asset | Autor | Fuente (UID Sketchfab) | Licencia | Caras | Anims | Cadena verificada |
|---|---|---|---|---|---|---|---|
| 1 | **9mm Pistol \| First Person Animations** | 1Matzh | `c26d7f5aa72f4b01a6da4578caa8f07f` | CC-BY 4.0 | 29 321 | 10 | Pistola `9mm Pistol` de **Urpo** (`30222f9a59104426ba526a6b20cd7532`) = CC-BY 4.0 ✅ · Brazos `Modern Soldier` de **Blue-Spirit** (`358b4fb07f0146cb9b9063342db5897a`) = CC-BY 4.0 ✅ |
| 2 | **Desert Eagle \| First Person Animations** | 1Matzh | `09a213d8510a42d1b747135e85712eff` | CC-BY 4.0 | 37 636 | 9 | Pistola `Desert Eagle` de **ELIZION** (`cabde59f5cf24effaf80536e35d04e95`) = CC-BY 4.0 ✅ · Brazos `Division Agent (Rigged)` de **Blue-Spirit** (`6c6645e00f6446339dd5ace4a63e49e3`) = CC-BY 4.0 ✅ |
| 3 | **heavy pistol animated** | DJMaesen (bumstrum) | `b7c78c533ced40cd986c44594b778ed6` | CC-BY 4.0 | 19 903 | 1 | Autor directo. ⚠️ El mismo autor publica `FP Arms` y `FPS Arms gloved` como **NC**; la descripción dice que trae *"gloved hands skin for arms mesh"* sin decir de cuál de sus mallas sale. **Riesgo abierto: hay que comprobar la malla descargada antes de usarla.** |

Notas de integración para el candidato 1 (el mejor situado): 10 animaciones, dos
manos enguantadas en agarre de pistola, y sus dos mallas de origen son CC-BY. Su
punto débil es que el autor avisa de que *"the textures are not fully organized"*.

**Ninguno se ha integrado todavía.** Bloqueo real: el endpoint de descarga de
Sketchfab (`/v3/models/<uid>/download`) devuelve HTTP 401 sin cuenta autenticada,
y este entorno no la tiene, así que no se ha podido descargar ni inspeccionar
ninguno localmente. Según el criterio anti-alucinación del proyecto, un asset no
se integra sin haber inspeccionado el archivo. La alternativa que sí estaba en
disco (el GLB de pistola del addon *Godot FPS Hands*, del mismo DJMaesen,
CC-BY 4.0) se descartó tras medirla: su malla de brazos carga **14 336 de sus
pesos en el hueso del codo** y la pistola es un nodo rígido sin hueso de arma, así
que no sirve para el montaje `PBody`/`Pmag` que el juego necesita.

---

No documentar assets que ya no existan en el repo. Antes de sustituir o añadir un
modelo, comprobar la licencia específica del asset y actualizar este archivo en el
mismo cambio. No asumir que la licencia de un repositorio cubre automáticamente
assets de terceros.
