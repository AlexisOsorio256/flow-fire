# FlowFire

FPS **bodycam** compacto y deliberadamente limitado. PC + Android. Hoy es un
**vertical slice de combate y entrenamiento**: una pistola, un viewmodel, un
mapa.

El proyecto se mantiene **100% con IA**, así que la eficiencia incluye **menos
búsqueda mental para la siguiente IA**: cada responsabilidad importante tiene un
módulo obvio, una sola autoridad y un nombre explícito. Separar
responsabilidades cuando eso reduce la búsqueda **no** es sobreingeniería;
sobreingeniería es apilar `Manager -> Service -> Adapter -> EventBus` sin una
necesidad real.

## Contrato

1. **Una sola autoridad por comportamiento y por transformación mecánica.** Una
   pieza no puede recibir el mismo hueso o transform de la animación, del
   procedural y de otro sistema a la vez. Si dos capas pueden escribir lo mismo,
   el ownership queda escrito junto al código correspondiente, no aquí.
2. **Una sola ruta de producción.** Sin fallbacks, flags ni legacy activo. Git es
   el rollback.
3. **Nada de arquitectura especulativa:** ni managers, ni event buses, ni
   interfaces genéricas, ni capas "por si luego sirven".
4. **Cambios locales antes que rediseños.** La causa se arregla donde está.
5. **No dividir archivos por tamaño**, sino cuando una IA necesita buscar menos.
6. **Los detalles técnicos viven junto al código que los usa.** README = reglas
   estables; código = verdad técnica actual; Git = historia.
7. **No inventes alcance.** Ni multijugador, ni mapa, ni UI, ni features nuevas
   por iniciativa propia.
8. **Assets:** licencia compatible (nunca NonCommercial) y crédito en
   `CREDITS_*.md` en el mismo cambio.
9. **Android manda junto con PC.** Que funcione en escritorio no prueba nada.
10. **Elimina lo que tu cambio vuelva obsoleto:** código, flags, comentarios,
    docs y herramientas que ya no se usan.
11. **Mantén este README corto y verdadero.**

**Prioridad:** correctitud → profundidad física / sensación → estabilidad →
rendimiento → calidad audiovisual → features.

## Arquitectura

| Responsabilidad | Autoridad |
|---|---|
| Arranque y escena | `scripts/Main.gd` |
| Mecánica del arma: munición, recámara, gatillo, cadencia, corredera, recarga | `scripts/Glock.gd` |
| Piezas del arma y tabla de armas (Glock, Desert Eagle) | `scripts/GlockWeapon.gd` |
| Viewmodel: brazos, ADS, pose, animación, sockets | `scripts/GlockViewmodel.gd` |
| Retroceso y peso: el arma en el agarre + cesión de las manos | `scripts/GlockRecoil.gd` |
| Fogonazo, luz de boca, humo | `scripts/WeaponFX.gd` |
| Audio | `scripts/GameAudio.gd` |
| Balística | `scripts/Ballistics.gd` |
| Impactos | `scripts/ImpactFX.gd` |
| Vaina expulsada | `scripts/Shell.gd` |
| Jugador y cámara | `scripts/Player.gd` |
| HUD y post bodycam | `scripts/HUD.gd` + `shaders/bodycam.gdshader` |
| Mundo y rango | `scripts/World.gd` |
| Blancos | `scripts/Target.gd` |
| Cajas de madera reactivas | `scripts/Crate.gd` |

Autoloads: `GameAudio`, `ImpactFX`, `Ballistics`. Escena: `scenes/Main.tscn`.
Señales del arma: `shot_fired`, `ammo_changed(mag, chamber, reserve, reloading)`.

**El arma no está en el esqueleto.** Es un árbol de piezas rígidas: `Frame`,
`Slide`, `Trigger`, `Magazine`, `Barrel` y los puntos de boca, miras y puerto.
Los brazos son el único esqueleto y su pose la manda el `AnimationPlayer`. El
ownership de cada nodo vive al principio de `scripts/GlockViewmodel.gd`.

**Dos armas:** Glock 19 y Desert Eagle, con el mismo viewmodel y los mismos
brazos. Cambiar de arma es **una línea** (`const ARMA` en
`GlockViewmodel.gd`); añadir otra es una entrada en la tabla `ARMAS` de
`GlockWeapon.gd` más su `.glb` preparado con `tools/make_weapon_parts.py`. No
hay código por arma.

Los eventos de la recarga (agarre del cargador, entrega, sonidos) no usan
tiempos escritos a mano: se disparan sobre los mínimos reales de la distancia
mano↔brocal, medidos cada frame. Ver `scripts/Glock.gd`.

### Dónde se pide cada ajuste

| Petición | Un solo sitio |
|---|---|
| "el recoil se ve falso" / "que pese más" | `scripts/GlockRecoil.gd`, 3 constantes juntas |
| "el arma está mal encuadrada" | `ARMA_EMPUNADURA` en `GlockViewmodel.gd` |
| "la corredera no llega / recorre de más" | `corredera` en la tabla `ARMAS` |
| "quiero otra pistola" | `const ARMA` + entrada en `ARMAS` + `.glb` |
| "un sonido no cae en el gesto" | no hay segundos que tocar: el evento sale del gesto |

Comprobar sin abrir el editor: `tools/check_weapon.gd` (orientación y montaje),
`tools/check_reload.gd` (dónde cae cada evento) y, en Blender,
`tools/check_weapon_parts.py` (piezas, tamaño real y puntos mecánicos).

## Workflow IA + usuario

- **El usuario es el evaluador principal** de apariencia, movimiento, sensación y
  audio. Ciclo: cambio pequeño → commit/push → el usuario prueba en Godot →
  feedback → corregir.
- **Capturas y video están permitidos.** Si el problema es espacial, visual o de
  pose, mirar una captura o pedirla al usuario es más rápido que diagnosticar
  transforms a ciegas. Mirar no es construir tooling. Excepción: UNA
  herramienta pequeña de inspección visual (`tools/review_contact_sheet.py`) que
  graba una acción breve a suficientes FPS y reúne sus frames en UNA sola
  imagen de contacto. No es un test, no produce métricas, no sustituye al
  usuario.
- **Sin laboratorio.** Nada más que esa hoja de contacto: ni DevTools, ni
  armdiag, ni recoilprobe, ni visualab, ni fpsbench, ni audiocapture, ni
  baterías de capturas para sustituir el juicio humano.
- **Tests:** no se ejecutan automáticamente. Una comprobación automática solo se
  justifica si el usuario la pide explícitamente o autoriza una invariante
  concreta (pregunta objetiva que el usuario no responde mejor mirando o
  escuchando, pequeña y atada a esa invariante).
- **Tras DOS intentos sin mejora visible o audible: DETENTE Y PREGUNTA.** Una
  pregunta de 10 segundos es mejor que 40 minutos de análisis equivocado.
- **Comentarios:** explican invariantes actuales y el porqué de una decisión no
  obvia. Un valor calibrado puede decir `CALIBRADO: razón actual`, pero no cita
  herramientas ni experimentos que ya no existen.

## Alcance

PC + Android, **4 vs 4**, un mapa pequeño y muy trabajado, mini entrenamiento
derivado del rango y lobby muy simple. **Multijugador, lobby, mapa y controles
Android finales solo cuando el usuario lo ordene.**

Fuera de alcance: mundo abierto, campaña, vehículos, loot, crafting, economía,
tienda, clanes, ranking, espectador, replays, decenas de armas o de mapas.

---

**FlowFire no debe impresionar por todo lo que tiene, sino por lo absurdamente
bien hecho que está lo poco que tiene.**
