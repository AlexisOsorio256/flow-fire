# FlowFire Bodycam — Godot 4 + Jolt

Prototipo de FPS realista con cámara corporal, balística y físicas de otro nivel,
hecho con **Godot 4.7.2** y **Jolt Physics**. Este repositorio es el único
proyecto activo: aquí vive todo el juego y aquí deben contribuir humanos e IAs.

> Estado: vertical slice jugable con **Glock 19 riggeado** (huesos de corredera,
> gatillo, cargador, cañón y retén), balística real y audio CC0. La hoja de ruta
> de abajo está pensada para que cualquier IA o persona continúe sin contexto.

## Requisitos

- Godot **4.7.2 stable** (Forward+/Vulkan; también compila en Compatibility).
- GPU con soporte Vulkan recomendado.
- Jolt viene integrado en Godot 4.4+; este proyecto ya lo activa en `project.godot`:

```ini
[physics]
3d/physics_engine="Jolt Physics"
```

## Ejecutar

```bash
# Abrir el editor
godot4 --editor --path .

# Jugar directo
godot4 --path . --rendering-driver vulkan

# Test automático de disparo/balística/Jolt (sin ventana)
godot4 --headless --path . -- --autotest

# Capturar un frame
godot4 --path . --rendering-driver vulkan -- --capture
# Guarda /tmp/godot_frame.png

# Previsualizar el arma aislada (útil para ajustar escala/materiales/huesos)
godot4 --path . --scene res://scenes/WeaponPreview.tscn --rendering-driver vulkan
# Guarda /tmp/weapon_preview.png
```

## Controles

- `WASD`: mover
- `Mouse`: mirar
- `Click izquierdo`: capturar mouse / disparar (semiautomática)
- `Click derecho`: apuntar
- `R`: recargar
- `F`: disparo alternativo
- `Esc`: liberar mouse

## Sistemas principales

| Archivo | Responsabilidad |
|---|---|
| `scripts/Main.gd` | Arranque, entorno, tests `--autotest` y `--capture`. |
| `scripts/Player.gd` | `CharacterBody3D`, cámara corporal, bob, breathing, sprint, recoil. |
| `scripts/Glock.gd` | Arma, corredera, gatillo, recarga, fogonazo y expulsión de casquillos. |
| `scripts/Ballistics.gd` | Autoload: proyectiles reales con gravedad, arrastre, penetración y rebotes. |
| `scripts/Target.gd` | Blancos `RigidBody3D` colgantes con daño por zona. |
| `scripts/ImpactFX.gd` | Autoload: decales, partículas, luces e impactos. |
| `scripts/GameAudio.gd` | Autoload: audio real CC0 con `AudioStreamPlayer2D/3D`. |
| `scripts/World.gd` | Rango, materiales PBR procedurales, props y luces. |
| `scripts/HUD.gd` | HUD bodycam, crosshair, ammo, reloj, hitmarker y post-proceso. |
| `scripts/WeaponPreview.gd` | Escena aislada para inspeccionar el arma. |
| `shaders/bodycam.gdshader` | Distorsión, chroma, grano, viñeta y blur. |

## Física y disparos

- Proyectiles reales a ~372 m/s con gravedad y arrastre.
- Raycast por subpasos para no atravesar geometría.
- Penetración en papel y madera (orificio de entrada + salida).
- Rebotes en metal/hormigón con pérdida de energía.
- Daño por zona: cabeza ×3.1, torso ×1, pierna ×0.65.
- Casquillos `RigidBody3D` con rebote, rodadura y sonido.
- Los blancos son `RigidBody3D` con `PinJoint3D`; Jolt los balancea.

## Assets

- **Arma:** `assets/models/glock_rigged.glb`, Rigged Glock MIT de
  `Hhk187/Zomopocalypse`. Créditos en [`CREDITS_MODELS.md`](CREDITS_MODELS.md).
- **Audio real:** grabaciones CC0 de Freesound, recortadas con ffmpeg.
  Créditos completos en [`CREDITS_AUDIO.md`](CREDITS_AUDIO.md).
- **Texturas:** procedurales generadas para el prototipo.

Incluye 6 variantes reales de disparo, corredera, cargador fuera/dentro,
impactos de metal/hormigón/madera, rebote, casquillo y pasos.

## Hoja de ruta para contribuir

Cualquier IA o persona puede tomar un punto y abrir un PR. Mantener el rumbo:
**fotorrealismo jugable sin bajar rendimiento**.

- [x] Integrar un Glock realista con licencia compatible.
- [x] Huesos separados para corredera, gatillo, cargador y cañón.
- [x] Limitador de audio en el bus Master.
- [x] SSAO/SSIL desactivados para matar artefactos de líneas negras.
- [ ] Ajustar a ojo la dirección/recorrido de los huesos en `Glock.gd`
      (`slide_axis`, `magazine_axis`) con la escena `WeaponPreview`.
- [ ] Añadir manos/brazos en primera persona con animaciones reales.
- [ ] Recarga con animación esquelética completa y sincronizada al audio.
- [ ] Fogonazo con geometría/partículas volumétricas más creíble.
- [ ] Seguir puliendo sombras y luces para cero artefactos.
- [ ] Hacer casquillos más visibles en primera persona (escala/trayectoria).
- [ ] Penetración y rebotes con más materiales reales.
- [ ] Optimizar Forward+ sin bajar calidad (LODs, escalado, sombras).
- [ ] Migrar a un entorno urbano con assets reales.

## Convenciones para IAs

1. No romper el test `--autotest`; debe reportar blanco con daño y recarga.
2. Mantener la API de señales (`ammo_changed`, `shot_fired`, `target_hit`).
3. Preferir nodos nativos y Jolt antes que físicas manuales.
4. Cualquier asset nuevo debe tener licencia compatible y créditos.
5. Comentar el código nuevo en español/inglés claro y conciso.

## Licencia

Código bajo licencia MIT. Ver [`LICENSE`](LICENSE).
Los audios CC0 mantienen sus créditos en `CREDITS_AUDIO.md`.
