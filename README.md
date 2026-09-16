# FlowFire Bodycam — Godot 4 + Jolt

> **Juego pequeño. Calidad obsesiva.** FlowFire no compite por cantidad de sistemas: compite porque lo poco que hace debe sentirse excepcional.
>
> Si un cambio no mejora directamente **combate, profundidad física, sensación del arma, realismo perceptual, estabilidad, rendimiento o claridad del producto**, no entra.

---

## 0. Contrato para cualquier IA o colaborador

Este repositorio se mantiene pequeño a propósito y el código se mantiene **100% con IA**. El siguiente modelo debe poder entender las autoridades, medir el comportamiento y continuar sin reconstruir el proyecto mentalmente desde cero. La prioridad es **profundizar, no expandir**.

1. **No inventes alcance.** Implementa únicamente lo pedido o lo necesario para corregir un problema demostrado.
2. **Si te piden “pulir”, profundiza lo existente.** No significa añadir sistemas, menús, modos, contenido o arquitectura nueva.
3. **Física, profundidad, realismo y eficiencia son restricciones simultáneas.** No se acepta más realismo a costa de desperdicio evitable, ni más FPS destruyendo la percepción buscada. El objetivo es mantener o mejorar calidad mientras se mantiene o mejora la eficiencia; una excepción debe estar medida y justificada.
4. **Una sola ruta de producción. Sin fallbacks ni legacy activo.** Cuando un reemplazo está validado, elimina el camino anterior, sus flags, assets y código muerto. Git es el rollback. No conservar `old_*`, `--old*`, implementaciones alternativas ni autoridades duplicadas “por si acaso”.
5. **Una sola autoridad por comportamiento.** No duplicar estado o lógica de arma, daño, audio, input, cámara, física, animación mecánica o networking.
6. **Nada de arquitectura especulativa.** No crear frameworks, capas, servicios, factories, event buses, ECS, plugins internos ni abstracciones “por si luego sirven”.
7. **No hacer future-proofing sin un problema real.** Una sola implementación no necesita una abstracción genérica.
8. **Las herramientas de diagnóstico NO son sobreingeniería cuando resuelven una necesidad real del flujo IA.** Benchmarks, capturas deterministas, slow motion, diagnósticos geométricos, audio y pruebas pueden ser extensos si permiten medir el producto. Deben permanecer fuera de la autoridad de gameplay, ejecutarse sólo cuando se solicitan y no imponer coste significativo al juego normal.
9. **El tooling sirve al modelo, no al revés.** Puede variar según la tarea/modelo activo. Prefiere comandos claros que produzcan datos, capturas o logs reproducibles; no metas lógica específica de un proveedor de IA en producción.
10. **No crear nuevos autoloads/managers salvo necesidad concreta y aprobación explícita.** Reutiliza la autoridad existente.
11. **No dividir archivos sólo porque crecieron.** Refactorizar únicamente cuando reduzca un problema real y medible de mantenimiento, errores, acoplamiento o coste.
12. **Cambios locales antes que rediseños.** La solución más pequeña que arregle bien la causa gana.
13. **Nada de suposiciones: mide.** Geometría, física, penetración, audio, animación, FPS, timings y comportamiento deben comprobarse con herramientas, referencias o capturas.
14. **Modelo → mide → compara → corrige → vuelve a medir.** Un cambio visual requiere inspección visual; audio requiere revisión/medición; rendimiento requiere benchmark; física requiere comprobar el resultado físico real, no sólo un test verde.
15. **Android manda junto con PC.** Que algo funcione o se vea bien en escritorio no demuestra que sea viable en teléfono.
16. **Assets:** licencia compatible y crédito en `CREDITS_*.md` en el mismo cambio. Nunca NonCommercial. No conservar candidatos descartados sin una razón activa.
17. **Commits pequeños y explicables.** Un tema por commit cuando sea razonable. No mezclar una feature con un refactor grande no solicitado.
18. **Mantén este README corto y verdadero.** Corrige información vieja; no dupliques reglas ni documentes estados que ya no existen.
19. **Elimina lo que tu propio cambio vuelva obsoleto.** Código, assets, flags, comentarios, tests falsos y documentación muerta no se acumulan.

### Prioridad de ingeniería

**correctitud → profundidad física / sensación / realismo → estabilidad → rendimiento → calidad audiovisual → features**

Ese orden no autoriza a degradar lo que está a la derecha: en FlowFire la **calidad perceptual y la eficiencia son criterios de aceptación**, no sliders que se cambian a ciegas.

---

## 1. Producto objetivo

FlowFire debe terminar siendo un FPS premium, compacto y deliberadamente limitado:

- **PC + Android**.
- **4 vs 4**.
- **Un mapa pequeño** y muy trabajado.
- Combate bodycam con armas, balística, físicas, audio, materiales e impactos extremadamente pulidos.
- **Mini entrenamiento** derivado del rango/prototipo actual.
- **Lobby muy simple**.
- **Multijugador**, sólo cuando el núcleo local, el rendimiento y las reglas de partida estén sólidos.

Eso es el producto. No convertirlo en un shooter enorme.

La profundidad debe venir de cómo reaccionan **arma, proyectil, material, cuerpo, cámara y sonido**, no de acumular features. Cuando una bala atraviese una estructura, debe sentirse como una entrada, pérdida de energía y salida coherentes; no como “tocó el objeto y reprodujo un efecto”.

### Fuera de alcance

No añadir por iniciativa propia: mundo abierto, campaña, vehículos, loot, crafting, inventario complejo, economía, battle pass, tienda, clanes, chat, ranking, espectador avanzado, replays, decenas de armas, decenas de mapas ni sistemas sociales.

**Multijugador, lobby, mapa 4v4 y controles finales de Android son objetivos del producto, pero no se implementan antes de tiempo.** Sólo se empiezan cuando el usuario lo ordene explícitamente.

---

## 2. Núcleo actual

Actualmente FlowFire es un vertical slice de combate y entrenamiento.

- Glock 19 de alta fidelidad en `assets/models/owk19_pistol.glb` (OWK 19, OKgamedev, CC-BY 4.0): 11 568 tris en 9 piezas rígidas. Es la **única representación del arma**; no existe rig legacy ni fallback.
- Brazos/manos y animaciones de pistola en `assets/models/fps_pistol_arms.glb` (Cransh): única fuente de pose humana. El cuerpo del arma cuelga de `PBody` y el cargador de `Pmag`. El GLB venía con `KHR_materials_pbrSpecularGlossiness`, que Godot no implementa: **su textura difusa se descartaba entera** y los brazos salían como geometría gris plana. Está convertido a metallic-roughness (receta reproducible en `CREDITS_MODELS.md`); ahora el guante, el normal y la rugosidad son los del autor y el código sólo tiñe el albedo. **Atribución pendiente de aclarar**: la malla parece ser "FP Arms" de bumstrum, que ese autor publica como CC-BY-NC; ver `CREDITS_MODELS.md` antes de un lanzamiento comercial.
- Montaje de brazos con **escala uniforme derivada de geometría**, sin estiramientos anatómicos para ocultar hombros.
- ADS resuelto desde la **mira trasera y delantera visibles de la OWK**; los marcadores geométricos son fuente y la pose es derivada, no al revés.
- Sin crosshair ni hitmarker visual: se apunta con las miras reales del arma.
- Corredera, gatillo, cargador, recarga, expulsión de casquillo y recamarado gobernados por el estado mecánico.
- Balística con gravedad, arrastre, subpasos, penetración, rebotes y daño por zona. **La salida ya se calcula desde la geometría real del volumen**, no desde metadata de grosor: se resuelve el intervalo de intersección de los tres *slabs* de cada `BoxShape3D` del collider y la cara lejana es la salida. Limitación concreta y deliberada: **`_find_exit_geometry()` sólo entiende `BoxShape3D`**; con cualquier otra forma no hay salida demostrable y el proyectil se detiene. Es suficiente para el rango actual (paneles y muros son cajas) y no se generaliza hasta que exista un caso real.
- Jolt para jugador, blancos y casquillos.
- Cámara bodycam con sway/bob/breathing/recoil y post-proceso sin blur deliberado.
- Audio con buses `Weapons` / `World`, compresión por bus y techo de seguridad en Master. Los 5 disparos son tomas reales de Glock 18c (Sonniss GDC 2016, royalty-free comercial); la foley es CC0. Todos los WAV se alinean a su ataque real con `tools/process_audio.sh`: **los 15 archivos atacan dentro de los primeros 2 ms**, así que ningún evento suena tarde.
- Materiales PBR reales para entorno y OWK 19.
- Tests duros con exit code y un laboratorio separado de medición/diagnóstico.

### Foco inmediato permitido

Mientras el usuario no cambie la fase, el trabajo debe concentrarse en:

- sensación, proporción y animación del arma/manos;
- sincronía mecánica + audio;
- balística, penetración geométrica, impactos y respuesta por material;
- estabilidad ante FPS bajos e hitches;
- rendimiento y perfil Android;
- claridad visual del bodycam;
- iluminación estática eficiente del rango;
- sustituir assets de primera persona cuando la propia geometría limite el realismo;
- eliminar bugs, residuos, fallbacks y contradicciones.

### Limitación conocida del viewmodel

El encuadre de **ADS no puede evitar que los hombros entren en pantalla** con este rig, y no es un problema de ajuste: es geometría medida con `--armdiag`.

- En ADS el alza trasera queda a 0,42 m del ojo, y el hombro cae **21,6 cm por delante de la cámara y a la altura del ojo** (`UpArm_L depth=0.216 up=-0.006`).
- El hombro está sólo **20,4 cm por detrás del alza** en el eje de visión. Un tirador real tiene el hombro a 55-65 cm por detrás de la mira.
- Como el hombro está rígidamente unido al arma en el rig, **ninguna traslación ni rotación del conjunto puede bajarlo**: la única traslación libre es la profundidad, y para que el hombro saliera del encuadre el alza tendría que estar a ~0,20 m del ojo (el arma pegada a la cara).
- La escala de los brazos (0,669) se deriva de la empuñadura y **no se toca**: subirla haría que la mano no envolviera la empuñadura real de la OWK.

Medido con la métrica `SILUETA` de `--armdiag`: los brazos ocupan **41% del encuadre en ADS** (71% de las bandas laterales inferiores) contra 17% en hip. El arma, 0,9%.

Lo que **sí** se corrigió en esta pasada es que esas masas se lean como brazos: la difusa real del autor las convierte en guantes de cuero con costuras y nudillos en vez de cilindros negros.

La palanca que queda, si se quiere el encuadre de la referencia bodycam, es **bajar la cámara ~12 cm** (1,62 → 1,50 m), que es donde va montada una bodycam real: con eso el hombro cae por debajo del borde inferior. No se ha hecho porque cambia el nivel de ojos del jugador y el usuario lo excluyó explícitamente en esta tarea.

No ampliar el juego para “aprovechar” que una tarea terminó pronto.

---

## 3. Límites técnicos

- **Motor:** Godot 4.7.2 stable.
- **Física:** Jolt, 60 ticks/s, unidades SI.
- **Perfil de desarrollo:** **Mobile** a 1920×1080 en PC y como base de Android.
- Mobile se eligió tras A/B determinista frente a Forward+: misma percepción en las escenas medidas y aproximadamente 20 ms menos por frame en la HD 520. No se eligió por prestigio sino por **calidad visual por milisegundo**.
- **Destino de producción:** PC + Android; el perfil móvil final debe medirse en dispositivo real.
- **Objetivo de rendimiento:** 60 FPS como meta de diseño. Una medición muy por debajo es un problema a investigar, no un estándar nuevo.
- **Autoloads:** `GameAudio`, `ImpactFX`, `Ballistics`.
- **Escena principal:** `scenes/Main.tscn`.

### Rendimiento medido

Perfil completo del rango bajo Mobile en la HD 520, 1920×1080 y vsync off: el cuello dominante siguen siendo las **8 Omni interiores** (~13 ms/frame de las 38 totales; apagarlas sube de 26 a 38 FPS). Sombra direccional y glow son pequeños. Las Omni no se abarataron troceando la sala ni aislando el viewmodel por capas. La palanca pendiente con mayor potencial es dejar de iluminar una sala mayormente estática con ocho Omni dinámicas: evaluar **LightmapGI / horneado real** con captura A/B y benchmark, sin aplanar la imagen.

Estado en el HEAD actual (`--fpsbench --fpsreps=3 --fpsduration=6`, 3 corridas):

| | fps avg | p1 | frametime avg | p95 | max |
|---|---|---|---|---|---|
| baseline completo | 26.06 | 22.32 | 38.37 ms | 44.81 ms | 48.09 ms |

**Coste del viewmodel, medido por diferencia** (misma escena y cámara): ocultar el viewmodel entero ahorra **1.48 ms/frame** (4%); de eso, los brazos son **0.56 ms** y la OWK rígida ~0.05 ms, que está dentro del ruido. Los brazos cuestan poco más que antes aunque ahora lleven sus 4 texturas reales (albedo, normal, oclusión y metallic-roughness): el trabajo sigue siendo skinning, no muestreo de textura.

Antes de cerrar una fase de rendimiento, repetir el perfil completo sobre el HEAD actual. La referencia de ~27 FPS de pasadas anteriores y estos 26.06 FPS no son una regresión: son la misma medida con distinto número de repeticiones en una máquina de 4 núcleos, y el orden de magnitud se mantiene. **Lo que sí es firme es el coste marginal del viewmodel, que es lo que esta pasada podía mover.**

### Autoridades existentes

| Área | Autoridad principal |
|---|---|
| Arranque / escena / tests | `scripts/Main.gd` |
| Laboratorio de diagnóstico | `scripts/DevTools.gd` |
| Jugador / cámara | `scripts/Player.gd` |
| Glock / viewmodel / arma / manos | `scripts/Glock.gd` |
| Resortes | `scripts/Springs.gd` |
| Balística | `scripts/Ballistics.gd` |
| Impactos | `scripts/ImpactFX.gd` |
| Audio | `scripts/GameAudio.gd` |
| Mundo / rango | `scripts/World.gd` |
| Blancos | `scripts/Target.gd` |
| HUD / bodycam post | `scripts/HUD.gd` + `shaders/bodycam.gdshader` |

El laboratorio puede observar, congelar, medir o desactivar temporalmente subsistemas para A/B. **No puede convertirse en una segunda autoridad del comportamiento normal.**

### Señales públicas

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

# ADS / mira visible real
godot4 --headless --path . -- --aimtest

# Penetración + daño + decals
godot4 --headless --path . -- --pentest

# Salida por segunda cara de la geometría (madera + pladur)
godot4 --headless --path . -- --penetrationdiag

# Recarga vacía y táctica
godot4 --headless --path . -- --reloadtest
```

Los cinco tests deben devolver **exit code 0**. Un test verde no reemplaza inspección visual/física cuando el cambio modifica algo perceptual.

### Herramientas del flujo IA

Estas herramientas existen para que el modelo pueda comprobar su propio trabajo. No son features del juego.

```bash
# Geometría, encuadre, corredera, recarga
godot4 --path . -- --geometrydebug

# Diagnósticos específicos de brazos y miras
godot4 --path . -- --armdiag
godot4 --path . -- --sightdiag

# Secuencia reproducible + media
godot4 --path . -- --timeline
bash tools/make_timeline_media.sh

# Estados rápidos de inspección
godot4 --path . -- --probe

# A/B visual determinista: env, hip, ads, shot, casing, reload, slide_back
godot4 --path . -- --visualab --visualout=captures/visual/current

# Disparo/recarga en cámara lenta
godot4 --path . -- --slowmo

# Benchmark real; misma cámara/resolución/duración, vsync off
godot4 --path . -- --fpsbench
godot4 --path . -- --fpsbench --fpsvariant=glow_off,stage_omnis_off --fpsreps=3 --fpsduration=5

# Mix final
godot4 --path . -- --audiocapture

# Preview del mismo viewmodel usado por el juego
godot4 --path . --scene res://scenes/WeaponPreview.tscn
```

**No pases `--rendering-driver vulkan` a secas.** En esta configuración puede forzar Forward+ y saltarse Mobile. Si necesitas forzar renderer, especifica también el método correspondiente.

Las capturas de diagnóstico (`captures/visual/`, `captures/shot/`, `captures/timeline/`) se regeneran y están ignoradas por Git. La única excepción versionada es **`captures/review/`**, la evidencia de auditoría que un revisor remoto necesita para juzgar el encuadre y el estado del viewmodel sin ejecutar el juego.

### Definition of Done

Un cambio no está terminado porque “funciona”. Está terminado cuando:

1. resuelve la causa pedida sin ampliar alcance;
2. los tests relevantes pasan;
3. no crea segunda autoridad, fallback ni arquitectura innecesaria;
4. se midió o inspeccionó el aspecto modificado;
5. física/realismo no retroceden silenciosamente;
6. rendimiento no retrocede sin causa medida y decisión consciente;
7. una optimización visual demuestra con A/B que no degradó apreciablemente nitidez, identidad o realismo;
8. no introduce assets sin licencia/crédito;
9. elimina lo que el cambio volvió obsoleto;
10. el resultado queda **más sólido y más entendible**, no simplemente más complejo.

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

Antes de controles táctiles, migrar entrada a acciones reutilizables. **No duplicar gameplay para Android**: cambia el input, no las reglas del arma o del jugador.

---

## 6. Assets y licencias

- **Arma:** `assets/models/owk19_pistol.glb` — “OWK 19 Pistol 9mm (G19)” de OKgamedev, CC-BY 4.0. Única representación del arma.
- **Brazos y animaciones:** `assets/models/fps_pistol_arms.glb` — “FPS pistol animations” de Cransh, CC-BY 4.0. Única fuente de pose humana.
- **Audio:** Freesound CC0, procesado con `tools/process_audio.sh`.
- **Texturas PBR:** Poly Haven CC0.
- **Código y contenido original de FlowFire:** propietario; los recursos de terceros conservan sus licencias. Ver `LICENSE` y `CREDITS_*.md`.

Nunca sustituir un asset bueno sólo por novedad. Cambiarlo únicamente si mejora de forma visible/medible el resultado o resuelve una limitación real.

Los assets de **primera persona** tienen un estándar más alto que el decorado: arma, manos, brazos, cargador y casquillo ocupan gran parte de la pantalla y no pueden delatar geometría pobre si el objetivo visual es realista. Si un asset limita la silueta/anatomía, se sustituye; no se deforma brutalmente ni se esconde con shaders.

---

## Regla final

**FlowFire no debe impresionar por todo lo que tiene. Debe impresionar por lo absurdamente bien hecho que está lo poco que tiene.**
