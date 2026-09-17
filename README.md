# FlowFire

FPS **bodycam** compacto y deliberadamente limitado. PC + Android. Hoy es un
**vertical slice de combate y entrenamiento**: una pistola, un viewmodel, un
mapa. El código se mantiene **100% con IA**, así que la facilidad de localización
es una métrica de eficiencia: cada responsabilidad importante tiene un archivo
obvio con un nombre que dice qué controla.

## Qué queremos

- Una pistola, un viewmodel, **una autoridad por comportamiento**.
- Profundidad en cómo reaccionan **arma, proyectil, material, cuerpo, cámara y
  sonido**, no cantidad de features.
- Que lo poco que hace se sienta excepcional, en PC **y** en Android.

## Contrato

1. **Una sola autoridad por comportamiento.** No duplicar estado ni lógica.
2. **Una sola ruta de producción.** Sin fallbacks, flags ni legacy activo. Git es
   el rollback.
3. **Nada de arquitectura especulativa:** sin managers, event buses, interfaces
   genéricas ni abstracciones "por si luego sirven".
4. **Separar por responsabilidad real, no por patrón.** Si una responsabilidad se
   extrae, se extrae de verdad, no a un facade.
5. **Cambios locales antes que rediseños.** La causa se arregla donde está.
6. **No dividir archivos por tamaño**, sino cuando una IA necesita buscar menos.
7. **Los detalles técnicos viven junto al código que los necesita**, no en este
   README. La historia la guarda Git.
8. **No inventes alcance.** Ni por iniciativa propia: multijugador, mapa,
   LightmapGI, penetración/balística, UI, lobby, controles Android, features nuevas.
9. **Assets:** licencia compatible (nunca NonCommercial) y crédito en
   `CREDITS_*.md` en el mismo cambio.
10. **Android manda junto con PC.** Que funcione en escritorio no prueba nada.
11. **Elimina lo que tu cambio vuelva obsoleto:** código, flags, comentarios,
    docs y herramientas que ya no se usan.
12. **Mantén este README corto y verdadero.**

**Prioridad:** correctitud → profundidad física / sensación → estabilidad →
rendimiento → calidad audiovisual → features. La calidad perceptual y la
eficiencia son criterios de aceptación.

## Arquitectura

| Responsabilidad | Autoridad |
|---|---|
| Arranque, escena y tests | `scripts/Main.gd` |
| Mecánica del arma: munición, recámara, gatillo, cadencia, corredera, recarga | `scripts/Glock.gd` |
| Viewmodel: rig, huesos, ADS, pose, animación, materiales | `scripts/GlockViewmodel.gd` |
| Retroceso: muñeca, arma, brazos | `scripts/GlockRecoil.gd` |
| Fogonazo, luz de boca, humo | `scripts/WeaponFX.gd` |
| Audio | `scripts/GameAudio.gd` |
| Balística | `scripts/Ballistics.gd` |
| Impactos | `scripts/ImpactFX.gd` |
| Jugador y cámara | `scripts/Player.gd` |
| HUD y post bodycam | `scripts/HUD.gd` + `shaders/bodycam.gdshader` |
| Mundo y rango | `scripts/World.gd` |
| Blancos | `scripts/Target.gd` |
| Laboratorio: setup y despacho | `scripts/DevTools.gd` |
| Diagnóstico del arma y del rig | `scripts/DevWeapon.gd` |
| Capturas y cámara lenta | `scripts/DevVisual.gd` |
| Benchmark | `scripts/DevBenchmark.gd` |
| Captura de audio | `scripts/DevAudio.gd` |

Autoloads: `GameAudio`, `ImpactFX`, `Ballistics`. Escena: `scenes/Main.tscn`.
Señales del arma: `shot_fired`, `ammo_changed(mag, chamber, reserve, reloading)`.

## Workflow IA + usuario

- **Perceptual:** cambia UNA cosa → pide al usuario que lo pruebe → corrige.
  El usuario es el evaluador visual y auditivo en tiempo real.
- **Mide** solo cuando la pregunta sea objetiva y la respuesta no evidente.
  No medir por ceremonia; el usuario puede enviar vídeo.
- **Test proporcional al cambio:** `aimtest` para ADS, `reloadtest` para recarga,
  mirar lo visual, escuchar lo audible, `fpsbench` para rendimiento. Suite
  completa solo al cerrar una etapa.
- **Herramientas:** `godot4 --path . -- --devhelp` lista las disponibles.

## Alcance

PC + Android, **4 vs 4**, un mapa pequeño y muy trabajado, mini entrenamiento
derivado del rango y lobby muy simple. **Multijugador, lobby, mapa y controles
Android finales solo cuando el usuario lo ordene.**

Fuera de alcance: mundo abierto, campaña, vehículos, loot, crafting, economía,
tienda, clanes, ranking, espectador, replays, decenas de armas o de mapas.

---

**FlowFire no debe impresionar por todo lo que tiene, sino por lo absurdamente
bien hecho que está lo poco que tiene.**
