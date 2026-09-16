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

- **Los antebrazos se cortan demasiado cerca de la mano.** Medido en espacio de
  cámara (ojo a 0,54 m del alza, pose Idle): las manos quedan a 0,58-0,66 m; la
  manga del antebrazo sólo llega a 0,245-0,35 m y su anillo de corte mira al
  objetivo a **0,31-0,33 m**. Es lo más cercano a la cámara en pantalla, así que
  se proyecta enorme y se le ve el corte. Detalle importante medido después: la
  malla tiene **20 bucles de frontera y 1 497 vértices de borde**, pero **95% de
  esos vértices están entre 0,35 y 0,70 m**, o sea que son costuras interiores de
  las piezas (los dedos van como cascaras sueltas), no un borde abierto. Los dos
  anillos que sí se ven son dos bucles de 100 vértices (~300 mm) que **forman
  parte del skin visible**.
- **Manga corta en proporción al arma**: el tramo hombro→mano mide ~24 cm
  escalado, cuando un tirador real tiene el hombro a 45-55 cm de la empuñadura.
  Por eso el hombro entra en encuadre si se quiere que el arma domine.
- La masa de las esquinas inferiores **no son los hombros**: son las cadenas de
  antebrazo y sus huesos de torsión (`BoneTwist_01.R_013`, 550 vértices, es la
  región más grande de la malla). Los huesos llamados `Forearm_L/R` sólo llevan
  ~180 vértices cada uno.

### Dos vías de arreglo descartadas con medición

- **Round-trip por Blender: rompe el skinning.** El GLB reexportado deja la
  silueta en 0,0% y manda 6 071 vértices detrás de la cámara. Causa: la jerarquía
  de este GLB (`Armature` a escala 100 bajo un nodo a 0,01) hace que Blender
  reconstruya el reposo de los huesos a 100x y las traslaciones de la animación
  se disparen.
- **Edición directa del buffer del GLB: conserva el rig pero no arregla la
  vista.** Se escribió un editor de GLB en Python que añade los abanicos de
  cierre conservando los 81 huesos, las 5 animaciones, los 4 mapas y la metadata
  de licencia (verificado importando en Godot: 8199 vértices, misma silueta).
  Resultado visual: **tapa plana gris** en el corte (la cara nueva no tiene UV
  útil y su normal apunta al objetivo), y al hundir y reducir el anillo para que
  el corte deje de mirar a la cámara el **cuero se arruga**, porque los vértices
  del anillo son piel visible. Las dos variantes se revirtieron.

Conclusión medida: **este defecto no se arregla parchando la malla, hace falta
sustituirla.**

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

## Candidatos descargables sin cuenta (verificados, descargados y medidos)

Se buscaron assets de brazos FPS en repositorios abiertos (GitHub) y en
OpenGameArt, que **sí se pueden descargar sin cuenta**. Los tres con licencia
limpia se descargaron y se midió su contenido real:

| asset | dónde | licencia (comprobada en el propio fichero) | tris (malla de brazos) | huesos | texturas |
|---|---|---|---|---|---|
| **fps_pistol_arms.glb** (el actual) | — | CC-BY 4.0 **pero malla NC** | **14 852** | **81** | **4 × 1024²** |
| GodotFPS-Template → `resources/player/fps_demo_arms.glb` | https://github.com/bukkbeek/GodotFPS-Template | MIT (LICENSE: "Copyright (c) 2026 bukkbeek"; README: *"3D assets + FPS arms animations by bukkbeek"*) | **636** (`fps_arms_extended`) | 33 | **0** |
| novemberdev…godot → `Assets/Models/gun.glb` | https://github.com/NovemberDev/novemberdev_first_person_shooter_godot | MIT (LICENSE: "Copyright (c) 2020 NovemberDev") | **286** (`Cube.001`) | 10 | **0** |
| WRAD ARMS → `arms.glb` | https://github.com/wwwriks/wrad-arms | CC0 1.0 (LICENSE = texto legal completo de CC0) | 1 196 | 50 | 1 × 512² |

**Por qué ninguno sustituye al actual, medido:** el candidato con más geometría
tiene **12,4 veces menos triángulos** que el actual (636 contra 14 852) y **cero
texturas** — ni albedo, ni normal, ni rugosidad. Con 0 imágenes el material sale
plano, que es exactamente el estado del que este proyecto ya salió: la malla
actual sólo empezó a parecer cuero cuando se recuperó su difusa real (ver arriba).
El único con textura es CC0 pero es un asset retro PSX de 512², por debajo del
listón de "nada de aspecto PSX/low-poly" que pide el objetivo.

**Conclusión medida: no existe un reemplazo descargable sin cuenta que cumpla el
listón de fidelidad.** Las tres alternativas limpias son una regresión visual de
12-52× en geometría y pierden el material. Por eso **el asset actual sigue en
runtime**, y la decisión queda entre dos caminos que no puede tomar quien
mantiene el código:

1. **Aceptar menos fidelidad** a cambio de licencia limpia con uno de los
   candidatos MIT/CC0 de arriba (habría que animarlo y texturizarlo).
2. **Mantener la fidelidad** y resolver la licencia del asset actual: pedir
   permiso a Cransh/bumstrum, o **comprar un asset** (Fab tiene packs de brazos
   FPS desde 34,99 USD con licencia estándar) o encargarlo. La página de Fab
   devuelve HTTP 403 a las peticiones automáticas, así que su licencia **no se ha
   podido verificar aquí** y no se recomienda a ciegas.

Lo que **no** es aceptable y por eso no se ha hecho: dejar el asset NC en el
producto final sin resolverlo.

### Lo que sí está descartado con evidencia

- **GDQuest `godot-4-FPS-arms`**: el mejor aspecto de todos (3 152 tris, 50
  huesos, 8 animaciones, dos manos con pistola) y el más peligroso. Su LICENSE
  dice literalmente: *"Art assets (image textures and 3D models) are
  CC-BY-NC-SA 4.0"*. El código es MIT, los modelos **no**.
- **`aravkp/godot-dungeon-crawler-fps`**: 1 176 tris, 52 huesos, 18 animaciones,
  pero **sin fichero de licencia**; su propio README avisa de que hay packs sin
  licencia verificada.
- **`AetherRadar/operation-steel-tide`**, **`unfa/liblast`**: MIT pero no tienen
  brazos FPS (sólo armas o un personaje completo).
- **`OctavianTocan/Low-Poly-Animated-Modern-Guns-Pack`**: el repo **no contiene
  ningún modelo**, sólo README e imágenes.
- **1Matzh** y **bumstrum/DJMaesen**: no existe ningún repositorio suyo; su
  trabajo vive sólo en Sketchfab, con muro de login.

## Candidatos de Sketchfab verificados (no integrados, requieren cuenta)

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

**Ninguno se ha integrado todavía.** Cómo conseguir uno, medido en este entorno:

| vía | resultado |
|---|---|
| `api.sketchfab.com/v3/models/<uid>/download` | **HTTP 401** ("Authentication credentials were not provided"). El endpoint existe y el modelo es `isDownloadable: true`, pero exige cuenta. |
| `/download/gltf`, `/download/glb`, `/download/source` | **HTTP 404**: no hay atajo por formato. |
| Página HTML del modelo | Devuelve 202 con cuerpo vacío (protección anti-bot) y no expone la URL de descarga. |
| `api.github.com/search/code` | **HTTP 401**: requiere token. |
| Cuenta gratuita de Freesound (para el audio) | Mismo problema: las URLs de descarga redirigen a login. |

Esto no es una suposición: son los códigos de respuesta de cada endpoint. **Para
desbloquear el reemplazo hace falta una de estas dos cosas**: (a) que alguien con
cuenta descargue el candidato y lo deje en el repo, o (b) un token de Sketchfab
con permiso de descarga en el entorno. Mientras no exista ninguna de las dos, el
asset NC sigue en runtime y el proyecto no es comercializable.

La alternativa que sí estaba en disco (el GLB de pistola del addon *Godot FPS
Hands*, del mismo DJMaesen, **CC-BY 4.0**, `asset.extras` lo confirma) se midió,
se renderizó y se descartó:

- **La manga es un muñón.** Renderizada la malla aislada en Blender, los brazos
  son manos y antebrazos cortos: la mano y los dedos tienen buen detalle, pero el
  antebrazo termina enseguida. Para un encuadre FPS eso es **peor** que el asset
  actual, porque el corte quedaría aún más cerca de la cámara.
- Carga **14 336 de sus pesos en el hueso del codo** y la pistola es un nodo
  rígido sin hueso de arma, así que no sirve para el montaje `PBody`/`Pmag`.
- Trae **una sola pista de animación de 7,8 s** que el importador de Godot parte
  en tramos por `slice` (`fire` 0,300 s, `reload` 2,167 s, `idle` 0,833 s,
  medidos en su `.import`): habría que separarla en cuatro clips y volver a clavar
  los instantes mecánicos (`RELOAD_MAG_OUT_T`, `RELOAD_MAG_IN_T`,
  `RELOAD_SLIDE_T`), que hoy están medidos sobre las claves de las animaciones
  actuales.

No compensa frente al candidato 1.

---

No documentar assets que ya no existan en el repo. Antes de sustituir o añadir un
modelo, comprobar la licencia específica del asset y actualizar este archivo en el
mismo cambio. No asumir que la licencia de un repositorio cubre automáticamente
assets de terceros.
