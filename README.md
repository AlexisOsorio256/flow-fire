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
- Brazos/manos y animaciones de pistola en `assets/models/fps_pistol_arms.glb` (Cransh): única fuente de pose humana. El cuerpo del arma cuelga de `PBody` y el cargador de `Pmag`. El GLB venía con `KHR_materials_pbrSpecularGlossiness`, que Godot no implementa: **su textura difusa se descartaba entera** y los brazos salían como geometría gris plana. Está convertido a metallic-roughness (receta reproducible en `CREDITS_MODELS.md`); ahora el guante, el normal y la rugosidad son los del autor y el código sólo tiñe el albedo. **No es utilizable en un producto comercial**: la malla de brazos es `FP Arms` de bumstrum, que se publica como CC-BY-NC. Ver el apartado de licencia más abajo y `CREDITS_MODELS.md`.
- Montaje de brazos con **escala uniforme derivada de geometría**, sin estiramientos anatómicos para ocultar hombros.
- ADS resuelto desde la **mira trasera y delantera visibles de la OWK**; los marcadores geométricos son fuente y la pose es derivada, no al revés. La distancia ojo → alza (0,54 m) se eligió midiendo el encuadre: ver "Encuadre del viewmodel en ADS".
- Sin crosshair ni hitmarker visual: se apunta con las miras reales del arma.
- Corredera, gatillo, cargador, recarga, expulsión de casquillo y recamarado gobernados por el estado mecánico.
- Balística con gravedad, arrastre, subpasos, penetración, rebotes y daño por zona. **La salida ya se calcula desde la geometría real del volumen**, no desde metadata de grosor: se resuelve el intervalo de intersección de los tres *slabs* de cada `BoxShape3D` del collider y la cara lejana es la salida. Limitación concreta y deliberada: **`_find_exit_geometry()` sólo entiende `BoxShape3D`**; con cualquier otra forma no hay salida demostrable y el proyectil se detiene. Es suficiente para el rango actual (paneles y muros son cajas) y no se generaliza hasta que exista un caso real.
- Jolt para jugador, blancos y casquillos.
- Cámara bodycam con sway/bob/breathing/recoil y post-proceso sin blur deliberado.
- Audio con buses `Weapons` / `World` y techo de seguridad en Master. **Sin compresores de bus**: se midió que no protegían nada y que su release devolvía ganancia durante la cola del disparo. Los 5 disparos son tomas reales de Glock 18c (Sonniss GDC 2016, royalty-free comercial) y **se cortan de la grabación original en su ataque medido**, con la cola acotada al hueco real hasta el disparo siguiente (`tools/process_audio.sh`, tabla `SHOT_CUTS`); la grabación original se versiona en `assets/audio/source/`. La foley es CC0. Todos los WAV se alinean a su ataque real con el mismo script: **los 15 archivos atacan dentro de los primeros 2 ms**.
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

### Encuadre del viewmodel en ADS

El encuadre de ADS se corrigió midiendo, no ajustando a ojo, y la causa no era
la que parecía.

**Lo que estaba mal.** En ADS se veían dos masas negras enormes a los lados que
se comían la pantalla. Medido con la métrica `SILUETA` de `--armdiag`, los
brazos ocupaban **41,2% del encuadre y 70,9% de las bandas laterales
inferiores**, contra 0,9% del arma.

**Qué son esas masas.** No son los hombros. El análisis de la malla (skinning
conforme al glTF, peso dominante por vértice) sitúa en las esquinas inferiores
las **cadenas de antebrazo**, en concreto sus huesos de torsión:
`BoneTwist_01.R_013` (550 vértices, la región más grande de toda la malla) y
`BoneTwist_02.R_012` hacia la derecha, `BoneTwist_01.L_07` y `BoneTwist_02.L_06`
hacia la izquierda. Los huesos llamados `Forearm_L/R` sólo llevan ~180 vértices
(el codo); el bulto del antebrazo **no** está en el hueso que su nombre sugiere.

**Cuál era la causa real.** La distancia ojo → mira trasera estaba en **0,42 m**.
Con el arma tan pegada a la cara, toda la geometría entre la mano y el hombro
queda a ~0,2 m de la cámara y su tamaño angular se dispara. Al alejar el ojo del
alza, esa masa se aleja *más* que las manos (que ya estaban lejos), así que el
reparto arma/brazos se corrige solo. Barrido medido:

| ojo → alza | brazos | bandas laterales inferiores |
|---|---|---|
| 0,42 m (antes) | 41,2% | 70,9% |
| 0,48 m | 34,8% | 57,2% |
| 0,52 m | 30,9% | 45,5% |
| **0,54 m (actual)** | **28,8%** | **36,5%** |
| 0,56 m | 26,5% | 29,2% |
| 0,62 m | 20,4% | 13,9% |

Se para en 0,54 m y no en 0,62 m porque a partir de ahí el alza trasera (unos
30 px) deja de leerse. El porcentaje del **arma** baja en la misma proporción
(0,9% → 0,4%) porque mira al frente y se ve de canto: no es que el arma se aleje
del centro, es que se acorta la profundidad. La mira sigue centrada (AIMTEST:
0,2 mm, 0,35 mrad) y HIP no cambia (17,4% / 27,6%). La escala de los brazos
(0,6694) sigue **derivada** de la empuñadura real de la OWK, con residuo 0,0 mm:
no se estiró nada para compensar.

Efecto secundario medido: el antebrazo izquierdo pasa de quedar **fuera** del
encuadre a quedar **dentro** con 147 px de margen, así que la pose también se
lee mejor que antes.

**Lo que sigue limitado, y no se disimula.** El encuadre ya no lo domina el
brazo, pero la geometría del asset sigue teniendo dos defectos reales que no se
arreglan con encuadre:

1. Los antebrazos se **cortan demasiado cerca de la mano**. Medido en espacio de
   cámara (ojo a 0,54 m del alza): las manos quedan a 0,58-0,66 m, pero la manga
   del antebrazo sólo llega a 0,245-0,35 m, y su anillo de corte mira al objetivo
   a **0,31-0,33 m**. Es el trozo de brazos más cercano a la cámara, así que se
   proyecta enorme y se le ve el corte. No es un agujero de la malla: son dos
   anillos de frontera de 100 vértices cada uno (~300 mm) que forman parte del
   skin visible, no un borde suelto.
2. La manga es **corta en proporción al arma**: el tramo hombro→mano mide ~24 cm
   escalado, cuando un tirador real tiene el hombro a 45-55 cm de la empuñadura.
   Por eso, por mucho que se aleje el ojo, el hombro entra en pantalla si se
   quiere que el arma domine. Es geometría, no ajuste.

**Dos intentos de arreglar (1) sin cambiar de asset, los dos descartados con
medición:**

- **Reescritura del GLB con Blender**: rompe el skinning. El asset reexportado
  deja la silueta en 0,0% y manda 6 071 vértices detrás de la cámara. La jerarquía
  de este GLB (`Armature` a escala 100 bajo un nodo a 0,01) hace que Blender
  reconstruya el reposo a 100x y las traslaciones de la animación se disparen.
- **Edición directa del buffer del GLB** (sin Blender, conservando los 81 huesos
  y las 5 animaciones por construcción, verificado). Tapar los anillos con un
  abanico al centroide sale como **una tapa plana gris**: la cara nueva no tiene
  un UV útil y su normal apunta al objetivo. Reducir y hundir el anillo para que
  el corte deje de mirar a la cámara **arruga el cuero** (los vértices del anillo
  son piel visible, no un borde oculto). Los dos resultados se revirtieron.

Ninguno de los dos se queda. La conclusión medida es que **este defecto no se
arregla parchando la malla: hace falta sustituirla.** Un FOV más estrecho también
lo taparía, pero está excluido explícitamente y además encogería el arma, que es
justo lo contrario de lo que se pide.

Los dos se resolverían sustituyendo la malla. Lo que lo bloquea no es criterio
artístico sino **licencia** (ver siguiente apartado) y que no hay forma de
descargar los candidatos limpios desde este entorno.

### Licencia de los brazos: pendiente de sustituir

**La malla de brazos en uso no es utilizable en un producto comercial.** No es
una sospecha: está en la propia descripción del asset que el proyecto usa.

- `assets/models/fps_pistol_arms.glb` se declara **CC-BY 4.0** (Cransh), pero la
  descripción de esa misma página dice literalmente *"Hands - FP Arms by
  @bumstrum"*.
- `FP Arms` de bumstrum/DJMaesen
  (https://sketchfab.com/3d-models/8416c380544949bb9b224278819cbe6b) es
  **CC Attribution-NonCommercial** (`by-nc/4.0`, "No commercial use"), y su
  recuento de caras (14 852) coincide con la malla de brazos de este GLB.
- Una licencia CC-BY concedida sobre un derivado **no puede sustituir** la
  licencia del original. Cransh relicencia como CC-BY algo que aguas arriba es
  NC (lo hace en varios de sus packs, no sólo en éste).

FlowFire será comercial, así que **NC no es aceptable**. El reemplazo está
investigado y verificado (ver `CREDITS_MODELS.md`), pero no se ha integrado.

No ampliar el juego para "aprovechar" que una tarea terminó pronto.

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
| baseline completo | 25.11 | 21.23 | 39.83 ms | 47.09 ms | 92.81 ms |

**Coste del viewmodel, medido por diferencia** (misma escena y cámara): ocultar el viewmodel entero ahorra **2.03 ms/frame** (5,4%); de eso, los brazos son **0.49 ms** y la OWK rígida está dentro del ruido (ocultar sólo el arma *sube* el frametime medio, es decir, no se puede separar de la varianza). Los brazos cuestan poco más que antes aunque ahora lleven sus 4 texturas reales (albedo, normal, oclusión y metallic-roughness): el trabajo sigue siendo skinning, no muestreo de textura. Nada de esto cambió con el retrabajo de audio, que no toca el render.

Antes de cerrar una fase de rendimiento, repetir el perfil completo sobre el HEAD actual. En esta máquina de 4 núcleos y GPU integrada la dispersión es grande (`fps_min` oscila entre 9 y 19 entre variantes que deberían medir casi igual), así que **el promedio de 3 corridas sirve para detectar regresiones grandes, no para comparar décimas**. Lo que sí es firme es el coste marginal del viewmodel, que es lo que estas pasadas podían mover.

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

# Brazos (encuadre, huesos y SILUETA) y miras
#   --armdiag imprime, por hueso, profundidad/lateral/altura respecto a la
#   cámara y su margen en pantalla, y ademas la linea SILUETA: que porcentaje
#   del encuadre 16:9 ocupan los brazos y el arma y cuanto de las bandas
#   laterales inferiores. Es la medida que convierte "los hombros salen
#   demasiado" en un numero comparable entre cambios.
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
- **Brazos y animaciones:** `assets/models/fps_pistol_arms.glb` — “FPS pistol animations” de Cransh, CC-BY 4.0 **en la etiqueta**, pero la malla de brazos es `FP Arms` de bumstrum (CC-BY-**NC**). **Bloquea el lanzamiento comercial**; candidatos de reemplazo ya verificados en `CREDITS_MODELS.md`.
- **Audio:** disparos de Sonniss #GameAudioGDC (royalty-free comercial, sin atribución obligatoria) y foley CC0 de Freesound. Todo procesado con `tools/process_audio.sh`.
- **Texturas PBR:** Poly Haven CC0.
- **Código y contenido original de FlowFire:** propietario; los recursos de terceros conservan sus licencias. Ver `LICENSE` y `CREDITS_*.md`.

Nunca sustituir un asset bueno sólo por novedad. Cambiarlo únicamente si mejora de forma visible/medible el resultado o resuelve una limitación real.

**Una etiqueta CC-BY no basta para los assets de primera persona.** El campo de los packs de brazos FPS en Sketchfab está lleno de derivados de `FP Arms` (bumstrum, CC-BY-NC) reetiquetados como CC-BY por quien los sube. Antes de integrar uno hay que leer la descripción buscando `@bumstrum` / `fp-arms` **y** remontar la licencia de la malla original, no sólo la del pack.

Los assets de **primera persona** tienen un estándar más alto que el decorado: arma, manos, brazos, cargador y casquillo ocupan gran parte de la pantalla y no pueden delatar geometría pobre si el objetivo visual es realista. Si un asset limita la silueta/anatomía, se sustituye; no se deforma brutalmente ni se esconde con shaders.

---

## Regla final

**FlowFire no debe impresionar por todo lo que tiene. Debe impresionar por lo absurdamente bien hecho que está lo poco que tiene.**
