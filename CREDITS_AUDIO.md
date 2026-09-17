# Créditos de audio

Sonidos reales procesados con `tools/process_audio.sh` (ffmpeg): cada one-shot se alinea con su ataque, se iguala la loudness dentro de cada familia y se recorta la cola con fade.

## El disparo sonaba dos veces: causa medida (corregido)

El disparo base gustaba, pero se percibía un segundo golpe inmediatamente después.
Se encontraron **tres** causas, y la tercera sólo apareció después de arreglar las
dos primeras.

### Causa 1 — las muestras no empezaban en su ataque

Los `shot_N.wav` anteriores eran ventanas de 700 ms cortadas a mano de la misma
rafaga, y su "ataque" (el pico de muestra, que es lo que medía el script) no
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

### Causa 2 — la capa mecánica usaba el MISMO archivo dos veces

Los dos golpes de la corredera son dos eventos físicos distintos: el **tope
trasero** a ~12 ms (la corredera toca 38-39 mm) y la
**vuelta a batería** a ~54 ms. Los dos usaban el mismo `slide.wav` —un chasquido
con el 63% de su energía entre 2,5 y 16 kHz— con distinto volumen y pitch, así
que el oído recibía el mismo transitorio dos veces separado 42 ms: exactamente
lo que se percibe como "BANG + otro golpe".

**Corrección.** Cada evento tiene ahora su propia grabación real, y de armas
distintas para que no puedan confundirse:

| muestra | evento | fuente | pico | centroide | reparto espectral |
|---|---|---|---|---|---|
| `slide_rear.wav` | tope trasero (~12 ms) | Glock 19 real | −0,85 dBFS | 7221 Hz | 85% >2,5 kHz |
| `slide_battery.wav` | vuelta a batería (~54 ms) | Sig P229 real | −9,82 dBFS | 774 Hz | 75% <800 Hz |

El trasero va a **−17 dB** y el de batería a **−15 dB**: la
energía del primero vive en agudos, donde el estampido ya no compite, y la del
segundo en graves, donde sí compite con la cola del estampido. (Antes −14/−18:
medido después, el trasero caía a solo −6,9 dB del blast en >2,5 kHz y se leía
como segundo golpe, y la batería quedaba 27 dB bajo la cola: inaudible. El
rebalanceo −3/+3 dB deja el crack ~10 dB bajo el blast y devuelve su peso al
cierre.) Medido en la
captura real, en la ventana 26-45 ms el centroide sube a
**2700-3000 Hz** con el 34-43% de la energía por encima de 2,5 kHz, que es
exactamente la huella del tope trasero, y el estampido conserva el dominio (su
ataque sigue 6-9 dB por encima de la mecánica). Antes de este cambio la capa
mecánica aportaba sólo 0,13-0,17 dB a su ventana: era inaudible.

### Causa 3 — dentro de la muestra, el mecánico pesaba tanto como el estampido

Ésta no se veía hasta arreglar las dos anteriores. Medido en los 5 disparos:

| ventana | pico | rms | energía del archivo |
|---|---|---|---|
| estampido 0-20 ms | -1.20 dB | -6,0…-7,0 dB | **35-54%** |
| mecánico 20-110 ms | **-1.20 dB** | -10,8…-14,2 dB | **46-52%** |

Dos datos clave: **los dos picos son idénticos** (~-1.20 dBFS), y el mecánico
dura 90 ms contra los 20 del estampido, así que en energía total lo empata o lo
supera. Eso es exactamente lo que el oído lee como dos golpes del mismo tamaño.

Se probó primero un **compresor de ataque** (thr -12 dB 3:1 y -10 dB 2:1, attack
1 ms, release 35-40 ms) y **empeora**: la energía se mueve *hacia* el mecánico
(49% → 56%) y la cola sube (3,7% → 6,4%), porque el release devuelve ganancia
antes de que la cola acabe. Es un problema de **reparto**, no de dinámica, y esa
vía queda descartada con medición.

**Corrección.** El mecánico se hunde **7 dB** con una rampa (1.0 hasta 25 ms,
lineal hasta -7 dB en 45 ms, constante después), en `tools/process_audio.sh` y no
en el motor, para que el pico de la muestra siga siendo el del estampido. El
ataque **no se toca**: el disparo que gusta queda intacto en pico y en RMS.

| | antes | después |
|---|---|---|
| pico de la muestra | -1.20 dBFS | **-1.20 dBFS** (intacto) |
| rms del estampido | -6,0…-7,0 dB | **igual** (intacto) |
| relación estampido/mecánico | +4,8…+7,3 dB | **+9,2…+11,1 dB** |
| energía del estampido | 35-54% | **62-74%** |
| muestras recortadas | 0 | **0** |

En el mix real: pico **-5,05 dBFS**, 0 recortadas, y la estructura del disparo
pasa a ser estampido dominante con la cola 12-20 dB por debajo, en vez de un
segundo bloque a 4,6 dB.

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
| `slide_rear.wav`, `slide_battery.wav` | 10 ms | 0 ms |
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
- `slide_rear.wav`: **tope trasero de la corredera**, cortado del evento de 10,972 s de "Glock 19 Handgun Pistol Slide Cocking Sounds" por jackthemurray — https://freesound.org/s/393734/ — CC0 (Freesound). Es el pico más agudo y limpio de la toma (85% de energía >2,5 kHz, 0 muestras recortadas). Se corta en su ataque real y se alinea por transitorio con `tools/process_audio.sh`.
- `slide_battery.wav`: **vuelta a batería**, cortado del evento de 4,016 s de "Sig Sauer P229 Handgun slide rack.wav" por nikkolaus — https://freesound.org/s/442560/ — CC0 (Freesound). Es el golpe más sordo y con más cuerpo disponible (75% de energía <800 Hz, centroide 774 Hz, 0 muestras recortadas): el contrapunto exacto del tope trasero. Las dos muestras vienen ya recortadas a su ataque desde el origen, así que la primera pasada del script no tiene que buscar nada.
- `slide.wav` (retirado): era "glock.wav" por hiramjustus — https://freesound.org/s/55340/ — CC0 (Freesound). Se eliminó al sustituirse por los dos eventos reales de arriba: usar la misma muestra para el tope trasero y para la batería era la causa medida del "BANG + otro golpe". No se conserva como variante.
- `magout.wav`: **extraccion del cargador** (clic del reten + friccion, 105 ms, pico -8 dBFS), cortado de `Heckler_&_Koch_G36C_5.56mm_foley_close_up_MKH60_mag_in_&_out.wav` (misma toma y micro que `magin`: pareja coherente) — Sonniss #GameAudioGDC Bundle 2016 — https://sonniss.com/gameaudiogdc — licencia Sonniss (royalty-free comercial). Sustituye al "Magazine Removal" de brianhanson2nd (Freesound CC0, retirado): grabacion mas fina, ataque limpio y sin sala.
- `magin.wav`: **insercion + asiento del cargador** (el clack cae ~60 ms dentro de la muestra; `Glock.gd` dispara el evento 60 ms antes del contacto para que caiga en el asiento), cortado de la misma toma que `magout` — Sonniss #GameAudioGDC Bundle 2016, misma licencia. El ciclo elegido (11.39-11.55 s) tiene 0 muestras al ras; se descartaron otros asientos de la misma toma con 4-14 muestras recortadas. Sustituye al "Magazine Insert" de brianhanson2nd (retirado, mismo motivo).
- `assets/audio/source/g36c_mag_in_out_excerpt.wav`: recorte 11.38-11.70 s de la toma original, 96 kHz / 24 bits / mono. Es la fuente versionada de la que se cortan `magin`/`magout` con `tools/process_audio.sh` (`process_mag`).
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
  - Matiz 2026-09: el `mag in/out` del G36C (close-up MKH60, 96/24) SÍ se adoptó para `magin`/`magout` (ver Fuentes): la foley anterior de cargador seguía sonando barata y la toma nueva es objetivamente más limpia. En cambio el `cocking & dry fire` del Steyr TMP se evaluó y se rechazó: es micro distante con sala (~-25 dB de pico y cola reverberante) y empeoraría el `empty`/corredera actuales, que son primeros planos.
- Descartados por licencia: Wikimedia `9 mm gunshot-mike-koenig-123.wav` (CC BY-SA 4.0, incompatible con el criterio del proyecto), OpenGameArt `gunshots` de kurt (CC0 pero procedencia no acreditada: "no son mis armas") y `gamesounds.xyz` (no declara licencia).

## Assets nuevos de esta pasada (2026-09)

Impactos y mecanica. Todos WAV, convertidos a 48 kHz mono 16-bit con ffmpeg y
normalizados a -16 LUFS / pico -1.5 dB (mismo criterio que el resto).

| archivo | fuente | licencia |
|---|---|---|
| `impact_concrete.wav` | Gamemaster Audio - Bullet Impact Sounds (`bullet_impact_concrete_brick_01`) | Sonniss GDC Bundle EULA: uso comercial y personal, sin atribucion |
| `impact_metal.wav` | Gamemaster Audio - Bullet Impact Sounds (`bullet_impact_metal_heavy_08`) | idem |
| `impact_drywall.wav` | misma grabacion que `impact_concrete` (el pladur comparte familia mineral) | idem |
| `impact_flesh.wav` | Gamemaster Audio - Bullet Impact Sounds (`bullet_impact_body_thump_02`) | idem |
| `ricochet.wav` | Pole Position - The Warfare Library (`warfare_t3_mg_whizzes_ricochets_bullet_cracks_M10`), recortado | idem |
| `bullet_flyby.wav` | Gamemaster Audio - Bullet Impact Sounds (`bullet_flyby_fast_05`) | idem |
| `slide_hand.wav` | SoundHolder - Metal Contact (`contact small metal box lid subtle hits`), recortado | idem |

Fuente: Sonniss #GameAudioGDC Bundle 2017, espejo publico
`http://ftpmirror.your.org/pub/misc/sonniss2017/`. El EULA esta en
`http://ftpmirror.your.org/pub/misc/sonniss2017/Licensing.pdf`: licencia
mundial, no exclusiva, libre de regalias, para proyectos personales y
comerciales, sin necesidad de atribucion. Se acredita igualmente aqui.

Nota de licencia descartada: Freesound tiene buenas grabaciones CC0 de recarga
(p. ej. el sonido 456195), pero solo ofrece previsualizaciones MP3 con perdida
sin cuenta; no se han usado.
