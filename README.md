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
| Piezas del arma (Glock 19: Frame, Slide, Trigger, Magazine, puntos) | `scripts/GlockWeapon.gd` |
| Viewmodel: brazos, anclaje del arma, ADS, pose, clips | `scripts/GlockViewmodel.gd` |
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
`Slide`, `Trigger`, `Magazine` y los puntos de boca, miras y puerto. Su sitio lo
fijan **dos constantes calibradas** de `GlockViewmodel.gd` (`ARMS_MOUNT_POS` y
`GRIP_POS`/`GRIP_ROT`), no una medición en runtime: no hay nada que buscar en el
rig de brazos ni nada que se rompa si el rig cambia.

**Una pistola.** Glock 19. No hay tabla de armas ni código por arma a propósito.

**Los brazos son `assets/models/arms.glb`**, podado por
`tools/prune_arms.py`: solo las mallas del personaje (mangas, guantes, reloj),
los 78 huesos que las deforman y los cinco clips que el juego reproduce (`Idle`,
`Fire`, `Reload`, `Reload_Empty`, `Inspect`). La pistola que traía el asset
original estaba anclada en el espacio, no en la mano, así que el arma va anclada
igual: fija al pivote, con las manos del clip trabajando alrededor. **Están en
evaluación de reemplazo**; el porqué está medido en `CREDITS_MODELS.md`.

Los eventos que dependen de un gesto del clip —los dos tiempos del cargador y
los de la inspección— son **instantes del propio clip**: se miden con
`tools/check_reload.gd` (que imprime las constantes listas para pegar) y viven
junto a su clip en `Glock.gd`. Si un clip cambia, se vuelven a medir.

### Dónde se pide cada ajuste

| Petición | Un solo sitio |
|---|---|
| "el recoil se ve falso" / "que pese más" | `scripts/GlockRecoil.gd`, 3 constantes juntas |
| "el arma está mal encuadrada" | `GRIP_POS` / `GRIP_ROT` en `GlockViewmodel.gd` |
| "los brazos salen mal encuadrados" | `ARMS_MOUNT_POS` / `ARMS_SCALE` en `GlockViewmodel.gd` |
| "la corredera no llega / recorre de más" | `CORREDERA` en `GlockWeapon.gd` |
| "un evento de la recarga cae fuera del gesto" | los `RELOAD_*_T` de `Glock.gd`, re-midiendo con `tools/check_reload.gd` |

Invariantes objetivas: `tools/check_weapon.gd` (orientación y montaje) y
`tools/prune_arms.py` (que el rig de brazos sea solo lo que se usa). En Blender,
`tools/make_weapon_parts.py` (piezas del arma, tamaño real y puntos mecánicos).
Lo visual se comprueba abriendo Godot en la pantalla del usuario (`:0`, X11) y
tomando capturas ahí. Prohibido headless, display virtual y GPU virtual: no
concuerdan con lo que ve el usuario.

## Workflow IA + usuario

- **La IA abre el juego en tu pantalla, toma capturas y juzga.** Si algo
  se ve mal, la IA ejecuta Godot en `:0`, saca sus propias capturas de esa
  pantalla y juzga sobre ellas. Nunca pide al usuario imágenes de lo que
  puede ver sola. Prohibido verificar en headless o en GPU/display virtual.
- **Ciclo:** cambio pequeño → la IA lo verifica en el juego con capturas →
  commit/push → el usuario valida en su Godot → feedback → corregir.
- **Honestidad antes que avance.** Si algo atrasa el proyecto, la IA lo dice y
  propone una forma mejor de reemplazarlo. Prohibido decir "ya quedó" sin
  haberlo verificado en el juego. Nada a medias ni mal hecho.
- **Assets:** si un asset frena o se ve mal, se descarga uno mejor (licencia
  compatible + crédito en `CREDITS_*.md`). Sin animaciones exorbitantes si
  atrasan: brazos y gestos, lo justo para que se vea bien y barato de
  mantener. La PISTOLA es lo que vende: calidad excelente de primer nivel en
  modelo, físicas y sensación, sin sacrificar velocidad de desarrollo.
- **Pendiente de assets:** los brazos actuales pesan 13,42 MB, de los que 11 MB
  son diez texturas PNG. El rig ligero de 706 KB se probó y no sirve (sin
  texturas y sin `Reload_Empty` ni `Inspect`): el diagnóstico medido, lo
  descartado y lo que debe traer el sustituto están en `CREDITS_MODELS.md`.
- **Tests:** no se ejecutan automáticamente. Una comprobación automática solo se
  justifica si el usuario la pide explícitamente o autoriza una invariante
  concreta (pregunta objetiva que el usuario no responde mejor mirando o
  escuchando, pequeña y atada a esa invariante).
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
