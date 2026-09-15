# FlowFire Bodycam — Godot 4 + Jolt

> **Juego pequeño. Calidad obsesiva.** FlowFire no compite por cantidad de sistemas: compite porque lo poco que hace debe sentirse excepcional.
>
> Si un cambio no mejora directamente **combate, sensación del arma, estabilidad, rendimiento o claridad del producto**, no entra.

---

## 0. Contrato para cualquier IA o colaborador

Este repo se mantiene pequeño a propósito. La prioridad es **profundizar**, no expandir.

1. **No inventes alcance.** Implementa únicamente lo pedido o lo necesario para corregir un problema demostrado.
2. **Si te piden “pulir”, mejora lo existente.** No lo interpretes como permiso para añadir sistemas, menús, modos, managers o contenido nuevo.
3. **Nada de arquitectura especulativa.** No crear frameworks, capas, servicios, factories, event buses, ECS, plugins internos ni abstracciones “por si luego sirven”.
4. **No hacer future-proofing sin un problema real.** Una sola implementación no necesita una abstracción genérica.
5. **No crear nuevos autoloads/managers salvo necesidad concreta y aprobación explícita.** Reutiliza la autoridad existente.
6. **Una sola autoridad por comportamiento.** No duplicar estado o lógica de arma, daño, audio, input, cámara, física o networking.
7. **No dividir archivos sólo porque crecieron.** Refactorizar únicamente cuando reduzca un problema real y medible de mantenimiento, errores o acoplamiento.
8. **Cambios locales antes que rediseños.** La solución más pequeña que arregle bien el problema gana.
9. **Nada de suposiciones: mide.** Geometría, audio, animación, FPS, timings y comportamiento se verifican con herramientas o capturas.
10. **Antes y después.** Corre pruebas antes de tocar y vuelve a correrlas después. Un cambio visual requiere inspección visual; uno de audio, revisión/medición de audio; uno de rendimiento, benchmark.
11. **Android manda junto con PC.** Que algo se vea bien en Forward+ de escritorio no demuestra que sea viable en teléfono.
12. **Assets:** licencia compatible y crédito en `CREDITS_*.md` en el mismo cambio. Nunca NonCommercial.
13. **Commits pequeños y explicables.** Un tema por commit. No mezclar una feature con un refactor grande no solicitado.
14. **Mantén este README corto y verdadero.** Corrige información vieja; no sigas agregando párrafos duplicados. Si una regla ya existe, no la repitas.

### Orden de prioridad

**correctitud → sensación/realismo → estabilidad → rendimiento → calidad audiovisual → features**

Una feature nueva nunca compensa una base mediocre.

---

## 1. Producto objetivo

FlowFire debe terminar siendo un FPS premium, compacto y deliberadamente limitado:

- **PC + Android**.
- **4 vs 4**.
- **Un mapa pequeño** y muy trabajado.
- Combate bodycam con armas, balística, físicas, audio y feedback extremadamente pulidos.
- **Mini entrenamiento** derivado del rango/prototipo actual.
- **Lobby muy simple**.
- **Multijugador**, sólo cuando el núcleo local, el rendimiento y las reglas de partida estén sólidos.

Eso es el producto. No convertirlo en un shooter enorme.

### Fuera de alcance

No añadir por iniciativa propia: mundo abierto, campaña, vehículos, loot, crafting, inventario complejo, economía, battle pass, tienda, clanes, chat, ranking, espectador avanzado, replays, decenas de armas, decenas de mapas ni sistemas sociales.

**Multijugador, lobby, mapa 4v4 y controles finales de Android son objetivos del producto, pero no se implementan antes de tiempo.** Sólo se empiezan cuando el usuario lo ordene explícitamente.

---

## 2. Núcleo actual

Actualmente FlowFire es un vertical slice de combate y entrenamiento.

- Glock 19 + brazos/manos en `assets/models/fps_rig.glb`, mismo esqueleto y animaciones `Grip`, `Idle`, `Shoot`, `Reload`.
- Arma medida en runtime: orientación, escala, boca, mira, puerto de expulsión y unidades de pose se verifican en vez de depender de offsets ciegos.
- Sin crosshair ni hitmarker visual: se apunta con las miras reales del arma.
- Arma centrada en el encuadre en pose de lista y, al apuntar, vista desde detrás del arma con la mira clavada en el centro (donde impacta la bala).
- Corredera, gatillo, cargador, cañón, recarga, expulsión de casquillo y recamarado.
- Balística con gravedad, arrastre, subpasos, penetración, rebotes y daño por zona.
- Jolt para jugador, blancos y casquillos.
- Cámara bodycam con sway/bob/breathing/recoil y post-proceso.
- Audio CC0 normalizado, buses `Weapons` / `World`, compresión por bus y techo de seguridad en Master.
- Materiales PBR del entorno y detalle procedural del arma.
- Tests duros con exit code y herramientas separadas de medición/diagnóstico.

### Foco inmediato permitido

Mientras el usuario no cambie la fase, el trabajo debe concentrarse en:

- sensación y animación del arma/manos;
- sincronía mecánica + audio;
- balística/impactos/materiales;
- estabilidad ante FPS bajos e hitches;
- rendimiento y perfil Android;
- claridad visual del bodycam;
- eliminar bugs, residuos y contradicciones.

No ampliar el juego para “aprovechar” que una tarea terminó pronto.

---

## 3. Límites técnicos

- **Motor:** Godot 4.7.2 stable.
- **Física:** Jolt, 60 ticks/s, unidades SI.
- **Perfil de desarrollo actual:** Forward+ a 1920×1080.
- **Destino de producción:** PC + Android; el perfil móvil final todavía debe medirse en dispositivo real.
- **Autoloads actuales:** `GameAudio`, `ImpactFX`, `Ballistics`.
- **Escena principal:** `scenes/Main.tscn`.

### Autoridades existentes

| Área | Autoridad principal |
|---|---|
| Arranque / escena / tests | `scripts/Main.gd` |
| Herramientas de diagnóstico | `scripts/DevTools.gd` |
| Jugador / cámara | `scripts/Player.gd` |
| Glock / viewmodel / animación mecánica | `scripts/Glock.gd` |
| Material del arma | `scripts/GunMaterials.gd` + `shaders/gun.gdshader` |
| Resortes | `scripts/Springs.gd` |
| Balística | `scripts/Ballistics.gd` |
| Impactos | `scripts/ImpactFX.gd` |
| Audio | `scripts/GameAudio.gd` |
| Mundo / rango | `scripts/World.gd` |
| Blancos | `scripts/Target.gd` |
| HUD / bodycam post | `scripts/HUD.gd` + `shaders/bodycam.gdshader` |

No crear una segunda autoridad para resolver un caso puntual.

### Señales públicas que no se deben romper sin una razón explícita

- `ammo_changed(mag, chamber, reserve, reloading)`
- `shot_fired`
- `target_hit(zone)`

---

## 4. Verificación obligatoria

```bash
# Importa/compila scripts
godot4 --headless --path . --editor --quit

# Disparo, blanco, daño, consumo y recamarado
godot4 --headless --path . -- --autotest

# ADS / mira real
godot4 --headless --path . -- --aimtest

# Penetración + daño + decals
godot4 --headless --path . -- --pentest

# Recarga vacía y conservación de munición
godot4 --headless --path . -- --reloadtest
```

Los cuatro tests deben devolver **exit code 0**. Si una regresión produce exit 1, no se maquilla ni se cambia el test para que pase: se corrige la causa, salvo que el contrato del comportamiento haya cambiado de forma deliberada.

### Herramientas de medida

```bash
# Geometría, encuadre, exposición real del arma, ciclo de corredera y recarga
godot4 --path . --rendering-driver vulkan -- --geometrydebug

# Secuencia visual reproducible
godot4 --path . --rendering-driver vulkan -- --timeline
bash tools/make_timeline_media.sh

# Estados hip / ADS / disparo / recarga
godot4 --path . --rendering-driver vulkan -- --probe

# Disparo y recarga en cámara lenta (corredera, casquillo, capas de retroceso)
godot4 --path . --rendering-driver vulkan -- --slowmo

# Rendimiento real de la escena (no usar headless para juzgar GPU)
godot4 --path . --rendering-driver vulkan -- --fpsbench

# Captura del mix final
godot4 --path . --rendering-driver vulkan -- --audiocapture
```

### Definition of Done

Un cambio no está terminado porque “funciona”. Está terminado cuando:

1. resuelve exactamente el problema pedido sin ampliar alcance;
2. los tests relevantes pasan;
3. no crea una segunda autoridad ni arquitectura innecesaria;
4. se midió o inspeccionó el aspecto que modifica;
5. no empeora perceptiblemente la estabilidad ni el rendimiento; una caída >10% requiere causa clara y decisión consciente;
6. no introduce assets sin licencia/crédito;
7. elimina código/documentación obsoleta que el propio cambio deje atrás;
8. el resultado se siente más sólido que antes, no simplemente más complejo.

---

## 5. Controles actuales

Controles provisionales de escritorio:

- `WASD`: mover
- `Mouse`: mirar
- `Click izq`: capturar mouse / disparar
- `Click der`: ADS
- `R`: recargar
- `F`: disparo alternativo de prueba
- `Esc`: liberar mouse

Antes de controles táctiles, el input debe pasar por acciones reutilizables. **No duplicar gameplay para Android**: la plataforma cambia la entrada, no las reglas del arma o del jugador.

---

## 6. Assets y licencias

- **Modelo/rig actual:** `assets/models/fps_rig.glb` — “Fps Rig” de J-Toastie, CC-BY 3.0. Ver `CREDITS_MODELS.md`.
- **Audio:** Freesound CC0, procesado con `tools/process_audio.sh`. Ver `CREDITS_AUDIO.md`.
- **Texturas PBR:** Poly Haven CC0. Ver `CREDITS_TEXTURES.md`.
- **Código del proyecto:** MIT. Ver `LICENSE`.

Nunca sustituir un asset bueno sólo por novedad. Cambiarlo únicamente si mejora de forma visible/medible el resultado o resuelve una limitación real.

---

## Regla final

**FlowFire no debe impresionar por todo lo que tiene. Debe impresionar por lo absurdamente bien hecho que está lo poco que tiene.**
