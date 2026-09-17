# FlowFire Bodycam — Godot 4 + Jolt

> Juego pequeño, calidad obsesiva. FlowFire no compite por cantidad de sistemas:
> compite porque lo poco que hace debe sentirse excepcional.

---

## 1. Qué es FlowFire

Un FPS **bodycam** compacto y deliberadamente limitado. Hoy es un **vertical
slice de combate y entrenamiento** en un rango pequeño: **una** pistola, **un**
viewmodel, **una** autoridad mecánica, balística con penetración real y audio de
grabaciones reales. Todo el código se mantiene con IA.

La profundidad viene de cómo reaccionan **arma, proyectil, material, cuerpo,
cámara y sonido**, no de acumular features.

---

## 2. Reglas de arquitectura

1. **Una sola autoridad por comportamiento.** No duplicar estado ni lógica de
   arma, daño, audio, input, cámara, física o animación mecánica.
2. **Una sola ruta de producción. Sin fallbacks ni legacy activo.** Cuando un
   reemplazo está validado, se elimina el camino anterior. Git es el rollback.
3. **Nada de arquitectura especulativa.** Sin frameworks de armas, event buses,
   managers, interfaces genéricas ni preparar rifles futuros. Tenemos una pistola.
4. **No dividir archivos sólo porque crecieron.** Refactorizar sólo si reduce
   carga cognitiva o acoplamiento reales. Un archivo extraído no puede tener una
   segunda copia de munición, recámara, corredera, recarga ni cadencia: recibe
   estado de su autoridad.
5. **Cambios locales antes que rediseños.** La causa se arregla donde está.
6. **No inventes alcance.** Solo lo pedido o lo necesario para corregir un
   problema demostrado. **No tocar por iniciativa propia:** multijugador, mapa,
   LightmapGI, penetración/balística, UI, lobby, controles Android ni features nuevas.
7. **Assets:** licencia compatible (nunca NonCommercial) y crédito en
   `CREDITS_*.md` en el mismo cambio. Una etiqueta CC-BY no basta en primera
   persona: los packs de brazos FPS suelen derivar de `FP Arms` (bumstrum, NC).
8. **Android manda junto con PC.** Que algo funcione en escritorio no demuestra
   que sea viable en teléfono.
9. **Elimina lo que tu cambio vuelva obsoleto:** código, flags, assets,
   comentarios y documentación muerta no se acumulan.
10. **Mantén este README corto y verdadero.** Corrige lo viejo; no lo archivas aquí.

**Prioridad:** correctitud → profundidad física / sensación → estabilidad →
rendimiento → calidad audiovisual → features. La calidad perceptual y la
eficiencia son criterios de aceptación, no sliders que se cambian a ciegas.

---

## 3. Regla de trabajo (IA + usuario)

El usuario está disponible como **evaluador visual y auditivo en tiempo real**.
Aprovéchalo.

- **Problemas perceptuales:** cambia UNA cosa → pide al usuario que lo pruebe →
  feedback concreto → corrige → vuelve a probar. Es más rápido y más fiable que
  deducir sensación desde capturas aisladas.
- **Mide** sólo cuando la pregunta sea objetiva y la respuesta no evidente
  (alineación, frametime, dos transitorios indistinguibles, geometría que se
  atraviesa). **No medir por ceremonia.**
- **Test proporcional al cambio:** aimtest para ADS, reloadtest para recarga,
  mirar para lo visual, escuchar para lo audible, fpsbench para rendimiento.
  La suite completa sólo al cerrar una etapa grande.
- **Capturas:** nunca 1 FPS para estudiar un disparo. Si hace falta inspección
  automática de un evento corto, tira de 8–16 frames en slow motion. Para
  comportamiento general, el usuario puede enviar vídeo.
- **Física, profundidad y eficiencia son restricciones simultáneas.**

---

## 4. Producto objetivo y alcance

- **PC + Android.**
- **4 vs 4**, un mapa pequeño y muy trabajado.
- Combate bodycam con balística, físicas, audio, materiales e impactos pulidos.
- **Mini entrenamiento** derivado del rango actual y **lobby muy simple**.
- **Multijugador** sólo cuando el núcleo local, el rendimiento y las reglas de
  partida estén sólidos, y **sólo cuando el usuario lo ordene**.

Fuera de alcance: mundo abierto, campaña, vehículos, loot, crafting, inventario,
economía, battle pass, tienda, clanes, chat, ranking, espectador, replays,
decenas de armas o mapas.

---

## 5. Autoridades actuales

| Área | Autoridad |
|---|---|
| Arranque / escena / tests | `scripts/Main.gd` |
| Laboratorio de diagnóstico | `scripts/DevTools.gd` |
| Jugador / cámara | `scripts/Player.gd` |
| Arma: mecánica y viewmodel | `scripts/Glock.gd` |
| Resortes | `scripts/Springs.gd` |
| Balística | `scripts/Ballistics.gd` |
| Impactos | `scripts/ImpactFX.gd` |
| Audio | `scripts/GameAudio.gd` |
| Mundo / rango | `scripts/World.gd` |
| Blancos | `scripts/Target.gd` |
| HUD / post bodycam | `scripts/HUD.gd` + `shaders/bodycam.gdshader` |

El laboratorio puede observar, congelar, medir o desactivar subsistemas para A/B.
**No puede convertirse en una segunda autoridad del comportamiento normal.**

Señales públicas: `ammo_changed(mag, chamber, reserve, reloading)`,
`shot_fired`, `target_hit(zone)`.

---

## 6. Asset y viewmodel actual

- **`assets/models/full9mm_2k.glb`** — “9mm Pistol | First Person Animations” de
  **1Matzh**, CC-BY 4.0 (cadena verificada hasta **Urpo** y **Blue-Spirit**,
  ambas CC-BY 4.0). **29 321 tris** (14 312 manos + 6 164 antebrazos + 8 357
  arma), 928 huesos, **10 animaciones** (Idle, Idle_2, Walk, Run, Fire, Reload,
  Reload_Empty, Inspect, Equip, Unequip). Trae **brazos y arma ya agarrados y
  animados en un solo rig**: es la única representación de arma y manos.
- Texturas 4096² bajadas a 2048 (`tools/downscale_glb_textures.py`) para Mobile.
- Cadena en runtime: `Camera → WeaponRig → Glock → PoseRoot → WristPivot →
  RecoilNode → ArmsMount → ArmsRoot (GLB) → Skeleton3D`.
- Reparto: la **lógica** manda munición, corredera, gatillo, cadencia y recarga;
  las **animaciones del asset** mandan la pose humana (manos, muñecas, brazos) y
  arrastran el arma. Las pistas de corredera, gatillo y del hueso del arma en
  `Fire` se eliminan al cargar (`_strip_mechanical_tracks`), así que la mecánica
  visible y la lógica son la misma realidad.
- **Mira, boca y puerto cuelgan de la corredera real** (`BoneAttachment3D` sobre
  `Slidder_919`): el ADS, el fogonazo, la balística y la vaina leen el arma de
  verdad, no una copia.

---

## 7. Estado actual

- **ADS resuelto desde la geometría real** (línea de mira → eje de cámara,
  corrección de canto con el hueso `Slidder`), a **0,54 m** ojo→alza.
  `--aimtest` mide **5,3 mm / 9,79 mrad** de desvío máximo, verde frente al
  criterio de 6 mm: no es error cero.
- **Corredera y gatillo gobernados por la lógica.** Ciclo de corredera
  **calibrado** a ~59 ms (recorrido real de G19: 39 mm), con dos transitorios
  reales distintos: tope trasero y vuelta a batería. El latigazo del arma en el
  disparo es físico (el clip `Fire` ya no mueve el hueso del arma).
- **Recarga** con los instantes clavados a las claves del rig (0,30 / 2,50 /
  2,90 s; totales 3,20 s táctica y 4,00 s vacía) y un rebote breve de muñeca al
  asentar el cargador, reutilizando el resorte de retroceso existente.
- **Audio:** buses `Weapons` / `World`, sin compresores de bus (medido: no
  protegían nada). Los 5 disparos son tomas reales de Glock 18c (Sonniss GDC
  2016) cortadas en su ataque medido; el estampido recupera el dominio sobre el
  mecánico dentro de cada muestra. Los 15 WAV atacan dentro de los primeros 2 ms.
  El blast actual **gusta: conservarlo**.
- **Vaina** procedural (9×19: 19,15 × 4,9 mm) expulsada desde el puerto real.
- **Escala manos/arma:** `--gundiag` mide el cociente **0,96×** en el mismo
  espacio y misma pose (105,5 mm de arma / 101,8 mm de manos en hip). Manos y
  arma son coherentes entre sí; **no hay desajuste de 12×** (esa cifra vieja
  comparaba espacios distintos y era falsa).

### Problemas realmente abiertos

- **Fogonazo.** Cuelga de la boca de la corredera (correcto) y su presentación
  vive en `scripts/WeaponFX.gd`: núcleo emisivo breve sobre el eje del cañón +
  gases irregulares con blend aditivo cuyo brillo cae del eje hacia fuera (así
  el contorno del poliedro no dibuja nada). Sustituye a la pieza naranja sólida
  anterior; **pendiente del veredicto perceptual del usuario** en hip y ADS.
  Sigue en curso: núcleo más breve/caliente, forma irregular, volumen pequeño,
  gases que nacen de la boca, viable en Mobile.
- **Sensación de disparo / peso.** Recoil, muñeca, recuperación, cámara y sonido
  mecánico se profundizan **por iteración humana**, una cosa cada vez.
- **Recarga:** el rebote al asentar está; falta saber si el conjunto se siente
  ligero y, si es así, qué contacto falta (sonido, timing, movimiento, transición).
- **Coste del viewmodel nuevo sin medir.** La última medida por diferencia
  (2,03 ms/frame con el rig anterior) no se extrapola: hay que reproducirla con
  29 321 tris y 928 huesos antes de cerrar una fase de rendimiento.
- **Iluminación del rango.** El cuello medido son las **8 Omni interiores**
  (~13 ms/frame de 38). No se toca por iniciativa propia; la palanca pendiente
  sería LightmapGI con A/B y benchmark, sin aplanar la imagen.

---

## 8. Límites PC + Android

- **Motor:** Godot 4.7.2 stable. **Física:** Jolt, 60 ticks/s, unidades SI.
- **Perfil de desarrollo:** **Mobile** a 1920×1080 en PC y como base de Android
  (elegido por A/B: misma percepción y ~20 ms menos por frame en la HD 520).
- **Destino:** PC + Android; el perfil móvil final debe medirse en dispositivo real.
- **Objetivo:** 60 FPS de diseño. Muy por debajo es un problema a investigar, no
  un estándar nuevo.
- **Autoloads:** `GameAudio`, `ImpactFX`, `Ballistics`. **Escena:** `scenes/Main.tscn`.

---

## 9. Herramientas

No son features del juego: existen para que la IA compruebe su propio trabajo.
`godot4 --path . -- <flag>` (con `--headless` para los tests).

| Flag | Para qué |
|---|---|
| `--autotest` | disparo, blanco, daño, consumo y recamarado |
| `--aimtest` | ADS / mira visible real |
| `--reloadtest` | recarga vacía y táctica |
| `--pentest` / `--penetrationdiag` | penetración, daño, decals / salida por segunda cara |
| `--geometrydebug` | geometría, encuadre, corredera, recarga |
| `--gundiag` | rig, piel, miras, muñeca (escala manos/arma) |
| `--armdiag` / `--sightdiag` | silueta de brazos en % de encuadre / línea de mira vs eje |
| `--recoilprobe` / `--firecurve` | retroceso real del disparo / curva de `Fire` sola |
| `--visualab --visualout=…` | A/B visual determinista (env, hip, ads, shot, casing, reload) |
| `--slowmo` | disparo/recarga en cámara lenta |
| `--audiocapture` | mix final |
| `--fpsbench --fpsreps=3 --fpsduration=6` | benchmark real, misma cámara/resolución, vsync off |

Los 5 tests (`autotest`, `aimtest`, `reloadtest`, `pentest`, `penetrationdiag`)
deben devolver **exit code 0**. Un test verde no sustituye la inspección visual o
física cuando el cambio es perceptual. Importar/compilar: `godot4 --headless
--path . --editor --quit`.

**No pases `--rendering-driver vulkan` a secas:** puede forzar Forward+ y saltarse
Mobile. Si necesitas forzar renderer, especifica también el método.

Las capturas de diagnóstico (`captures/visual/`, `captures/shot/`,
`captures/timeline/`) se regeneran y están ignoradas por Git. La única excepción
versionada es `captures/review/`, la evidencia que un revisor remoto necesita
para juzgar encuadre y estado del viewmodel sin ejecutar el juego.

**Definition of Done:** la causa pedida resuelta sin ampliar alcance; tests
relevantes en verde; sin segunda autoridad ni fallback; aspecto modificado
medido o inspeccionado; física y rendimiento sin retroceso silencioso; assets con
licencia y crédito; y lo obsoleto eliminado.

---

## 10. Controles actuales

Provisionales de escritorio: `WASD` mover · `Mouse` mirar · `Click izq`
capturar/disparar · `Click der` ADS · `R` recargar · `F` inspeccionar · `Esc`
liberar mouse.

Antes de controles táctiles, migrar la entrada a acciones reutilizables. **No
duplicar gameplay para Android:** cambia el input, no las reglas del arma o del
jugador.

---

## Regla final

**FlowFire no debe impresionar por todo lo que tiene. Debe impresionar por lo
absurdamente bien hecho que está lo poco que tiene.**
