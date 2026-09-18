# Créditos de audio

Sólo créditos: archivo actual, fuente, autor, licencia y qué se le hizo. La
investigación (pruebas, descartes y medidas) vive en la historia de Git, no aquí.

La mayoria de WAV se convierten a 44,1 kHz mono 16-bit con `tools/process_audio.sh`
(ffmpeg), alineados a su ataque y normalizados por familia. Los cuatro de Foley
sintetizado NO los toca ese script: los genera `tools/make_weapon_sounds.py`.
Los masters versionados estan en `assets/audio/source/` (con `.gdignore` para
que Godot no los importe).

## Familia arma (bus `Weapons`)

| archivo | fuente | autor / licencia | transformación |
|---|---|---|---|
| `shot_1..5.wav` | PLACEHOLDER compuesto (no G19 pura): crack de Glock 18c a 1 m, micrófono MKH416 — Sonniss #GameAudioGDC Bundle 2016; cuerpo de una Beretta 93R a 1 m, mismo bundle y mismo tipo de micro | Pole Position Production / Sonniss EULA (comercial, sin atribución) | 5 disparos cortados en su ataque desde `assets/audio/source/sonniss_gdc2016_glock18c_1m.wav`; `tools/build_shot.py` les monta el cuerpo grave de `assets/audio/source/beretta93r_body_excerpt.wav` (paso bajo a 900 Hz, −4 dB, alineado por ataque, decaimiento tau 28 ms) y doma la cola horneada del crack (intacto 30 ms, tau 40 ms) para UN solo golpe (ataque 13-18 dB sobre cola 60-140 ms, medido). DRY sin sala horneada (la sala la pone el bus Range). Quedan en 360 ms, pico −1,2 dBFS, cresta ~20, grave ~20 %, centroide ~2,1 kHz e igual loudness de ataque |
| `magin.wav`, `magout.wav` | foley de cargador, micro MKH60 close-up — Sonniss #GameAudioGDC Bundle 2016 | Heckler & Koch G36C (Sonniss EULA) | cortes de `assets/audio/source/g36c_mag_in_out_excerpt.wav`; el clack del asiento cae ~60 ms dentro de `magin.wav` y `Glock.gd` lo adelanta ese tiempo |
| `empty_b.wav` | "9mm Handgun Being Dry Fired" | serøutōnin--deprivəd — https://freesound.org/s/674568/ — CC0 | alineado al ataque |
| `slide_rear.wav` | "Glock 19 Handgun Pistol Slide Cocking Sounds" (evento de 10,972 s) | jackthemurray — https://freesound.org/s/393734/ — CC0 | corte al ataque (tope trasero de la corredera) |
| `slide_battery.wav` | "Sig Sauer P229 Handgun slide rack.wav" (evento de 4,016 s) | nikkolaus — https://freesound.org/s/442560/ — CC0 | corte al ataque (vuelta a batería) |
| `slide_hand.wav` | "Metal Contact" (contact small metal box lid subtle hits) | SoundHolder / Sonniss #GameAudioGDC Bundle 2017, espejo `http://ftpmirror.your.org/pub/misc/sonniss2017/` — EULA comercial sin atribución | recortado |

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

| archivo | fuente | autor / licencia | transformación |
|---|---|---|---|
| `impact_concrete.wav` | "Bullet Impact Sounds" (`bullet_impact_concrete_brick_01`) | Gamemaster Audio / Sonniss #GameAudioGDC Bundle 2017 — EULA comercial sin atribución | alineado al ataque |
| `impact_drywall.wav` | la misma grabación que `impact_concrete` (familia mineral) | Gamemaster Audio / Sonniss 2017 | copia alineada |
| `impact_metal.wav` | "Bullet Impact Sounds" (`bullet_impact_metal_heavy_08`) | Gamemaster Audio / Sonniss 2017 | alineado al ataque |
| `impact_aluminum.wav` | `impact_metal.wav` como fuente de proyecto | Gamemaster Audio / Sonniss 2017 | derivado offline: high-pass/treble/tempo y nivel menor; 538 ms, pico −3,4 dBFS, RMS −24,3 dBFS, cresta 11,1; no comparte master ni pitch runtime con acero |
| `impact_wood.wav` | "Wooden Blocks" | NearTheAtmoshphere — https://freesound.org/s/676457/ — CC0 | alineado al ataque |
| `ricochet.wav` | "The Warfare Library" (`warfare_t3_mg_whizzes_ricochets_bullet_cracks_M10`) | Pole Position / Sonniss #GameAudioGDC Bundle 2017 | recorte de 3,0 s |
| `bullet_flyby.wav` | "Bullet Impact Sounds" (`bullet_flyby_fast_05`) | Gamemaster Audio / Sonniss 2017 | alineado al ataque |
| `shell_drop.wav` | "Metal_Shell_Spin_10" | BlondPanda — https://freesound.org/s/777923/ — CC0 | alineado al ataque |
| `footstep.wav` | "Footsteps on concrete" | florianreichelt — https://freesound.org/s/459964/ — CC0 | alineado al ataque |

Los EULA de Sonniss conceden uso comercial mundial, libre de regalías y sin
obligación de atribución; se acredita igualmente por cortesía. Si se reemplaza un
WAV, se actualiza su fila en el mismo cambio.
