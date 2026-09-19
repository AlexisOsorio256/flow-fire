# Créditos de audio

Sólo créditos: archivo actual, fuente, autor, licencia y qué se le hizo. La
investigación (pruebas, descartes y medidas) vive en la historia de Git, no aquí.

La mayoria de WAV se convierten a 44,1 kHz mono 16-bit con `tools/process_audio.sh`
(ffmpeg), alineados a su ataque y normalizados por familia. Los cuatro de Foley
sintetizado NO los toca ese script: los genera `tools/make_weapon_sounds.py`.
Los masters versionados estan en `assets/audio/source/` (con `.gdignore` para
que Godot no los importe).

Los cinco disparos (`shot_1..5.wav`) tampoco pasan por ahí: son **48 kHz** mono
16-bit y los construye `tools/build_shot_real.py` desde cinco grabaciones reales
de pistola, con HPF + low-shelf + trim de ataque común. Los mide
`tools/measure_shots.py`, que comprueba los criterios de dinámica uno a uno.

Los seis de impacto (`impact_*.wav`, `ricochet.wav`) tampoco pasan por
`process_audio.sh`: los corta `tools/build_impacts.py`, **cada uno de una
grabación distinta**, y se normalizan por **pico** (−1,2 dBFS) y no por media,
porque su factor de cresta va de 14,2 a 29,2 dB y una media común los dejaba
descompensados. El equilibrio de la familia vive en la tabla `SOUNDS` de
`scripts/GameAudio.gd`, medido sobre estos WAV.

## Familia arma (bus `Weapons`)

| archivo | fuente | autor / licencia | transformación |
|---|---|---|---|
| `shot_1..5.wav` | **5 disparos REALES de pistola, cada uno de una grabación DISTINTA** (tabla abajo) | 5 autores distintos, todos **`Creative Commons 0`** (texto leído en la página de cada sonido al descargarlo; ver la nota de licencias) | reconstruidos por `tools/build_shot_real.py` y verificados con `tools/measure_shots.py`. Sustituyen a cinco cortes de la Walther PPQ que medían **cresta 26,4-28,4 dB**: pico a tope (-1,00 dBFS) pero **RMS -27,4..-29,4 dBFS** y -20 dB a los 15 ms, o sea un chasquido fino sin cuerpo ni cola. La causa era la fuente (tomas de micro cercano: `X_39.wav` cruda mide **39,0 dB** de cresta), no el corte |
| `magin.wav`, `magout.wav` | foley de cargador, micro MKH60 close-up — Sonniss #GameAudioGDC Bundle 2016 | Heckler & Koch G36C (Sonniss EULA) | cortes de `assets/audio/source/g36c_mag_in_out_excerpt.wav`; el clack del asiento cae ~60 ms dentro de `magin.wav` y `Glock.gd` lo adelanta ese tiempo |
| `empty_b.wav` | "9mm Handgun Being Dry Fired" | serøutōnin--deprivəd — https://freesound.org/s/674568/ — CC0 | alineado al ataque |
| `slide_rear.wav` | "Glock 19 Handgun Pistol Slide Cocking Sounds" (evento de 10,972 s) | jackthemurray — https://freesound.org/s/393734/ — CC0 | corte al ataque (tope trasero de la corredera) |
| `slide_battery.wav` | "Sig Sauer P229 Handgun slide rack.wav" (evento de 4,016 s) | nikkolaus — https://freesound.org/s/442560/ — CC0 | corte al ataque (vuelta a batería) |
| `slide_hand.wav` | "Metal Contact" (contact small metal box lid subtle hits) | SoundHolder / Sonniss #GameAudioGDC Bundle 2017, espejo `http://ftpmirror.your.org/pub/misc/sonniss2017/` — EULA comercial sin atribución | recortado |

### Los cinco disparos: qué es cada uno

Elegidos por MEDIDA sobre 25 fuentes reales (cresta, reparto de bandas y RMS),
no por el nombre del fichero. Un fichero fuente distinto por toma, para que las
cinco variantes no sean el mismo disparo repetido.

| archivo | qué es | fuente (URL) | autor | licencia |
|---|---|---|---|---|
| `shot_1.wav` | **Glock 19X real** (9 mm), la de más cuerpo del conjunto (cresta 13,5 dB) | https://freesound.org/s/828786/ | areniporgen | `Creative Commons 0` |
| `shot_2.wav` | **Glock real disparada 3 veces** (9 mm) | https://freesound.org/s/855652/ | serøutōnin--deprivəd | `Creative Commons 0` |
| `shot_3.wav` | **disparos de mano a bocajarro**, toma larga con muchos tiros sueltos; el título de la fuente dice .22 mm / 7,5 mm / 9 mm | https://freesound.org/s/377786/ | johanwestling | `Creative Commons 0` |
| `shot_4.wav` | **pistola real** (calibre no documentado por la fuente) | https://freesound.org/s/253736/ | Kodack | `Creative Commons 0` |
| `shot_5.wav` | **pistola 9 mm real** | https://freesound.org/s/427592/ | michorvath | `Creative Commons 0` |

**Nota de licencias (honesta):** las cinco cadenas `Creative Commons 0` se leyeron
en la página de cada sonido al descargarlo (pasada anterior) y están registradas
en `downloads/AUDIO_SOURCES.md`. Durante esta pasada **freesound.org devolvió HTTP
502**, así que no se pudieron re-verificar en vivo. Se intentó por Wayback: la
instantánea de `areniporgen` 828786 existe pero el archivo devuelto viene
comprimido y no se pudo leer la licencia; las otras cuatro no tienen instantánea.
La cadena es la registrada, no inventada, pero **no está verificada en esta
pasada**. (El `ricochet.wav` sí se pudo verificar por Wayback: ver su fila.)

### La cadena que se les aplica (`tools/build_shot_real.py`)

El corte por sí solo no arreglaba nada: las tomas de micro cercano son todo pico.
Lo que devuelve el cuerpo es la cadena, en este orden:

1. **HPF 35 Hz** (Butterworth 2.º orden): fuera el retumbe por debajo de la banda
   útil; 120-400 Hz no se toca.
2. **Low-shelf a 200 Hz con ganancia por toma** (0 a +6 dB): sube a la vez el
   reparto 120-400 Hz y el RMS respecto al pico, o sea **baja la cresta**. Solo
   amplifica contenido que ya está en la grabación; no se añade nada.
3. **Normalización de pico a -0,5 dBFS.**
4. **Trim de ataque común**: ganancia para que el RMS de los primeros 40 ms valga
   lo mismo en las cinco. Como la ganancia sale ≤ 0, el pico nunca sube.
5. **Fade de salida de 30 ms** y comprobación de muestras al ras.

La compresión/limiting y el EQ no son hacer trampa aquí: una grabación real de
disparo puesta en crudo es justo lo que sonaba a juguete.

### Disparos: antes y después (medido con `tools/measure_shots.py`)

| | antes (5 cortes de Walther PPQ) | después (5 pistolas reales) |
|---|---|---|
| duración | 420,5 ms | 382 ms |
| pico | -1,00 dBFS | -0,50 a -1,61 dBFS |
| **RMS** | **-27,4 a -29,4 dBFS** | **-14,7 a -17,8 dBFS** |
| **cresta** | **26,4 a 28,4 dB** | **13,5 a 17,0 dB** |
| ataque (40 ms) | -19,7 a -17,2 dBFS (dispersión 2,51 dB) | **-8,76 dBFS en las cinco (dispersión 0,00 dB)** |
| muestras al ras | 0 | 0 |
| **120-400 Hz** | **0,000-0,015** (prácticamente cero) | **0,058-0,404** |
| **400-1000 Hz** | **0,002-0,037** | **0,283-0,646** |
| <120 Hz | 0,003-0,975 | 0,006-0,033 |
| >2,5 kHz | 0,021-0,958 | 0,037-0,217 |
| cola (últimos 100 ms) | 39,9-56,9 dB por debajo del ataque (solo ruido de sala) | 12,2-23,6 dB por debajo (cola real que decae) |

El dato que explica el reporte del usuario ("parece que dispara peluches") es el
reparto de bandas: los disparos viejos tenían **0,000-0,015 de su energía en
120-400 Hz y 0,002-0,037 en 400-1000 Hz**. Estaban partidos entre retumbe por
debajo de 120 Hz y agudos por encima de 2,5 kHz, sin nada en medio: un clic
fino. Los nuevos tienen el cuerpo justo en esa banda.

Criterios de aceptación (cresta 12-18 dB, pico ≤ -0,5 sin recorte, RMS ≥ -18 dBFS,
energía en 120-400 y 400-1000 Hz, ataque igual dentro de 1,5 dB, 250-450 ms con
cola que decae): **los cinco los cumplen**.

### Foley sintetizado (sin master)

Estos no vienen de ninguna grabación: son eventos que estaban mudos y se
sintetizan en `tools/make_weapon_sounds.py`, que es su fuente y su licencia
(propia, mismo LICENSE que el codigo: Todos los derechos reservados). Regenerarlos es volver a
ejecutarlo y reimportar.

| archivo | evento | carácter |
|---|---|---|
| `trigger_reset.wav` | click del reset del disparador | sintesis 50 ms, un transitorio (ver `make_weapon_sounds.py`) |
| `mag_drop.wav` | el cargador golpeando hormigon | UN golpe (220 ms); cada contacto dispara uno con nivel/pitch por velocidad |
| `mag_insert.wav` | el cargador rozando el brocal al subir | metal contra metal, costillas y resorte |
| `slide_release.wav` | el retén de la corredera al soltarse | tic de acero corto y agudo |

## Familia mundo (bus `World`, enviado al bus de sala `Range`)

Los seis impactos son **grabaciones distintas entre sí**. Ninguno es copia,
pitch-shift ni EQ de otro del mismo set: eso es exactamente lo que había antes
(`impact_drywall` era el master de `impact_concrete` y `impact_aluminum` un
derivado de `impact_metal`) y ya no existe. Estado real de cada uno, sin
adornos:

| archivo | qué es REALMENTE | fuente exacta (URL descargada) | autor | licencia (texto exacto) | transformación |
|---|---|---|---|---|---|
| `impact_metal.wav` | **Impacto de BALA REAL** sobre placa de metal pesada (nivel 1 de preferencia) | `http://ftpmirror.your.org/pub/misc/sonniss2017/individual/Gamemaster%20Audio%20-%20%20Bullet%20Impact%20Sounds/bullet_impact_metal_heavy_08.wav` (`bullet_impact_metal_heavy_08.wav`) | Gamemaster Audio | **`THE SONNISS #GAMEAUDIOGDC BUNDLE LICENSING AGREEMENT`**: *"a worldwide, nonexclusive, royaltyfree license to use all or any of the sound effects"*; *"Licensee may use the licensed sound effects for personal and commercial projects without attribution to the original creator."* Texto completo: `http://ftpmirror.your.org/pub/misc/sonniss2017/Licensing.pdf` | corte en `tools/build_impacts.py`: ataque re-anclado (la toma traía ~68 ms de riser antes del golpe), 550 ms de cola, fade 90 ms, DC fuera, pico a −1,2 dBFS. 876 Hz de centroide, 86,1 % de energía <800 Hz |
| `impact_concrete.wav` | **Impacto de BALA REAL** sobre ladrillo/hormigón (nivel 1) | `http://ftpmirror.your.org/pub/misc/sonniss2017/individual/Gamemaster%20Audio%20-%20%20Bullet%20Impact%20Sounds/bullet_impact_concrete_brick_01.wav` (`bullet_impact_concrete_brick_01.wav`) | Gamemaster Audio | **`THE SONNISS #GAMEAUDIOGDC BUNDLE LICENSING AGREEMENT`** (misma cita que arriba) | corte: ataque re-anclado (~44 ms de riser fuera), 300 ms, fade 60 ms, pico a −1,2 dBFS. 3.656 Hz de centroide, 36,8 % <800 Hz |
| `impact_aluminum.wav` | **FOLEY de chapa fina** (calibre 20) golpeada — nivel 3. La librería **no documenta la aleación**, así que NO se puede afirmar que la grabación sea de aluminio; sí es chapa fina, que es el comportamiento que pide el set (sin cuerpo, resonancia alta) | `http://ftpmirror.your.org/pub/misc/sonniss2019/individual/Airborne%20Sound%20-%20Elements%20Metal/Metal%2CCrash%2CConcrete%2CSheet%20Metal%2C20%20Gauge%2CSlow%2CComplex.wav` (`Metal,Crash,Concrete,Sheet Metal,20 Gauge,Slow,Complex.wav`) | Airborne Sound | **`THE SONNISS #GAMEAUDIOGDC BUNDLE LICENSING AGREEMENT`** (misma cita) | corte: un golpe aislado en 1,688 s, 160 ms, fade 45 ms, +12,6 dB de ganancia para llegar al pico, pico a −1,2 dBFS. 5.112 Hz de centroide, 0,6 % <800 Hz y 83,6 % >2,5 kHz: el material más agudo y con menos cuerpo de los seis |
| `impact_wood.wav` | **FOLEY de tabla de madera** golpeada/partida — nivel 3. Es un *crack* seco de madera real, no un bloque-instrumento | `http://ftpmirror.your.org/pub/misc/sonniss2017/individual/Double%20Trouble%20Audio%20-%20Wood%20Impacts%20and%20Debris/Impacts%20Soft%20-%20Short%2C%20Crack.wav` (`Impacts Soft - Short, Crack.wav`) | Double Trouble Audio | **`THE SONNISS #GAMEAUDIOGDC BUNDLE LICENSING AGREEMENT`** (misma cita) | corte del **primer** crack de la toma (0,009 s), 100 ms, fade 30 ms, pico a −1,2 dBFS. 1.612 Hz de centroide, 25,2 % <800 Hz: el más grave de los cuatro materiales "duros" |
| `impact_drywall.wav` | **PROYECTIL REAL** (flecha) contra un panel fino — nivel 2. No hay disponible ninguna grabación de bala contra pladur en ninguna fuente alcanzable sin login; esta es la única cosa real que atraviesa un panel | `https://freesound.org/s/802473/` ("Arrow in something thin"), descargado como preview `-hq` (184 kbps MP3) porque freesound.org exige cuenta para el original | Sadiquecat | **`Creative Commons 0`** — texto leído en la propia página del sonido al descargarlo (pasada anterior) y registrado en `downloads/AUDIO_SOURCES.md`. **Aviso honesto: NO se ha podido re-verificar de forma independiente.** freesound.org devolvió HTTP 502 toda la pasada, y Wayback **no tiene ninguna copia** de este sonido (`web.archive.org/cdx/search/cdx?url=freesound.org/*802473*` devuelve vacío; los snapshots de este autor sólo llegan a sonidos de 2021). La cadena es la registrada, no inventada, pero no está verificada en vivo | corte: 120 ms desde el ataque, fade 35 ms, pico a −1,2 dBFS. 2.647 Hz de centroide, 6,3 % <800 Hz: mucho más ligero que hormigón (36,8 %) |
| `ricochet.wav` | **RICOCHET de BALA REAL** con barrido Doppler (nivel 1). El espectrograma muestra el banco de armónicos cayendo de ~5,2 kHz a ~1,7 kHz en 500 ms | `https://freesound.org/s/30932/` ("bullet ricochet.wav", preview `-hq`, MP3) | aust_paul | **`Creative Commons 0`** — **re-verificado de forma independiente en esta pasada** sobre la copia archivada de la página del sonido (`http://web.archive.org/web/2024id_/https://freesound.org/people/aust_paul/sounds/30932/`, snapshot 2026-02-22): la página enlaza a `http://creativecommons.org/publicdomain/zero/1.0/` con la etiqueta literal *"Creative Commons 0"* y el texto *"You can copy, modify, distribute and perform the sound, even for commercial purposes, all without the need of asking permission to the author."* (freesound.org seguía en HTTP 502, por eso se usó Wayback) | corte del **primer** rebote (el segundo empieza en 0,992 s): 700 ms, fade 120 ms, pico a −1,2 dBFS. Sustituye a un recorte de 3,0 s de *The Warfare Library* (Pole Position) cuyo pico caía a 2,6 s y medía 423 Hz de centroide: **no era un ricochet, era un retumbe** |
| `bullet_flyby.wav` | "Bullet Impact Sounds" (`bullet_flyby_fast_05`) | `http://ftpmirror.your.org/pub/misc/sonniss2017/individual/Gamemaster%20Audio%20-%20%20Bullet%20Impact%20Sounds/bullet_flyby_fast_05.wav` | Gamemaster Audio / Sonniss 2017 — EULA sin atribución (misma cita) | alineado al ataque. **No tocado en esta pasada** |
| `shell_drop.wav` | "Metal_Shell_Spin_10" | BlondPanda — https://freesound.org/s/777923/ — CC0 | BlondPanda | `Creative Commons 0` | alineado al ataque. **No tocado en esta pasada**; sólo se le bajó el nivel en `GameAudio.gd` |
| `footstep.wav` | "Footsteps on concrete" | florianreichelt — https://freesound.org/s/459964/ — CC0 | florianreichelt | `Creative Commons 0` | alineado al ataque. **No tocado en esta pasada** |

### Lo que se descartó, y por qué

- **`impact_aluminum` como derivado de `impact_metal`**: retirado. Era un
  high-pass/treble/tempo del acero, es decir, el mismo material con otro color.
- **`impact_drywall` como copia de `impact_concrete`**: retirado. Era
  literalmente el mismo master (mismo MD5) con otro nombre.
- **`impact_wood` = "Wooden Blocks" (NearTheAtmoshphere, CC0)**: retirado. Era
  foley de un bloque de madera, no un golpe de proyectil sobre tabla; medía
  642 Hz de centroide y 64 % de energía <800 Hz, o sea un golpe sordo.
- **`ricochet` = Pole Position, *The Warfare Library***: retirado. La toma es una
  ametralladora real, pero el recorte de 3,0 s no contenía un rebote: su pico
  estaba en 2,6 s y su centroide medía 423 Hz. Ningún transitorio de esa toma
  (181 s analizados) supera 1 kHz de centroide, así que no hay de dónde sacar un
  zing.
- **Bala real contra pladur, aluminio o madera**: **no existe** en ninguna
  fuente alcanzable sin cuenta ni API key. Se buscó en los seis bundles Sonniss
  #GameAudioGDC (2016-2020, 1.566 packs inventariados), archive.org, Wikimedia
  Commons y OpenGameArt. El pack "Bullet Impact Sounds" de Gamemaster Audio sólo
  aporta a los bundles 4 archivos (hormigón, metal pesado, cuerpo, flyby); el
  pack completo es de pago y no está espejado.
- Esa conclusión se **corroboró con una segunda búsqueda independiente** (96
  archivos validados, tabla completa en `downloads/bullet_hunt/FINDINGS.md`,
  gitignored) que rastreó además los espejos de los bundles Sonniss en
  archive.org y reconstruyó URLs de previews de Freesound desde instantáneas de
  Wayback. Su veredicto, literal: **"Drywall/gypsum: nothing found on any
  reachable source"** y **"no real bullet-on-aluminium exists"**. El único
  impacto real sobre chapa fina que encontró es una bala de goma contra una lata
  (`sounddino.com`, **licencia sin verificar** ⇒ descartado por las reglas), y el
  único candidato real sobre madera (`Bullet_Drop_Wood_04`, que ya se midió aquí:
  632 Hz de centroide = sordo) es ambiguo por su propio nombre (*drop*). También
  avisó de dos candidatos de Freesound con licencia **CC BY-NC 3.0**
  (benjaminharveydesign 315858, LiamG_SFX 323070): **no comerciales, no se han
  usado**.

Los EULA de Sonniss conceden uso comercial mundial, libre de regalías y sin
obligación de atribución (la propia cláusula *"without attribution to the
original creator"*); se acredita igualmente por cortesía. Si se reemplaza un
WAV, se actualiza su fila en el mismo cambio.
