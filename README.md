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
| Viewmodel: rig, huesos, ADS, pose, animación, materiales | `scripts/GlockViewmodel.gd` |
| Retroceso: el arma dentro de la mano, y el brazo | `scripts/GlockRecoil.gd` |
| Fogonazo, luz de boca, humo | `scripts/WeaponFX.gd` |
| Audio | `scripts/GameAudio.gd` |
| Balística | `scripts/Ballistics.gd` |
| Impactos | `scripts/ImpactFX.gd` |
| Jugador y cámara | `scripts/Player.gd` |
| HUD y post bodycam | `scripts/HUD.gd` + `shaders/bodycam.gdshader` |
| Mundo y rango | `scripts/World.gd` |
| Blancos | `scripts/Target.gd` |

Autoloads: `GameAudio`, `ImpactFX`, `Ballistics`. Escena: `scenes/Main.tscn`.
Señales del arma: `shot_fired`, `ammo_changed(mag, chamber, reserve, reloading)`.
El ownership de huesos concretos vive al principio de `scripts/GlockViewmodel.gd`.

## Workflow IA + usuario

- **El usuario es el evaluador principal** de apariencia, movimiento, sensación y
  audio. Ciclo: cambio pequeño → commit/push → el usuario prueba en Godot →
  feedback → corregir.
- **Capturas y video están permitidos.** Si el problema es espacial, visual o de
  pose, mirar una captura o pedirla al usuario es más rápido que diagnosticar
  transforms a ciegas. Mirar no es construir tooling.
- **Sin laboratorio.** No se construyen herramientas, métricas ni baterías de
  capturas para sustituir el juicio humano (nada de DevTools, armdiag,
  recoilprobe, visualab, fpsbench, audiocapture).
- **Tests:** no son workflow por defecto. Una comprobación automática solo se
  justifica si la pregunta es objetiva, el usuario no puede responderla mejor
  mirando o escuchando, protege una invariancia importante y es pequeña.
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
