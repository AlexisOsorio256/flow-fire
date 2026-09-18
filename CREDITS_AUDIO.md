# Créditos de audio

Sólo créditos: archivo actual, fuente, autor, licencia y qué se le hizo. La
investigación (pruebas, descartes y medidas) vive en la historia de Git, no aquí.

Todos los WAV están convertidos a 48 kHz mono 16-bit con `tools/process_audio.sh`
(ffmpeg), alineados a su ataque y normalizados por familia. Ese script es la
única transformación reproducible; los masters que sí se versionan están en
`assets/audio/source/`.

## Familia arma (bus `Weapons`)

| archivo | fuente | autor / licencia | transformación |
|---|---|---|---|
| `shot_1..5.wav` | grabación de Glock 18c a 1 m, micrófono MKH416 — Sonniss #GameAudioGDC Bundle 2016 | Pole Position Production / Sonniss EULA (comercial, sin atribución) | 5 disparos cortados en su ataque desde `assets/audio/source/sonniss_gdc2016_glock18c_1m.wav`; a cada uno se le fusiona el cuerpo grave de `assets/audio/source/beretta93r_body_excerpt.wav` (Beretta 93R a 1 m, −4 dB) |
| `magin.wav`, `magout.wav`, `handling.wav` | foley de cargador, micro MKH60 close-up — Sonniss #GameAudioGDC Bundle 2016 | Heckler & Koch G36C (Sonniss EULA) | cortes de `assets/audio/source/g36c_mag_in_out_excerpt.wav`; el clack del asiento cae ~60 ms dentro de `magin.wav` y `Glock.gd` lo adelanta ese tiempo |
| `empty_b.wav` | "9mm Handgun Being Dry Fired" | serøutōnin--deprivəd — https://freesound.org/s/674568/ — CC0 | alineado al ataque |
| `slide_rear.wav` | "Glock 19 Handgun Pistol Slide Cocking Sounds" (evento de 10,972 s) | jackthemurray — https://freesound.org/s/393734/ — CC0 | corte al ataque (tope trasero de la corredera) |
| `slide_battery.wav` | "Sig Sauer P229 Handgun slide rack.wav" (evento de 4,016 s) | nikkolaus — https://freesound.org/s/442560/ — CC0 | corte al ataque (vuelta a batería) |
| `slide_hand.wav` | "Metal Contact" (contact small metal box lid subtle hits) | SoundHolder / Sonniss #GameAudioGDC Bundle 2017, espejo `http://ftpmirror.your.org/pub/misc/sonniss2017/` — EULA comercial sin atribución | recortado |

### Foley sintetizado (sin master)

Estos no vienen de ninguna grabación: son eventos que estaban mudos y se
sintetizan en `tools/make_weapon_sounds.py`, que es su fuente y su licencia
(propia, CC-BY-4.0 como el resto del proyecto). Regenerarlos es volver a
ejecutarlo y reimportar.

| archivo | evento | carácter |
|---|---|---|
| `mag_drop.wav` | el cargador vacío rebotando en hormigón | cinco rebotes, cada uno más flojo y grave |
| `mag_slap.wav` | la palma en la culata al asentarlo | golpe sordo con resto de metal |
| `mag_insert.wav` | el cargador rozando el brocal al subir | metal contra metal, costillas y resorte |
| `slide_release.wav` | el retén de la corredera al soltarse | tic de acero corto y agudo |
| `chamber_check.wav` | comprobar la recámara | dos clics de acero con el muelle tensándose |
| `reload_rustle.wav` | ropa y correaje durante la recarga | ruido de banda con tres agarres |

## Familia mundo (bus `World`)

| archivo | fuente | autor / licencia | transformación |
|---|---|---|---|
| `impact_concrete.wav` | "Bullet Impact Sounds" (`bullet_impact_concrete_brick_01`) | Gamemaster Audio / Sonniss #GameAudioGDC Bundle 2017 — EULA comercial sin atribución | alineado al ataque |
| `impact_drywall.wav` | la misma grabación que `impact_concrete` (familia mineral) | Gamemaster Audio / Sonniss 2017 | copia alineada |
| `impact_metal.wav` | "Bullet Impact Sounds" (`bullet_impact_metal_heavy_08`) | Gamemaster Audio / Sonniss 2017 | alineado al ataque |
| `impact_wood.wav` | "Wooden Blocks" | NearTheAtmoshphere — https://freesound.org/s/676457/ — CC0 | alineado al ataque |
| `ricochet.wav` | "The Warfare Library" (`warfare_t3_mg_whizzes_ricochets_bullet_cracks_M10`) | Pole Position / Sonniss #GameAudioGDC Bundle 2017 | recorte de 3,0 s |
| `bullet_flyby.wav` | "Bullet Impact Sounds" (`bullet_flyby_fast_05`) | Gamemaster Audio / Sonniss 2017 | alineado al ataque |
| `shell_drop.wav` | "Metal_Shell_Spin_10" | BlondPanda — https://freesound.org/s/777923/ — CC0 | alineado al ataque |
| `footstep.wav` | "Footsteps on concrete" | florianreichelt — https://freesound.org/s/459964/ — CC0 | alineado al ataque |

Los EULA de Sonniss conceden uso comercial mundial, libre de regalías y sin
obligación de atribución; se acredita igualmente por cortesía. Si se reemplaza un
WAV, se actualiza su fila en el mismo cambio.
