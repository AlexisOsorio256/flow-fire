# FlowFire Bodycam — Godot 4 + Jolt

> **Proyecto hiperespecializado.** No es un sandbox de features. Es un FPS
> pequeño, técnicamente denso, obsesionado con cuatro cosas:
>
> 1. **Armas** que se sientan reales.
> 2. **Balística y físicas** reales.
> 3. **Calidad visual/sonora** que sume al realismo.
> 4. **Optimización** para que todo eso corra fluido.
>
> Si eres una IA o persona que entra al repo: tu trabajo es hacer que **disparar
> se sienta más real** y que **corra igual o mejor**. Si un cambio no mejora
> armas, balística, físicas, calidad u optimización, no entra.

**English brief for AI collaborators:** FlowFire Bodycam is a small,
hyper-specialized Godot 4 + Jolt FPS prototype. The scope is intentionally
narrow: weapon handling, real projectile ballistics (drag, gravity,
penetration, ricochet), bodycam camera physics, CC0 real audio, visual quality
and performance. Do not add unrelated features. Keep the automated tests
passing and preserve the physics-first architecture.

---

## 0. Contexto rápido para una IA que llega nueva

Lee esto antes de tocar código:

- **Motor:** Godot **4.7.2 stable**, renderer **Forward+** (Vulkan).
- **Física:** **Jolt Physics** (`project.godot` → `3d/physics_engine="Jolt Physics"`).
- **Escena principal:** `scenes/Main.tscn` → `scripts/Main.gd`.
- **Autoloads:** `GameAudio`, `ImpactFX`, `Ballistics`.
- **Unidades:** SI estrictas (metros, segundos, kg, m/s, julios, newtons).
- **Arma base:** Glock 19 riggeada, 9x19, ~372 m/s, 8 g.
- **Antes de tocar:** corre los tests de la sección 6.
- **Después de tocar:** vuelve a correr los 3 tests + una captura.
- **Prohibido:** assets sin licencia, features fuera de alcance, refactors
  enormes que no aporten al realismo/rendimiento, físicas manuales donde Jolt
  ya resuelve, romper las señales públicas.

---

## 1. Misión y filosofía

FlowFire Bodycam busca la **profundidad** en un vertical slice chico:

- Una sola arma bien hecha vale más que diez armas a medias.
- Una bala que vuela, atraviesa, rebota y deja orificio vale más que mil
  partículas genéricas.
- Una cámara corporal con peso, inercia y respiración vale más que un HUD
  recargado.
- 60 FPS estables con buena nitidez valen más que 200 efectos apilados.

**Regla de oro:** cada PR debe poder responder *“¿en qué hace que disparar se
sienta más real o que corra mejor?”*.

---

## 2. Pilares del juego (lo que SÍ hacemos)

### 2.1 Armas
- Modelo 3D realista de Glock con licencia compatible.
- Huesos separados: `Slide`, `Trigger`, `Magazine`, `Barrel`, `SlideCatch`.
- Manejo: retroceso, recuperación, gatillo, corredera, recarga, ADS, sprint.
- Sway físico, breathing, inercia y clamps para que nunca se salga de cámara.
- Mira centrada de verdad (`--aimtest`).

### 2.2 Balística real
- Proyectiles reales a ~372 m/s, con **gravedad** y **arrastre**.
- Raycast por subpasos para evitar túneles.
- **Penetración**: entrada + salida + continuación con pérdida de energía.
- Materiales: papel, madera y pladur penetrables; metal/hormigón rebotan.
- **Rebotes** con pérdida de energía y sonido.
- **Orificios visibles** de entrada y salida, unidos al objeto impactado.
- Daño por zona: cabeza ×3.1, torso ×1, pierna ×0.65.

### 2.3 Físicas Jolt
- Blancos colgantes `RigidBody3D` + `PinJoint3D`.
- Casquillos `RigidBody3D` con rebote, rodadura y sonido.
- Colisiones del jugador contra props y mundo.
- Movimiento `CharacterBody3D` con peso e inercia.

### 2.4 Cámara corporal (Bodycam)
- Cámara a la altura del pecho, no de los ojos.
- Bob, lean, breathing, sprint FOV y peso al arrancar/parar.
- Post-proceso bodycam: distorsión de lente, chroma, viñeta, grano y blur.
- Mira ADS calculada con transformaciones reales del modelo.

### 2.5 Audio real
- Sonidos **reales CC0**, no sintetizados.
- 6 variantes de disparo, corredera, cargador, impactos, rebote, casquillo, pasos.
- Audio 3D posicional para impactos y casquillos.
- Limitador en bus Master para que no reviente al disparar rápido.

### 2.6 Calidad visual
- Materiales PBR procedurales: hormigón, madera, metal, pladur.
- Sombras direccionales + luces de interior.
- 1920x1080 nativo, MSAA 2x, anisotrópico 2x, sin FXAA.
- Fogonazo, humo, chispas, polvo y luces de impacto.

### 2.7 Optimización
- SSAO/SSIL apagados (además quitaban artefactos).
- Sombra direccional 2048 y distancia acotada.
- Sin reescalado dinámico (`scaling_3d` en 1.0) para no ver borroso.
- Partículas y decales con límites.
- Meta: **60 FPS en Intel HD 520 a 1080p**; si un cambio baja más de 10% el
  FPS, debe justificarse o revertirse.

---

## 3. No-objetivos (lo que NO hacemos por ahora)

Para mantener la hiperespecialización:

- ❌ Multijugador.
- ❌ Mundo abierto / mapas enormes.
- ❌ Vehículos, loot, inventario, crafting.
- ❌ Gore o sangre explícita.
- ❌ 20 armas distintas.
- ❌ Cinemáticas y campaña.
- ❌ Features que no aporten a arma, balística, física, calidad u optimización.
- ❌ Assets con licencia dudosa.

Si quieres romper un no-objetivo, primero abre un issue/RFC explicando por qué
mejora el núcleo. Si no convence, no entra.

---

## 4. Estado actual (vertical slice jugable)

### Funcionando
- [x] Glock 19 riggeada MIT integrada.
- [x] Corredera, gatillo, cargador y cañón animados por huesos.
- [x] Balística con gravedad, arrastre y subpasos.
- [x] Penetración entrada/salida en papel, madera y pladur.
- [x] Orificios visibles que siguen a blancos móviles.
- [x] Rebotes en metal/hormigón.
- [x] Blancos colgantes con Jolt y daño por zona.
- [x] Casquillos con física.
- [x] Cámara bodycam con bob/breathing/ADS.
- [x] Audio real CC0 + limitador.
- [x] HUD bodycam + post-proceso.
- [x] Tests `--autotest`, `--aimtest`, `--pentest`, `--capture`.
- [x] Previsualizador de arma aislado.

### Pendiente (hoja de ruta priorizada)
**A. Armas y animación**
- [ ] Manos/brazos en primera persona con animación real.
- [ ] Recarga esquelética completa sincronizada al audio.
- [ ] Fogonazo más realista (geometría + partículas + luz dinámica).
- [ ] Casquillos más visibles en primera persona.
- [ ] Viewmodel en capa/subviewport para que no se oculte con geometría.

**B. Balística**
- [ ] Penetración en cristal, chapas finas y más grosores.
- [ ] Astillas/desprendimiento por material.
- [ ] Rebotes con ángulo, sonido y chispas dependientes de superficie.
- [ ] Balística de distancia con caída más evidente a larga distancia.

**C. Física**
- [ ] Reacciones de blancos más ricas (caída, giro, golpes).
- [ ] Casquillos que rueden y se asienten de forma más creíble.
- [ ] Colisiones del arma/brazos contra paredes cercanas.

**D. Calidad visual**
- [ ] Texturas PBR en mayor resolución.
- [ ] Iluminación interior más cinematográfica sin perder FPS.
- [ ] Mejor post-proceso bodycam sin ensuciar la imagen.
- [ ] Entorno urbano chico y creíble (solo cuando el núcleo esté sólido).

**E. Optimización**
- [ ] LODs y distancias de sombra.
- [ ] Oclusión/culling de props y luces.
- [ ] Pooling de partículas y decales.
- [ ] Perfilado en GPU integrada y modo rendimiento/calidad.

---

## 5. Arquitectura

| Archivo | Responsabilidad |
|---|---|
| `scripts/Main.gd` | Arranque, entorno, tests `--autotest`, `--aimtest`, `--pentest`, `--capture`. |
| `scripts/Player.gd` | `CharacterBody3D`, cámara corporal, bob, breathing, sprint, recoil. |
| `scripts/Glock.gd` | Arma, huesos, corredera, gatillo, recarga, fogonazo, expulsión. |
| `scripts/Ballistics.gd` | Autoload: proyectiles, penetración, rebotes, daño. |
| `scripts/Target.gd` | Blancos `RigidBody3D` colgantes con daño por zona. |
| `scripts/ImpactFX.gd` | Autoload: orificios, partículas, luces e impactos. |
| `scripts/GameAudio.gd` | Autoload: audio real CC0 + limitador. |
| `scripts/World.gd` | Rango, materiales, props, luces y paneles penetrables. |
| `scripts/HUD.gd` | HUD bodycam + post-proceso. |
| `scripts/WeaponPreview.gd` | Escena aislada para inspeccionar el arma. |
| `shaders/bodycam.gdshader` | Distorsión, chroma, grano, viñeta y blur. |

### Señales públicas que NO se deben romper
- `ammo_changed(mag, chamber, reserve, reloading)`
- `shot_fired`
- `target_hit(zone)`

---

## 6. Tests y verificación

Ejecutar siempre en este orden después de un cambio:

```bash
# 1) Compila/importa y no rompe scripts
godot4 --headless --path . --editor --quit

# 2) Disparo, balística, recarga, Jolt
godot4 --headless --path . -- --autotest
# Esperado: shotFired, reloadWorked y target health ≈ 55.5

# 3) Mira centrada
godot4 --headless --path . -- --aimtest
# Esperado: delta_px < 0.5

# 4) Penetración y orificios
godot4 --headless --path . -- --pentest
# Esperado: decals_after > decals_before, health ≈ 55.5

# 5) Captura visual
godot4 --path . --rendering-driver vulkan -- --capture
# Guarda /tmp/godot_frame.png

# 6) Previsualización del arma
godot4 --path . --scene res://scenes/WeaponPreview.tscn --rendering-driver vulkan
# Guarda /tmp/weapon_preview.png
```

**Definition of Done de un PR:**
1. Los 4 tests automáticos pasan.
2. No baja más de 10% el FPS en la escena principal.
3. No rompe señales públicas.
4. No mete assets sin licencia y créditos.
5. El código nuevo está comentado en español o inglés claro.
6. Explica en el PR qué mejora de realismo/optimización aporta.

---

## 7. Convenciones para IAs y humanos

1. **Física primero:** usa Jolt y nodos nativos antes que ecuaciones a mano,
   excepto para balística de proyectiles (ahí el control fino es intencional).
2. **SI siempre:** nada de “unidades raras”. Metros, kg, m/s, J, N.
3. **Nada de magia:** si usas un número raro, comenta de dónde sale.
4. **Clamps y estabilidad:** cualquier sistema que reciba input del mouse o del
   jugador debe tener límites; no queremos otra vez el arma saliéndose.
5. **Rendimiento:** si agregas luces, partículas o decales, mide FPS antes/después.
6. **Assets:** licencia compatible + créditos en `CREDITS_*.md`.
7. **No toques** `project.godot` para bajar calidad sin justificarlo.
8. **Commits:** mensajes claros en español, un tema por commit.
9. **Sin refactors masivos:** cambios chicos, medibles y reversibles.
10. **El núcleo manda:** si tu feature no mejora armas, balística, física,
    calidad u optimización, probablemente esté fuera de alcance.

---

## 8. Requisitos y ejecución

- Godot **4.7.2 stable** (Forward+/Vulkan; también compila en Compatibility).
- Jolt viene integrado en Godot 4.4+; el proyecto ya lo activa.

```bash
# Editor
godot4 --editor --path .

# Jugar
godot4 --path . --rendering-driver vulkan
```

### Controles
- `WASD`: mover
- `Mouse`: mirar
- `Click izquierdo`: capturar mouse / disparar (semiautomática)
- `Click derecho`: apuntar
- `R`: recargar
- `F`: disparo alternativo
- `Esc`: liberar mouse

---

## 9. Assets y licencias

- **Arma:** `assets/models/glock_rigged.glb`, Rigged Glock MIT de
  `Hhk187/Zomopocalypse`. Ver [`CREDITS_MODELS.md`](CREDITS_MODELS.md).
- **Audio real:** CC0 de Freesound, recortado con ffmpeg.
  Ver [`CREDITS_AUDIO.md`](CREDITS_AUDIO.md).
- **Texturas:** generadas proceduralmente para el prototipo.
- **Código:** MIT. Ver [`LICENSE`](LICENSE).

Nunca agregues un asset sin licencia compatible y su crédito correspondiente.

---

## 10. Resumen de una línea

**FlowFire Bodycam es un FPS chico e hiperespecializado: pocas cosas, pero
armas, balística, físicas, calidad y optimización de otro nivel.**
