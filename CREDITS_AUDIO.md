# Créditos de audio

Sonidos reales procesados con `tools/process_audio.sh` (ffmpeg): cada one-shot se alinea con su ataque, se iguala la loudness dentro de cada familia y se recorta la cola con fade.

## El disparo sonaba dos veces: causa medida (corregido)

El disparo base gustaba, pero se percibía un segundo golpe inmediatamente después.
La causa **no** era la capa mecánica sintética, sino las propias muestras.

**Los `shot_N.wav` anteriores eran ventanas de 700 ms cortadas a mano de la misma
rafaga**, y su "ataque" (el pico de muestra, que es lo que medía el script) no
coincidía con el ataque acústico. Medido con la envolvente RMS de 2 ms:

| archivo | ataque real | muestras recortadas al ras | duración |
|---|---|---|---|
| `shot_1.wav` | 22 ms | 15 | 700 ms |
| `shot_2.wav` | **432 ms** | 7 | 700 ms |
| `shot_3.wav` | 228 ms | 11 | 700 ms |
| `shot_4.wav` | 156 ms | 4 | 700 ms |
| `shot_5.wav` | 90 ms | 2 | 700 ms |

Es decir: el juego reproducía entre 22 y 432 ms de material que **no** era el
estampido antes de que llegara el estampido. En `shot_2.wav` el oyente oía
ruido de manejo durante casi medio segundo y luego el disparo.

Además, la grabación original declara **6 disparos** y sus ataques medidos están
en `0.1190 / 0.3410 / 0.7800 / 0.9860 / 1.1640 / 1.3470 s` — intervalos de
178-222 ms, o sea una **rafaga real de Glock 18c a 1100-1360 RPM**. Las ventanas
de 700 ms metían el disparo **vecino** dentro de la muestra, así que un clic del
jugador disparaba dos disparos grabados.

**Corrección.** Los 5 disparos se cortan ahora de la grabación original en su
ataque medido, con la cola acotada al hueco real hasta el disparo siguiente menos
35 ms de margen (tabla `SHOT_CUTS` de `tools/process_audio.sh`). Verificado: los
5 ataques caen en **0-2 ms**, **0 muestras recortadas** y **0 material previo** al
estampido. La grabación original se versiona en
`assets/audio/source/sonniss_gdc2016_glock18c_1m.wav` (md5
`692d47763d6af32ee551312f24868b38`) para que el corte sea reproducible.

**La capa mecánica también competía, y se bajó.** `slide.wav` es un chasquido con
el **63% de su energía entre 2,5 y 16 kHz**, mientras que el estampido la tiene en
800-2500 Hz. Entra a **12,7 ms** del disparo (el tope trasero real de la
corredera, calculado del resorte de `Glock.gd`: k=4000, c=80, v0=5,45 m/s,
recorrido 39 mm). Al mismo nivel que el disparo no se oía *debajo* del blast, se
oía **al lado**. Medido en el mix, energía relativa en agudos de la ventana
13-40 ms: 0,17 sin capa mecánica, **0,43 a -10 dB**, 0,22 a -20 dB. Ahora está en
**-18 dB**, que aporta profundidad mecánica sin competir con el estampido.

**Fuera los compresores de bus.** El de `Weapons` (thr -14 dB, 3:1) daba sólo
**2,2 dB** de reducción en el ataque y **0** en las colas, así que no protegía
nada; su release de 120 ms devolvía ganancia justo durante la cola del disparo,
que es la clase de bombeo que hace que un solo disparo se perciba como dos. Con
los WAV ya normalizados por familia, cada bus sólo lleva su nivel y Master queda
con un techo de seguridad.

**Alineación al ataque (del resto de la foley).** El modo antiguo comparaba
bloques de 20 ms de RMS contra el bloque más fuerte con 12 dB de margen. Un ruido
de sala 30 dB por debajo del golpe no lo activaba, así que el archivo se dejaba
intacto y **el evento sonaba tarde**. Peor: el umbral se fijaba sobre el **pico de
muestra**, así que un único sample alto o recortado al principio lo hundía y el
detector no veía nada — el fallo exacto de `shot_2.wav`.

| archivo | retraso del ataque antes | ahora |
|---|---|---|
| `magin.wav` | 464 ms | 1 ms |
| `slide.wav` | 10 ms | 0 ms |
| `magout.wav` | 11 ms | 10 ms |
| `impact_concrete.wav` | 91 ms | 91 ms |
| `empty_b.wav` | 26 ms | 26 ms |
| `footstep.wav`, `impact_wood.wav`, `ricochet.wav` | 9-10 ms | 9-10 ms |
| `shot_1..5.wav` | 22-432 ms | **0-2 ms** |

(En los impactos y pasos el "ataque" medido es el primer instante dentro de 20 dB
de la envolvente máxima, que en esas tomas es ruido de sala anterior al golpe: no
es un retraso del evento, y no empeoró.)

La detección nueva usa una **envolvente RMS de 1 ms calculada en awk** sobre las
muestras crudas (`envelope1ms`), con el umbral relativo al pico de esa envolvente.
No se usa `astats` con `reset` pequeño: su reset se queda en el tamaño de frame
(2048 muestras ≈ 46 ms), así que la resolución nunca baja de ahí.

## Fuentes

- **Los 5 disparos** son tomas de una misma grabación de Glock 18c (micrófono MKH416 a 1 m) del **Sonniss #GameAudioGDC Bundle (2016)**, cuya licencia está en el `Licensing.pdf` que acompaña al bundle: concede uso **comercial, mundial y libre de regalías, sin obligación de atribución**, y prohíbe revender los WAV tal cual (dentro del juego sí se pueden usar). Se acredita igualmente por cortesía.
- `assets/audio/source/sonniss_gdc2016_glock18c_1m.wav`: fichero original del bundle, ruta interna `Sonniss.com - GDC 2016- Game Audio Bundle/Pole Position Production - Glock 18c/Glock_18_1m_left_off_axis_MKH416_clean_Six_shots_x_1.wav`, 96 kHz / 24 bits / mono, 3,7333 s. Es la fuente de la que se cortan `shot_1..5.wav`. Los seis disparos que anuncia el nombre del fichero son los seis ataques medidos arriba: cuadra.
- `shot_1.wav` … `shot_5.wav`: 5 disparos separados de esa grabación — Sonniss #GameAudioGDC Bundle 2016 — https://sonniss.com/gameaudiogdc — licencia Sonniss (royalty-free comercial).
- Motivo medido del cambio a Sonniss (frente a las CC0 anteriores): las 5 variantes CC0 tenían 21-53 dB de relación pico/ruido y dos de ellas concentraban el 85-95% de su energía por debajo de 200 Hz (un "golpe" sordo, sin crack). Las tomas nuevas dan 70-74% en 200-2000 Hz, 11-15% en 2-8 kHz, ataque <1 ms y 50-84 dB de pico/ruido, y todas salen de la misma arma y el mismo micro, así que son coherentes entre sí.
- Tras sustituir cualquier WAV hay que **reimportar** el proyecto (`godot4 --headless --path . --editor --quit`) antes de ejecutarlo: un `.wav` sin importar rompe el autoload de audio entero (el juego se queda sin sonido), porque el `preload` de la tabla de sonidos falla.

- `empty_b.wav`: "9mm Handgun Being Dry Fired" por serøutōnin--deprivəd — https://freesound.org/s/674568/ — CC0 (Freesound).
- `slide.wav`: "glock.wav" por hiramjustus — https://freesound.org/s/55340/ — CC0 (Freesound). Se alinea a su pico (su golpe bueno está a 0,4 s dentro del archivo original) y se reproduce a **-18 dB**: es la única fuente del arma que no está a nivel de familia, y el motivo está medido arriba (su energía vive en 2,5-16 kHz, donde el estampido no tiene nada). **Es el candidato número uno a sustituir si algún día se quiere más cuerpo mecánico**: las tomas de corredera de Freesound que lo mejorarían ("Sig Sauer P229 Handgun slide rack" de nikkolaus, https://freesound.org/s/442560/, CC0; "Taurus G2c Slide Racking" de NoonerBear, https://freesound.org/s/589849/, CC0, 27 eventos para variación) requieren cuenta gratuita en Freesound para descargar, y este entorno no la tiene.
- `magout.wav`: "Magazine Removal" por brianhanson2nd — https://freesound.org/s/171208/ — CC0 (Freesound).
- `magin.wav`: "Magazine Insert" por brianhanson2nd — https://freesound.org/s/171209/ — CC0 (Freesound).
- `ricochet.wav`: "bullet ricochet.wav" por aust_paul — https://freesound.org/s/30932/ — CC0 (Freesound).
- `shell_drop.wav`: "Metal_Shell_Spin_10" por BlondPanda — https://freesound.org/s/777923/ — CC0 (Freesound).
- `impact_metal.wav`: "Fast Collision Reverb" por qubodup — https://freesound.org/s/332057/ — CC0 (Freesound).
- `impact_concrete.wav`: "Stone on Stone Hit" por xtra1 — https://freesound.org/s/858891/ — CC0 (Freesound).
- `impact_wood.wav`: "Wooden Blocks" por NearTheAtmoshphere — https://freesound.org/s/676457/ — CC0 (Freesound).
- `footstep.wav`: "Footsteps on concrete" por florianreichelt — https://freesound.org/s/459964/ — CC0 (Freesound).

Esta lista refleja únicamente los WAV que existen actualmente en `assets/audio/`; si se reemplaza un sonido, actualizar el crédito en el mismo commit.

## Alternativas evaluadas y no adoptadas

Se revisaron ~240 candidatos para corredera, cargador y casquillo (Freesound CC0, OpenGameArt, Wikimedia, Sonniss). La foley CC0 actual se queda porque las alternativas no mejoraban lo que ya hay o no eran utilizables:

- Las mejores tomas de corredera/cargador de Freesound (p. ej. "Glock 19 slide cocking" de jackthemurray, 36 variaciones) sólo son descargables como **preview MP3 de 192 kbps** sin iniciar sesión, y varias muestran clipping en el preview. No se sustituye un WAV por un MP3 recortado.
- Las tomas de Sonniss para mecánica (`Steyr TMP9 cocking`, `HK G36C mag in/out`, `M1911A1 dryfire`) son buenas pero el juego ya tiene su propia foley CC0 coherente con el arma; cambiarla no aportaba una mejora medible.
- Descartados por licencia: Wikimedia `9 mm gunshot-mike-koenig-123.wav` (CC BY-SA 4.0, incompatible con el criterio del proyecto), OpenGameArt `gunshots` de kurt (CC0 pero procedencia no acreditada: "no son mis armas") y `gamesounds.xyz` (no declara licencia).
