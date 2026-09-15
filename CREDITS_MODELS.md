# Créditos de modelos 3D

## Fps Rig — J-Toastie

- Archivo: `assets/models/fps_rig.glb`.
- Incluye Glock, brazos/manos, un único esqueleto y animaciones `Grip`, `Idle`, `Shoot` y `Reload`.
- Fuente original: Poly Pizza — https://poly.pizza/m/uxko5LkGia
- Licencia: **Creative Commons Attribution 3.0 (CC-BY 3.0)**; permite uso comercial manteniendo la atribución.
- Atribución a incluir: *"Fps Rig" by J-Toastie, licensed under CC-BY 3.0, via Poly Pizza*.
- El asset se obtuvo desde el pack "FPS pack" del repositorio `Hhk187/Zomopocalypse` (MIT), que conserva la declaración de licencia del asset de J-Toastie.
- Huesos relevantes del arma: `Root`, `Slide`, `Trigger`, `Magazine`, `Barrel`, `SlideCatch`.
- El rig trae orientación/origen no ideales para el juego; FlowFire mide y verifica su geometría en runtime en vez de asumir offsets fijos.
- **Sigue siendo la autoridad de brazos y animaciones.** Su malla de arma se oculta cuando el arma de alta fidelidad está activa, pero el esqueleto y las animaciones se siguen usando.

## OWK 19 Pistol 9mm (G19) — OKgamedev

- Archivo: `assets/models/owk19_pistol.glb` (28.5 MB, md5 `b26c4f52f481aea04475ce35847bf9d4`).
- Fuente: Sketchfab — https://sketchfab.com/3d-models/owk-19-pistol-9mm-g19-3a773b0f46f246dc855742ef413bf4a6
- Autor: **OKgamedev** — https://sketchfab.com/OKgamedev
- Licencia: **Creative Commons Attribution 4.0 (CC-BY 4.0)**, declarada en la metadata `asset.extras` del propio GLB y verificada antes de integrar.
- Atribución a incluir: *"OWK 19 Pistol 9mm (G19)" by OKgamedev, licensed under CC-BY 4.0, via Sketchfab*.
- 11 568 triángulos en 9 piezas rígidas separadas (`Slide`, `Frame`, `SlideLock`, `Barrel`, `Sight`, `Magazine`, `Shell`, `Bullet`, `Trigger`) y 4 materiales PBR (`GlockSlide`, `GlockFrame`, `GlockMag`, `Bullet`) con albedo, metallic-roughness y normal; `GlockSlide` lleva además emisivo.
- **No trae esqueleto ni animaciones a propósito**: la mecánica de FlowFire (recorrido de corredera, gatillo, recámara, cargador, expulsión) es la autoridad y mueve las piezas como nodos rígidos.
- La metadata de licencia se conserva dentro del GLB; no se ha eliminado al copiarlo al repositorio.

## FPS Arms — DJMaesen

- Archivo: `assets/models/fps_arms.glb` (10.3 MB, md5 `0546fa73ffcf15031d874f6697c794cd`).
- Fuente: Sketchfab — https://sketchfab.com/3d-models/fps-arms-08ec4403a47645d8ad80633abf13d39d
- Autor: **DJMaesen** (bumstrum) — https://sketchfab.com/bumstrum
- Licencia: **Creative Commons Attribution 4.0 (CC-BY 4.0)**, declarada en `asset.extras`.
- Atribución a incluir: *"fps arms" by DJMaesen, licensed under CC-BY 4.0, via Sketchfab*.
- 7 028 triángulos, 1 malla skinned, 47 huesos, **sin animaciones**.
- **No integrado.** Evaluado como recambio de brazos y descartado por ahora: su topología de dedos no casa con la del rig actual (ver nota de retarget).

## 9mm Luger Ammo (Free) — Ziperi

- Archivo: `assets/models/9mm_luger.glb` (8.4 MB).
- Fuente: Sketchfab — https://sketchfab.com/3d-models/9mm-luger-ammo-free-25cac470713949619a6c766886e3cd0a
- Autor: **Ziperi** — https://sketchfab.com/ziperistudio
- Licencia: **Creative Commons Attribution 4.0 (CC-BY 4.0)**, declarada en `asset.extras`.
- Atribución a incluir: *"9mm Luger Ammo (Free)" by Ziperi, licensed under CC-BY 4.0, via Sketchfab*.
- 608 triángulos, 1 malla, 1 material PBR completo.
- **No integrado todavía**: la Glock OWK ya trae piezas `Shell` (380 tris) y `Bullet` (208 tris). Se usará el que dé mejor calidad por coste tras compararlos visualmente.

---

## Nota: por qué no se retargetean las animaciones al rig de brazos nuevo

Las animaciones actuales (`Grip`, `Idle`, `Shoot`, `Reload`) son del rig viejo y
funcionan. Retargetearlas a `fps_arms.glb` **no es viable sin inventar
movimiento**, y el motivo es topológico, no de nombres:

| | rig viejo (J-Toastie) | rig nuevo (DJMaesen) |
|---|---|---|
| huesos | 41 | 47 |
| cadenas de dedos por mano | 3 (`DoubleFingers`, `Index`, `Thumb`) | 5 (`thumb`, `point`, `middle`, `ring`, `pink`) |

`DoubleFingers` es **una sola cadena para corazón, anular y meñique**. Al
retargetear sólo hay origen para una de las tres, así que las otras dos se
quedarían en su pose de reposo: **extendidas**, mientras el resto de la mano
agarra. En una empuñadura de pistola eso es justo lo que no puede pasar, porque
anular y meñique son los que cierran contra el frente del armazón. No es un
problema de escala ni de offsets que se arregle con más cuidado: falta el
movimiento de origen.

El rig nuevo tampoco trae animaciones propias, así que no hay fuente alternativa.
Se conserva el rig viejo para brazos y animación, y el arma de alta fidelidad se
integra como piezas rígidas sobre esa misma mano.

---

No documentar assets que ya no existan en el repo. Antes de sustituir o añadir un
modelo, comprobar la licencia específica del asset y actualizar este archivo en el
mismo cambio. No asumir que la licencia de un repositorio cubre automáticamente
assets de terceros.
