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
15. **Rendimiento es parte de la calidad.** No aceptar FPS bajos como precio del realismo, pero tampoco “optimizar” degradando la imagen a ciegas. Primero perfilar y comparar A/B; eliminar trabajo redundante, overdraw, luces/sombras innecesarias, lecturas de pantalla evitables, allocations y coste invisible. Si una técnica visual cara debe cambiarse, sustituirla por una solución de calidad equivalente o mejor, no simplemente apagar calidad.

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

- Glock 19 de alta fidelidad en `assets/models/owk19_pistol.glb` (OWK 19, OKgamedev, CC-BY 4.0): 11 568 tris en 9 piezas rígidas, movidas por la mecánica existente. Se recupera el arma low-poly anterior con `--oldgun`.
- Brazos/manos y animaciones `Grip`, `Idle`, `Shoot`, `Reload` en `assets/models/fps_rig.glb` (rig de J-Toastie). De ese GLB sólo se usan ya los brazos y el esqueleto: su malla de arma no se dibuja.
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
- sustituir assets de primera persona visiblemente low-poly cuando la propia geometría limite el realismo; un shader puede mejorar material y microdetalle, pero no corrige silueta, topología, manos/dedos pobres ni una forma incorrecta;
- eliminar bugs, residuos y contradicciones.

No ampliar el juego para “aprovechar” que una tarea terminó pronto.

---

## 3. Límites técnicos

- **Motor:** Godot 4.7.2 stable.
- **Física:** Jolt, 60 ticks/s, unidades SI.
- **Perfil de desarrollo actual:** **Mobile** a 1920×1080, tanto en PC como en Android.
  Se adoptó tras comparar siete escenas congeladas (entorno, hip, ADS, disparo,
  casquillo, recarga y corredera atrás) contra Forward+: la imagen es
  indistinguible a ojo —0.00% de píxeles por encima de 8/255 en entorno, hip,
  ADS, recarga y corredera atrás, y 0.16% con el casquillo— y cuesta 40.3 ms por
  frame contra 60.4 ms. El glow, que en Forward+ costaba 12.7 ms, en Mobile
  cuesta 0.25 ms dando el mismo halo. No se eligió por prestigio: se eligió por
  calidad visual por frame.
- **Destino de producción:** PC + Android; el perfil móvil final todavía debe medirse en dispositivo real.
- **Objetivo de rendimiento:** 60 FPS como meta de diseño. Una medición muy por debajo de eso es un problema a investigar, no un nuevo estándar de aceptación.
- **Autoloads actuales:** `GameAudio`, `ImpactFX`, `Ballistics`.
- **Escena principal:** `scenes/Main.tscn`.

### Cuello de botella medido (HD 520, 1920×1080, Mobile)

Perfil A/B por subsistema, misma escena, cámara y duración:

| Subsistema | Coste | % del frame |
|---|---|---|
| 8 luces omni del interior | **12.2 ms** | 31% |
| sombra direccional | 2.4 ms | 6% |
| bodycam post | 1.8 ms | 5% |
| viewmodel completo | 1.9 ms | 5% |
| glow | 0.3 ms | 1% |
| niebla | 0.2 ms | <1% |

Las omni son el único cuello de botella grande que queda, y **no se puede
abaratarlas por culling**. Comprobado, no supuesto:

- trocear la sala (suelo, techo y paredes) en 36 mallas en vez de 6, para que
  cada trozo lleve en su lista sólo las luces que le llegan: el coste de las
  omni no cambió (12.27 ms contra 12.24 ms);
- sacar el viewmodel a su propia capa de luz para que las ocho omni no entren
  en su lista: sin ganancia medible, y el arma se oscurecía 1.7–4.4/255, así que
  se descartó.

El coste es intrínseco a ocho omni dinámicas de 9 m alumbrando toda la sala. La
palanca que queda es dejar de renderizarlas en tiempo real: **horneado
(LightmapGI)**, que exige convertir la parte estática de la sala a una escena
editable y generar UV2. No se ha hecho todavía.

Lo que **no** es un problema, medido y descartado: el shader procedural del arma
(4 fbm por píxel) no cuesta nada — sustituirlo por un material plano no ahorra
ni un milisegundo— y el script de animación tampoco.

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

**No pases `--rendering-driver` a secas.** Godot elige el renderer por defecto a
partir del driver de la línea de comandos: si se pasa `--rendering-driver vulkan`
sin `--rendering-method`, fuerza `forward_plus` y **se salta el ajuste del
proyecto**. Comprobado: `godot4 --path . --quit` arranca en Forward Mobile, y
`godot4 --path . --rendering-driver vulkan --quit` arranca en Forward+. Para
forzar un renderer, pasar los dos flags.

```bash
# Geometría, encuadre, exposición real del arma, ciclo de corredera y recarga
godot4 --path . -- --geometrydebug

# Secuencia visual reproducible
godot4 --path . -- --timeline
bash tools/make_timeline_media.sh

# Estados hip / ADS / disparo / recarga
godot4 --path . -- --probe

# Comparación visual A/B determinista entre renderers o entre cambios.
# Congela la escena (time_scale 0, fases y resortes a cero, animación del autor
# en un tiempo exacto, fogonazo y grano del bodycam fijados), así que dos
# corridas dan la MISMA imagen y cualquier diferencia es del cambio evaluado.
# Estados: env, hip, ads, shot, casing, reload, slide_back.
godot4 --path . -- --visualab --visualout=captures/visual/fp   # renderer del proyecto
godot4 --path . -- --visualab --visualout=captures/visual/mob --rendering-method=mobile

# Disparo y recarga en cámara lenta (corredera, casquillo, capas de retroceso)
godot4 --path . -- --slowmo

# Rendimiento real de la escena (no usar headless para juzgar GPU).
# Fija 1920x1080, vsync OFF y mide cada variante A/B con la misma cámara y
# duración. Opciones: --fpsvariant=id1,id2 --fpsreps=N --fpsduration=S
# --fpscapture guarda una captura 1080p por variante.
# --fpsstress aísla el coste de partículas/impact FX con impactos periódicos.
godot4 --path . -- --fpsbench
godot4 --path . -- --fpsbench --fpsvariant=glow_off,stage_omnis_off --fpsreps=3 --fpsduration=5

# Captura del mix final
godot4 --path . -- --audiocapture
```

Para optimización, medir siempre **la misma escena, resolución, cámara y duración**. Hacer cambios de una variable cada vez cuando sea posible. No declarar una mejora por una sola corrida ruidosa: repetir y comparar.

### Definition of Done

Un cambio no está terminado porque “funciona”. Está terminado cuando:

1. resuelve exactamente el problema pedido sin ampliar alcance;
2. los tests relevantes pasan;
3. no crea una segunda autoridad ni arquitectura innecesaria;
4. se midió o inspeccionó el aspecto que modifica;
5. no empeora perceptiblemente la estabilidad ni el rendimiento; una caída >10% requiere causa clara y decisión consciente;
6. una optimización visual demuestra con captura A/B que no degradó de forma apreciable la identidad, nitidez o realismo;
7. no introduce assets sin licencia/crédito;
8. elimina código/documentación obsoleta que el propio cambio deje atrás;
9. el resultado se siente más sólido que antes, no simplemente más complejo.

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

- **Arma:** `assets/models/owk19_pistol.glb` — “OWK 19 Pistol 9mm (G19)” de OKgamedev, CC-BY 4.0 (`--oldgun` recupera la anterior).
- **Brazos y animaciones:** `assets/models/fps_rig.glb` — “Fps Rig” de J-Toastie, CC-BY 3.0. Ver `CREDITS_MODELS.md`.
- **Audio:** Freesound CC0, procesado con `tools/process_audio.sh`. Ver `CREDITS_AUDIO.md`.
- **Texturas PBR:** Poly Haven CC0. Ver `CREDITS_TEXTURES.md`.
- **Código del proyecto:** MIT. Ver `LICENSE`.

Nunca sustituir un asset bueno sólo por novedad. Cambiarlo únicamente si mejora de forma visible/medible el resultado o resuelve una limitación real.

Los assets de **primera persona** tienen un estándar más alto que el decorado: arma, manos, brazos, cargador y casquillo ocupan gran parte de la pantalla y no pueden verse deliberadamente low-poly si el objetivo visual es realista. Se permite buscar y sustituir/remapear estos assets por otros de mayor fidelidad con licencia comercial compatible, siempre midiendo coste de memoria/render y conservando la lógica y animación correctas.

---

## Regla final

**FlowFire no debe impresionar por todo lo que tiene. Debe impresionar por lo absurdamente bien hecho que está lo poco que tiene.**
