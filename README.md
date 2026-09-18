# FlowFire

**Un laboratorio FPS de una sola pistola: la Glock 19.** El proyecto existe para
profundizar una cadena, y sólo esa cadena:

```
Glock -> disparo -> ciclo mecanico -> proyectil -> material
      -> penetracion/rebote -> reaccion fisica -> sonido -> feedback visual
```

Todo lo que no haga esa cadena más convincente o más barata de mantener no
pertenece a `main` todavía. No hay multijugador, ni lobby, ni mapa: hay un rango
donde experimentarla.

El proyecto se mantiene **100% con IA**, así que la eficiencia incluye **menos
búsqueda mental para la siguiente IA**: cada responsabilidad importante tiene un
módulo obvio, una sola autoridad y un nombre explícito. Separar
responsabilidades cuando eso reduce la búsqueda **no** es sobreingeniería;
sobreingeniería es apilar `Manager -> Service -> Adapter -> EventBus` sin una
necesidad real.

## Contrato

1. **Una sola autoridad por comportamiento y por transformación mecánica.** Una
   pieza no puede recibir el mismo transform de la animación, del procedural y de
   otro sistema a la vez. Si dos capas pueden escribir lo mismo, el ownership
   queda escrito junto al código correspondiente, no aquí.
2. **Una sola ruta de producción.** Sin fallbacks, flags ni legacy activo. Git es
   el rollback.
3. **Nada de arquitectura especulativa:** ni managers, ni event buses, ni
   interfaces genéricas, ni capas "por si luego sirven". Tampoco un sistema de
   armas genérico mientras haya una sola arma.
4. **Cambios locales antes que rediseños.** La causa se arregla donde está.
5. **No dividir archivos por tamaño**, sino cuando una IA necesita buscar menos.
6. **Los detalles técnicos viven junto al código que los usa.** README = reglas
   estables; código = verdad técnica actual; Git = historia y también el museo de
   los assets y herramientas que ya no se usan.
7. **No inventes alcance.** El alcance lo fija la sección de abajo; nada de
   features nuevas por iniciativa propia.
8. **Assets:** licencia compatible (nunca NonCommercial) y crédito en
   `CREDITS_*.md` en el mismo cambio. Un asset = una representación: el `.glb`
   lleva sus texturas dentro y el importador no deja copias sueltas en el repo.
9. **Elimina lo que tu cambio vuelva obsoleto:** código, flags, comentarios,
   docs y herramientas que ya no se usan. Una herramienta rota es peor que no
   tener herramienta.
10. **Mantén este README corto y verdadero.** Si algo aquí ya no es cierto, se
    corrige en el mismo cambio.

**Prioridad:** correctitud → profundidad física / sensación → estabilidad →
rendimiento → calidad audiovisual → features.

## Arquitectura

| Responsabilidad | Autoridad |
|---|---|
| Arranque y escena | `scripts/Main.gd` |
| Mecánica del arma: munición, recámara, gatillo, cadencia, corredera, recarga, inspección | `scripts/Glock.gd` |
| Piezas del arma (Frame, Slide, Magazine, puntos) y su escala real | `scripts/GlockWeapon.gd` |
| Viewmodel: montaje del arma, pose, ADS, encuadre | `scripts/GlockViewmodel.gd` |
| Retroceso y peso: el arma en el agarre + cesión del conjunto | `scripts/GlockRecoil.gd` |
| Fogonazo, luz de boca, humo | `scripts/WeaponFX.gd` |
| Audio | `scripts/GameAudio.gd` |
| Balística, penetración, rebote | `scripts/Ballistics.gd` |
| Impactos | `scripts/ImpactFX.gd` |
| Vaina expulsada | `scripts/Shell.gd` |
| Jugador y cámara | `scripts/Player.gd` |
| HUD y post bodycam | `scripts/HUD.gd` + `shaders/bodycam.gdshader` |
| Mundo y rango (incluidas las latas de cascara fina) | `scripts/World.gd` |
| Blancos y cajas reactivas | `scripts/Target.gd`, `scripts/Crate.gd` |

Autoloads: `GameAudio`, `ImpactFX`, `Ballistics`. Escena: `scenes/Main.tscn`.
Señales del arma: `shot_fired`, `ammo_changed(mag, chamber, reserve, reloading)`.

**Referencia: Glock 19 Gen5 stock** (185 x 128 x 30 mm, 15 tiros, ~12,5 mm de
disparador, 39 mm de corredera). **La pistola va en metros.** El GLB canonico
llega ya en metros y Godot solo valida; la malla actual mide 174 mm (11 mm
corta: aproximacion visual declarada, no se estira). El encuadre se calibra
alrededor. Lo comprueba `tools/check_weapon.gd`.

**El arma no está en ningún esqueleto.** Es un árbol de piezas rígidas: `Frame`,
`Slide`, `Magazine`, `Trigger`, `Barrel`, los herrajes y los puntos de boca,
miras y puerto. Mover la corredera, el cargador o el gatillo es escribir un
`transform`. El gatillo gira sobre su pasador y el cañón cae cuando el arma se
abre; las dos cosas se miden sobre la malla, no se suponen. `Trigger` y `Barrel`
siguen siendo opcionales: si faltan, el arma funciona sin ellos.

**Los brazos no están en producción.** El asset anterior (13,4 MB, 78 huesos y
cinco clips cuyos instantes había que remedir en cada cambio) está congelado
fuera del árbol; Git lo conserva. La pistola flota montada en el pivote. Cuando
el arma esté cerrada entrarán unos brazos limpios como **capa de presentación**,
nunca como columna de la mecánica.

**Una pistola.** Glock 19. No hay tabla de armas ni código por arma a propósito.

### Cómo se comporta la bala

- La forma de colisión manda: la salida se resuelve analíticamente en cajas,
  cilindros y esferas, y el espesor que atraviesa la bala es geometría real, no
  metadata.
- Un cuerpo **fino** (una lata) declara `thin_shell` + `wall_thickness`: pierde
  energía en dos paredes delgadas y no en 66 mm de metal macizo. Jolt se encarga
  de que ruede y se voltee.
- Sin trazadoras: una Glock normal no las dispara. El proyectil no deja estela.

### Dónde se pide cada ajuste

| Petición | Un solo sitio |
|---|---|
| "el recoil se ve falso" / "que pese más" | `scripts/GlockRecoil.gd`, 3 constantes juntas |
| "el arma está mal encuadrada" | `GRIP_POS` / `GRIP_ROT` en `GlockViewmodel.gd` |
| "la corredera no llega / recorre de más" | `SLIDE_TRAVEL` en `GlockWeapon.gd` |
| "el cargador sale por donde no debe" | `MAGAZINE_OUT_AXIS` / `MAG_TRAVEL` en `GlockWeapon.gd` |
| "la recarga va a destiempo" | los `RELOAD_*_T` de `Glock.gd` (segundos reales de la mecánica) |
| "una lata no reacciona como debería" | `penetration_resistance` / `wall_thickness` en `World.gd` |

Invariantes objetivas: `tools/check_weapon.gd` (malla en metros, capacidad 15,
Muzzle bajo Barrel, corredera, brocal, gatillo sobre su pasador, caida del canon).
Inspector del asset: `tools/check_viewmodel.gd` (poses a PNG, sin mecanica);
sonda CPU: `tools/check_fps.gd` (no GPU real). La preparación del asset es un solo paso:
`tools/build_g19_parts.py` parte la malla del autor (que trae el arma armada y
despiezada a la vez) en `Frame`, `Slide`, `Magazine`, `Trigger` y `Barrel`, y
reasienta los orígenes de cada pieza.
Prohibido verificar en headless para lo visual: para mirar se abre Godot en la
pantalla del usuario (`:0`).

## Workflow IA + usuario

- **La IA abre el juego en tu pantalla, toma capturas y juzga.** Si algo se ve
  mal, la IA ejecuta Godot en `:0`, saca sus propias capturas de esa pantalla y
  juzga sobre ellas. Nunca pide al usuario imágenes de lo que puede ver sola.
- **Las capturas no se versionan.** `captures/` está ignorado por Git: se generan
  para mirar, se miran y se borran. Una hoja de revisión es evidencia de trabajo,
  no un asset.
- **Ciclo:** cambio pequeño → la IA lo verifica en el juego con capturas →
  commit/push → el usuario valida en su Godot → feedback → corregir.
- **Honestidad antes que avance.** Si algo atrasa el proyecto, la IA lo dice y
  propone una forma mejor de reemplazarlo. Prohibido decir "ya quedó" sin
  haberlo verificado en el juego.
- **Tests:** no se ejecutan automáticamente. Una comprobación automática solo se
  justifica si el usuario la pide explícitamente o autoriza una invariante
  concreta (pregunta objetiva que el usuario no responde mejor mirando o
  escuchando, pequeña y atada a esa invariante).
- **Comentarios:** explican invariantes actuales y el porqué de una decisión no
  obvia. Un valor calibrado puede decir `CALIBRADO: razón actual`, pero no cita
  herramientas ni experimentos que ya no existen.

## Alcance

El renderer es **Mobile** (también para Android), pero hoy lo que manda es lo que
se ve y se siente en el rango. Un mapa de juego esta fuera de alcance; ampliar
el rango y anadir estaciones de prueba esta dentro (instrumento de medicion).
**Fuera de alcance ahora mismo:** multijugador, lobby, mapa, controles Android
finales, vida de blancos, puntuación y más de una arma.

---

**FlowFire no debe impresionar por todo lo que tiene, sino por lo absurdamente
bien hecho que está lo poco que tiene.**
