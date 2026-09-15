# Créditos de modelos 3D

- `assets/models/fps_rig.glb`: **Fps Rig** de **J-Toastie** — el Glock *y* los
  brazos en un mismo esqueleto, con las animaciones `Grip`, `Idle`, `Shoot` y
  `Reload`.
  - Fuente original: Poly Pizza — https://poly.pizza/m/uxko5LkGia
  - Licencia: **Creative Commons Attribution 3.0 (CC-BY 3.0)**; uso comercial
    permitido manteniendo la atribución.
  - Atribución a incluir: *"Fps Rig" by J-Toastie, licensed under CC-BY 3.0,
    via Poly Pizza*.
  - Se descargó del pack "FPS pack" del repositorio `Hhk187/Zomopocalypse`
    (MIT), que declara la licencia del pack en el archivo
    `FPS pack by J-Toastie [CC-BY] via Poly Pizza.txt`.
  - Huesos del arma: `Root`, `Slide`, `Trigger`, `Magazine`, `Barrel`,
    `SlideCatch`. Huesos de brazos: `UpperArm`, `LowerArm`, `Hand` y dedos.
  - La malla viene con ~15° de balanceo y el origen descentrado: el juego lo
    mide en runtime (`_measure_mesh`) en vez de asumir una orientación.

- `assets/models/fps_arms.glb`: **Fps Rig** de **J-Toastie** (brazos y manos en
  primera persona, riggeados, 24 huesos con dedos; sin animaciones, la pose se
  resuelve por IK en `scripts/Arms.gd`).
  - Fuente: Poly Pizza — https://poly.pizza/m/uxko5LkGia
  - Licencia: **Creative Commons Attribution 3.0 (CC-BY 3.0)**; uso comercial
    permitido manteniendo la atribución.
  - Atribución a incluir: *"Fps Rig" by J-Toastie, licensed under CC-BY 3.0,
    via Poly Pizza*.
  - Se descargó del pack "FPS pack" del repositorio `Hhk187/Zomopocalypse`
    (MIT), el mismo del que sale el Glock; el pack declara su licencia en el
    archivo `FPS pack by J-Toastie [CC-BY] via Poly Pizza.txt`.

Antes de sustituir o añadir modelos, documentar aquí la fuente y la licencia específica del asset. No asumir que la licencia de un repositorio cubre automáticamente assets de terceros sin comprobar su procedencia.
