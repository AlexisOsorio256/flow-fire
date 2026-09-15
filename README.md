# FlowFire Bodycam — Godot 4 + Jolt

> FPS chico y especializado. Cuatro cosas y nada más: **armas**, **balística**,
> **físicas Jolt** y **calidad visual/sonora**, siempre con **optimización** como
> requisito. Un cambio que no haga que disparar se sienta más real o que corra
> mejor no entra.
>
> El proyecto lo mantienen IAs: se mantiene **pequeño** a propósito. Menos
> archivos, menos sistemas, menos superficie donde romper algo.

---

## 0. Reglas para una IA que llega nueva

1. **Alcance cerrado.** Solo armas, balística, físicas, calidad y rendimiento.
   Si tu idea no entra en eso, no se hace (abre un RFC si crees que sí).
2. **Nada de suposiciones: mide.** Orientación del arma, niveles de audio,
   recorrido de huesos, FPS: se miden con las herramientas de la sección 4 y se
   corrige con esa medida.
3. **Antes de tocar:** corre los tests de la sección 4. **Después de tocar:**
   vuelve a correrlos y deja una captura o timeline.
4. **Física primero:** Jolt y nodos nativos antes que ecuaciones a mano
   (la balística de proyectiles es la única excepción, y es intencional).
5. **SI siempre:** metros, segundos, kg, m/s, julios, newtons.
6. **Clamps y estabilidad:** todo lo que reciba input del jugador o del ratón
   necesita límites.
7. **Rendimiento:** si agregas luces, partículas o efectos, mide FPS antes y
   después. Si baja más de 10%, se justifica o se revierte.
8. **Assets:** licencia compatible + crédito en `CREDITS_*.md`. Nunca
   NonCommercial.
9. **No rompas** las señales públicas ni el contrato de los tests.
10. **Cambios chicos**, medibles y reversibles. Un tema por commit, en español.
11. **Android manda:** una captura bonita en Forward+ de escritorio no prueba
    nada sobre el objetivo real.

---

## 1. Alcance

### Lo que hacemos

- **Armas:** una Glock 19 riggeada, con corredera, gatillo, cargador y cañón
  animados por huesos; recarga táctica y vacía; ADS, sprint, sway, breathing y
  retroceso.
- **Balística real:** proyectiles a ~372 m/s con gravedad y arrastre, raycast por
  subpasos, penetración entrada/salida, rebotes, orificios y daño por zona.
- **Físicas Jolt:** blancos colgantes, casquillos, colisiones del jugador.
- **Calidad:** cámara corporal con bob/lean/breathing, post-proceso bodycam,
  audio CC0 real con mix por buses, materiales PBR.
- **Optimización:** 1920x1080 de referencia en desarrollo y perfil Android real
  como objetivo de producción.

### Lo que NO hacemos (por ahora)

Multijugador · mundo abierto · vehículos · loot, inventario o crafting · gore ·
arsenal de 20 armas · campaña o cinemáticas · features que no aporten a arma,
balística, física, calidad u optimización · assets de licencia dudosa.

---

## 2. Estado actual

### Funcionando

- [x] Glock 19 riggeada integrada y acreditada.
- [x] Materiales del arma por primitiva con detalle procedural (`shaders/gun.gdshader`):
      el GLB no trae ninguna textura, así que el grano del polímero, el rayado de
      la corredera y el desgaste se generan en el shader (sin assets externos).
- [x] Brazos y manos en primera persona (`assets/models/fps_rig.glb`, "Fps Rig"
      de J-Toastie, CC-BY 3.0): el paquete trae el arma y los brazos en el mismo
      esqueleto con animaciones `Grip`/`Idle`/`Shoot`/`Reload`, así que la pose
      de agarre es la del autor (nada de IK propio deformando el skin).
- [x] Sin mira en pantalla: se apunta con las miras reales del arma.
- [x] Alineación del arma **medida en runtime** sobre la malla (orientación,
      escala real de 186 mm y verificación en el arranque).
- [x] Boca, mira y puerto de expulsión medidos sobre la geometría, en el frame
      del arma (no dentro del modelo rotado).
- [x] Corredera, gatillo, cargador y cañón animados por huesos.
- [x] Recarga táctica conserva cartuchos; recarga vacía alimenta la recámara.
- [x] Balística con gravedad, arrastre y subpasos.
- [x] Penetración entrada/salida en papel, madera y pladur.
- [x] Orificios visibles que siguen a blancos móviles.
- [x] Rebotes en metal/hormigón.
- [x] Blancos colgantes con Jolt y daño por zona (cabeza ×3.1, torso ×1, pierna ×0.65).
- [x] Casquillos con física, que salen por el puerto derecho.
- [x] Cámara bodycam con bob/breathing/ADS y post-proceso.
- [x] Audio CC0 real normalizado por familia (`tools/process_audio.sh`) y mix por
      buses (arma / mundo) con compresor por bus y techo en Master.
- [x] HUD bodycam.
- [x] Tests `--autotest`, `--aimtest`, `--pentest`, `--reloadtest`, captura
      `--capture`, timeline `--timeline` y previsualizador de arma.

### Pendiente (priorizado)

**A. Armas**
- [ ] Animación esquelética real de brazos (el asset trae el rig pero no
      animaciones: hoy la pose es IK + el movimiento del arma; falta idle,
      disparo, recarga y sprint animados).
- [ ] Recarga esquelética completa sincronizada al audio.
- [ ] Fogonazo más realista (geometría + partículas + luz) sin convertirlo en
      una explosión por disparo.
- [ ] Casquillos más visibles en primera persona.
- [ ] Viewmodel en capa/subviewport para que no se oculte con geometría.

**B. Balística**
- [ ] Validar penetración contra geometría real (hoy el grosor se aproxima).
- [ ] Penetración en cristal y chapas finas; astillas por material.
- [ ] Rebotes con ángulo, sonido y chispas según superficie.

**C. Física**
- [ ] Reacciones de blancos más ricas (caída, giro, golpes).
- [ ] Casquillos que rueden y se asienten de forma más creíble.

**D. Calidad**
- [ ] Sustituir texturas procedurales por PBR CC0 1K/2K donde una captura lo
      justifique.
- [ ] Iluminación interior más cinematográfica sin perder FPS.

**E. Optimización / Android**
- [ ] Perfil Android real (renderer Mobile, resolución escalable, medición en
      teléfono).
- [ ] Input por acciones antes de controles táctiles.
- [ ] LODs, distancias de sombra y culling de props/luces.
- [ ] Medir el coste del shader bodycam (el blur hace lecturas extra).

---

## 3. Arquitectura

| Archivo | Responsabilidad |
|---|---|
| `scenes/Main.tscn` → `scripts/Main.gd` | Arranque, entorno, tests y herramientas de medida. |
| `scripts/Player.gd` | `CharacterBody3D`, cámara corporal, bob, breathing, sprint, recoil. |
| `scripts/Arms.gd` | Brazos en primera persona: mide el rig, lo alinea y resuelve la pose de agarre por IK. |
| `scripts/GunMaterials.gd` | Materiales del arma por nombre de primitiva (con detalle procedural). |
| `scripts/Springs.gd` | Resortes amortiguados con integración estable (subpasos adaptativos). |
| `scripts/Glock.gd` | Arma: mide la base de la malla, alinea el modelo, coloca boca/mira/puerto, huesos, corredera, gatillo, recarga, fogonazo, expulsión. |
| `scripts/Ballistics.gd` | Autoload: proyectiles, penetración, rebotes, daño. |
| `scripts/Target.gd` | Blancos `RigidBody3D` colgantes con daño por zona. |
| `scripts/ImpactFX.gd` | Autoload: orificios, partículas, luces e impactos. |
| `scripts/GameAudio.gd` | Autoload: buses `Weapons`/`World`, niveles, voces limitadas y sonidos CC0. |
| `scripts/World.gd` | Rango, materiales, props, luces y paneles penetrables. |
| `scripts/HUD.gd` | HUD bodycam + post-proceso. |
| `scripts/WeaponPreview.gd` | Escena aislada para inspeccionar el arma. |
| `shaders/bodycam.gdshader` | Distorsión, chroma, grano, viñeta y blur. |
| `shaders/gun.gdshader` | Detalle procedural del arma y los brazos (sin texturas en el GLB). |
| `tools/process_audio.sh` | Normaliza los WAV por familia (ataque, cola, pico). |
| `tools/make_timeline_media.sh` | Convierte los frames de `--timeline` en contacto + vídeo. |

**Autoloads:** `GameAudio`, `ImpactFX`, `Ballistics`.
**Escena principal:** `scenes/Main.tscn`.
**Física:** Jolt (`3d/physics_engine="Jolt Physics"`), 60 ticks/s, gravedad 9.8.

### Señales públicas que NO se deben romper

- `ammo_changed(mag, chamber, reserve, reloading)`
- `shot_fired`
- `target_hit(zone)`

---

## 4. Verificación

Obligatorio después de cada cambio:

**Los 4 tests devuelven exit code 0/1**: si algo se rompe, el comando falla y no
basta con leer la salida. Verificado con pruebas negativas (apuntar al techo,
ADS desplazado, recarga rota: los tres devuelven 1).

```bash
# 1) Compila/importa y no rompe scripts
godot4 --headless --path . --editor --quit

# 2) Disparo, balística, Jolt y recamarado
godot4 --headless --path . -- --autotest
# Esperado: passed=true, targets > 0, la salud del blanco baja, se gasta 1 bala
# y la recámara queda alimentada (chamber=1).

# 3) Mira centrada
godot4 --headless --path . -- --aimtest
# Esperado: passed=true, aim_blend > 0.99 y offset_mm <= 14. Medido: ~9 mm por
# debajo del centro, porque el arma se enmarca algo baja a propósito
# (ADS_SIGHT_DROP) para no tapar el punto de mira.

# 4) Penetración y orificios
godot4 --headless --path . -- --pentest
# Esperado: passed=true, decals_after > decals_before Y el blanco recibe daño
# (las dos cosas: se comprobó que un disparo al techo falla el test).

# 5) Recarga vacía y conservación de munición
godot4 --headless --path . -- --reloadtest
# Esperado: passed=true, mag=16, chamber=1, reserve=0, total=17.
# (Comprobado también en negativo: si el cargador no se asienta, devuelve 1.)
```

**Herramientas de medida** (no son tests: sirven para no suponer):

```bash
# Medida del arma: largo/escala, caja real en frame de arma, boca/mira/puerto,
# recorrido de corredera y cargador, y pose viva.
godot4 --path . --rendering-driver vulkan -- --geometrydebug
# Esperado: passed=true con largo_m=0.186, caja (0.0296, 0.1286, 0.186),
# corredera viajando en +Z y cargador en -Y. Devuelve exit code.

# Timeline: secuencia guionizada (quieto, caminando, apuntar, disparos, recarga)
# con un frame cada 0.1 s y sus métricas (mira, boca, caja del arma, cámara).
godot4 --path . --rendering-driver vulkan -- --timeline
bash tools/make_timeline_media.sh
# Salida: captures/timeline/frame_*.png, captures/timeline_contacto.png y .mp4

# Capturas de estados sueltos, con y sin arma para comparar.
godot4 --path . --rendering-driver vulkan -- --probe
# Salida: /tmp/probe_{hip,ads,shot,reload}_{with,without}.png

# Rendimiento (desactiva vsync y mide 8 s). En headless el viewport es 64x64 y
# la cifra no vale.
godot4 --path . --rendering-driver vulkan -- --fpsbench

# Captura visual y previsualización aislada del arma
godot4 --path . --rendering-driver vulkan -- --capture   # /tmp/godot_frame.png
godot4 --path . --scene res://scenes/WeaponPreview.tscn --rendering-driver vulkan
```

`captures/` está en `.gitignore`: es material de revisión, no parte del repo.

**Definition of Done**
1. Los 4 tests pasan.
2. No baja más de 10% el FPS de la escena principal.
3. No rompe señales públicas.
4. No mete assets sin licencia ni créditos.
5. Código comentado en español o inglés claro.
6. El commit explica qué mejora de realismo o rendimiento aporta.

---

## 5. Ejecución y controles

Requisitos: **Godot 4.7.2 stable**, `ffmpeg` e ImageMagick para las herramientas.

```bash
godot4 --editor --path .                       # editor
godot4 --path . --rendering-driver vulkan      # jugar perfil de desarrollo
```

- `WASD`: mover · `Mouse`: mirar · `Click izq`: capturar mouse / disparar ·
  `Click der`: apuntar · `R`: recargar · `F`: disparo alternativo · `Esc`: liberar mouse.

Estos controles son de escritorio: antes de Android deben pasar por acciones de
input y controles táctiles, no duplicarse como otro sistema de gameplay.

---

## 6. Assets y licencias

- **Arma:** `assets/models/glock_rigged.glb`, Rigged Glock de `Hhk187/Zomopocalypse`
  (ver [`CREDITS_MODELS.md`](CREDITS_MODELS.md)).
- **Audio:** CC0 de Freesound, normalizado con `tools/process_audio.sh`
  (ver [`CREDITS_AUDIO.md`](CREDITS_AUDIO.md)).
- **Texturas:** PBR CC0 1K/2K con mipmaps y normal maps
  (ver [`CREDITS_TEXTURES.md`](CREDITS_TEXTURES.md)).
- **Código:** MIT. Ver [`LICENSE`](LICENSE).

Nunca agregues un asset sin licencia compatible y su crédito en el mismo commit.
