# Créditos de modelos 3D

## 9mm Pistol — Urpo (EL ARMA)

- Archivo: `assets/models/glock_urpo.glb` (15,9 MB). El GLB lleva sus diez
  texturas embebidas: es la única representación del arma en el repo.
- Fuente: Sketchfab —
  https://sketchfab.com/3d-models/9mm-pistol-30222f9a59104426ba526a6b20cd7532
- Autor: **Urpo** — https://sketchfab.com/Urpo
- Licencia: **CC-BY 4.0**, declarada en `asset.extras` del propio GLB.
  Atribución: *"9mm Pistol" by Urpo, licensed under CC-BY 4.0, via Sketchfab*.
- Transformación: `tools/make_weapon_parts.py` da a cada pieza su propio origen y
  añade los puntos medidos sobre la malla (`Muzzle`, `EjectionPort`, `SightRear`,
  `SightFront`). El resultado son tres mallas rígidas — `Frame`, `Slide`,
  `Magazine` — sin esqueleto y sin animaciones. El asset **no trae `Trigger` ni
  `Barrel`**: `GlockWeapon.gd` los trata como opcionales y el juego funciona sin
  ellos. Añadirlos es trabajo de Blender sobre esta malla, no de código.

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
