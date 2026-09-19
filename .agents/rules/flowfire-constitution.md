# FlowFire — regla de workspace

Antes de modificar el proyecto, lee `README.md` completo desde el estado ACTUAL de
`main` y trátalo como la constitución técnica del repositorio.

- `main` es la única rama de producción. No crees branches, PRs ni rutas paralelas.
- Si el prompt y el repo discrepan, verifica el runtime actual antes de actuar.
- Una autoridad por comportamiento. No introduzcas managers, fallbacks, legacy activo
  ni abstracciones para features que todavía no existen.
- Problema de asset/pose/UV/origen/rig -> Blender. Problema de mecánica/física/audio
  runtime -> Godot o tooling offline mínimo.
- Prefiere capacidades nativas de Godot/Blender antes que código nuevo.
- Una mejora perceptual que aumenta innecesariamente la superficie mental no está
  terminada. Una simplificación que empeora perceptiblemente el hero asset tampoco.
- Al reemplazar una ruta, elimina la anterior en el mismo cambio; Git es el museo.
- No declares calidad visual por un check estructural: usa capturas reales. No declares
  rendimiento por una sonda CPU: usa el benchmark de render. No declares audio premium
  por nombres o comentarios: inspecciona los WAV y la mezcla real.
- Antes de afirmar éxito, verifica que README/CREDITS describen literalmente el estado
  final. Si una decisión nueva cambia la constitución, actualiza README en el mismo cambio.
- El producto actual es una sola Glock 19 y su cadena de disparo/material/feedback.
  Cualquier trabajo fuera de esa cadena debe justificar claramente por qué existe.
