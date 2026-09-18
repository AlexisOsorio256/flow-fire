# Créditos de modelos 3D

Los créditos se quedan mientras el asset esté en el repo o de él salga contenido
distribuido. Este archivo guarda además el **diagnóstico de los modelos que se
van a reemplazar**, con las medidas que lo justifican, para no repetir la
búsqueda.

## Brazos — 1Matzh  (EN REEMPLAZO: ver "Diagnóstico")

- Archivo: `assets/models/arms.glb` (13,42 MB), derivado; ver "Cómo se hizo".
- Fuente: Sketchfab —
  https://sketchfab.com/3d-models/desert-eagle-first-person-animations-09a213d8510a42d1b747135e85712eff
- Autor: **1Matzh** — https://sketchfab.com/1Matzh
- Licencia: **CC-BY 4.0**, declarada en `asset.extras` del propio GLB.
  Atribución: *"Desert Eagle | First Person Animations" by 1Matzh, licensed
  under CC-BY 4.0, via Sketchfab*.
- Cómo se hizo: el GLB que llegó del pack (`deagle_arms.glb`, 102 MB) ya no vive
  en el repo; se recupera con `git show fb95cc3:assets/models/deagle_arms.glb` y
  lo poda `tools/prune_arms.py`, que deja **solo lo que el viewmodel usa**: las
  cinco mallas del personaje (`Sleeves`, `Watch`, `Watch_Emission`, `Body`,
  `Gloves`), los 78 huesos que las deforman, los cinco clips (`Idle`, `Fire`,
  `Reload`, `Reload_Empty`, `Inspect`) remuestreados a 60 FPS y las diez texturas
  que pintan esos materiales. La pistola, el skybox y los ayudantes de apuntado
  del pack se van en el podado, no en runtime.
- Contenido: 21 705 triángulos (14 384 de ellos solo en los guantes), 78 huesos
  y diez texturas: seis de 1024² y cuatro de 512².

### Diagnóstico: por qué se reemplazan

Medido sobre `assets/models/arms.glb` (13,42 MB):

| Parte | Peso | |
|---|---|---|
| Texturas (10 PNG) | 11,03 MB | 82 % del archivo |
| Malla (5 mallas, 21 705 tris) | 1,57 MB | 12 % |
| Animación (5 clips a 60 FPS) | 0,72 MB | 5 % |
| Esqueleto + JSON | 0,10 MB | 1 % |

- **El tamaño lo ponen las texturas.** El mismo asset con todo a 512² mide
  4,81 MB (2,42 MB de texturas). Bajar a 512 es el único mando que queda dentro
  de este asset, y no toca el problema de fondo.
- **El rig de 706 KB no es la alternativa.** `fps_rig.glb` de J-Toastie (commit
  `490f22a`) pesa 706 KB porque **no trae ni una textura** (0 imágenes) y sus
  cuatro clips (`Grip`, `Idle`, `Reload`, `Shoot`) mueven 2–4 canales cada uno:
  no existe `Reload_Empty` ni `Inspect`, que el juego sí reproduce, y las manos
  vuelven a verse sin material. Reponerlo es lo que motivó `fb95cc3`.
- **Lo que de verdad ata estos brazos es la coreografía.** Los clips se animaron
  para la Desert Eagle del autor, que no se ve. Nuestra Glock va fija al pivote,
  con su sitio en dos constantes calibradas a mano (`GRIP_POS` / `GRIP_ROT`), y
  los dos tiempos del cargador son instantes del clip, medidos con
  `tools/check_reload.gd` y escritos como `RELOAD_*_T` en `Glock.gd`. El rig no
  tiene un hueso del arma que se pueda leer: cada vez que un clip cambie hay que
  volver a medir.
- **Android:** 13,42 MB de brazos más 11 MB de texturas para un viewmodel es la
  dirección contraria a la del proyecto, aunque todavía no hay una medición
  Android.

### Qué tiene que traer el reemplazo

1. Texturas ≤512² (o ninguna) y un presupuesto total ≤5 MB.
2. Cinco clips por acción (`Idle`, `Fire`, `Reload`, `Reload_Empty`, `Inspect`) y
   muchos menos huesos.
3. Un hueso del arma (o socket equivalente) **dentro del rig**, para colgar la
   Glock de él y no volver a calibrar posiciones ni medir instantes.

El día que entre, este bloque, `tools/prune_arms.py` y `arms.glb` se van juntos.

## 9mm Pistol — Urpo  (ARMA VISIBLE)

- Archivo: `assets/models/glock_urpo.glb` (15,9 MB).
- Fuente: Sketchfab —
  https://sketchfab.com/3d-models/9mm-pistol-30222f9a59104426ba526a6b20cd7532
- Autor: **Urpo** — https://sketchfab.com/Urpo
- Licencia: **CC-BY 4.0**, declarada en `asset.extras` del propio GLB.
  Atribución: *"9mm Pistol" by Urpo, licensed under CC-BY 4.0, via Sketchfab*.
- La pistola llega ya separada en tres nodos por el autor: `Gun_Slide`,
  `Gun_Body` y `Magazine`. `tools/make_weapon_parts.py` les da a cada uno su
  propio origen y añade los puntos de boca, miras y puerto de expulsión medidos
  sobre la malla. Resultado: el arma es un árbol de piezas rígidas, sin
  esqueleto, y mover una pieza es escribir un `transform`.

## Assets evaluados y descartados

Nada de esto está en el repo. Se conserva únicamente como registro de **qué se
midió y por qué se descartó**, para no repetir la búsqueda.

- **Fps Rig** — J-Toastie, CC-BY 3.0 (`fps_rig.glb`, 706 KB). Estuvo en el repo
  (commit `490f22a`) y se sustituyó en `fb95cc3`: sin texturas, con cuatro clips
  que mueven dos huesos cada uno, los hombros se veían feos al apuntar.
  Atribución que se conserva: *"Fps Rig" by J-Toastie, licensed under CC-BY 3.0*.
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
- **GDQuest `godot-4-FPS-arms`**: el mejor aspecto de los gratuitos (3 152 tris,
  8 animaciones) y el mas peligroso. Su LICENSE pone los **modelos** en
  CC-BY-NC-SA 4.0 aunque el codigo sea MIT.
- **bukkbeek/GodotFPS-Template** (MIT, 636 tris) y **NovemberDev** (MIT, 286
  tris): licencia limpia pero **cero texturas** y una decima parte de la
  geometria; serian una regresion visual.
- **wwwriks/wrad-arms** (CC0): la licencia mas limpia de todas, pero es un asset
  retro PSX de 512² y sin animaciones.

## Assets que salieron del repo

Solo viven en la historia de git: no queda nada de ellos en el árbol ni en lo que
se distribuye.

- `desert_eagle.glb` — **ELIZION**, CC-BY 4.0. *"Desert Eagle" by ELIZION,
  licensed under CC-BY 4.0, via Sketchfab*.
  https://sketchfab.com/3d-models/desert-eagle-cabde59f5cf24effaf80536e35d04e95
- `full9mm_2k.glb` — **1Matzh**, CC-BY 4.0. Antes de integrarlo se comprobó su
  cadena de licencia: los brazos son `Modern Soldier` de **Blue-Spirit**, CC-BY
  4.0, y la pistola es la `9mm Pistol` de Urpo de arriba. *"9mm Pistol | First
  Person Animations" by 1Matzh, licensed under CC-BY 4.0, via Sketchfab*.
  https://sketchfab.com/3d-models/9mm-pistol-first-person-animations-c26d7f5aa72f4b01a6da4578caa8f07f
