# Créditos de audio

Sonidos reales procesados con `tools/process_audio.sh` (ffmpeg): cada one-shot se alinea con su ataque, se iguala la loudness dentro de cada familia y se recorta la cola con fade.

**Los 5 disparos** son tomas de una misma grabación de Glock 18c (micrófono MKH416 a 1 m) del **Sonniss #GameAudioGDC Bundle (2016)**, cuya licencia está en el `Licensing.pdf` que acompaña al bundle: concede uso **comercial, mundial y libre de regalías, sin obligación de atribución**, y prohíbe revender los WAV tal cual (dentro del juego sí se pueden usar). Se acredita igualmente por cortesía.

- `shot_1.wav` … `shot_5.wav`: 5 disparos separados de `Sonnis/GDC 2016/Weapons/Glock 18c/Glock 18c 1m.wav` — Sonniss #GameAudioGDC Bundle 2016 — https://sonniss.com/gameaudiogdc — licencia Sonniss (royalty-free comercial).
- Motivo medido del cambio: las 5 variantes CC0 anteriores tenían 21-53 dB de relación pico/ruido y dos de ellas concentraban el 85-95% de su energía por debajo de 200 Hz (un "golpe" sordo, sin crack). Las tomas nuevas dan 70-74% en 200-2000 Hz, 11-15% en 2-8 kHz, ataque <1 ms y 50-84 dB de pico/ruido, y todas salen de la misma arma y el mismo micro, así que son coherentes entre sí. Las anteriores quedan en `/tmp/audio_cc0_antes` por si hiciera falta comparar.

- Los 5 disparos comparten loudness de ataque (-10 dB en los primeros 250 ms): antes había 27 dB de diferencia entre variantes y cada disparo sonaba a una distancia distinta.
- Tras sustituir cualquier WAV hay que **reimportar** el proyecto (`godot4 --headless --path . --editor --quit`) antes de ejecutarlo: un `.wav` sin importar rompe el autoload de audio entero (el juego se queda sin sonido), porque el `preload` de la tabla de sonidos falla.
- `slide.wav` se recorta a su golpe útil (0.4 s dentro del archivo original) para que la capa mecánica del disparo coincida con la corredera.
- `magin.wav` tenía 0.45 s de silencio delante: ahora el clic del cargador suena cuando entra.

- `empty_b.wav`: "9mm Handgun Being Dry Fired" por serøutōnin--deprivəd — https://freesound.org/s/674568/ — CC0 (Freesound).
- `slide.wav`: "glock.wav" por hiramjustus — https://freesound.org/s/55340/ — CC0 (Freesound).
- `magout.wav`: "Magazine Removal" por brianhanson2nd — https://freesound.org/s/171208/ — CC0 (Freesound).
- `magin.wav`: "Magazine Insert" por brianhanson2nd — https://freesound.org/s/171209/ — CC0 (Freesound).
- `ricochet.wav`: "bullet ricochet.wav" por aust_paul — https://freesound.org/s/30932/ — CC0 (Freesound).
- `shell_drop.wav`: "Metal_Shell_Spin_10" por BlondPanda — https://freesound.org/s/777923/ — CC0 (Freesound).
- `impact_metal.wav`: "Fast Collision Reverb" por qubodup — https://freesound.org/s/332057/ — CC0 (Freesound).
- `impact_concrete.wav`: "Stone on Stone Hit" por xtra1 — https://freesound.org/s/858891/ — CC0 (Freesound).
- `impact_wood.wav`: "Wooden Blocks" por NearTheAtmoshphere — https://freesound.org/s/676457/ — CC0 (Freesound).
- `footstep.wav`: "Footsteps on concrete" por florianreichelt — https://freesound.org/s/459964/ — CC0 (Freesound).

Esta lista refleja únicamente los WAV que existen actualmente en `assets/audio/`; si se reemplaza un sonido, actualizar el crédito en el mismo commit.
