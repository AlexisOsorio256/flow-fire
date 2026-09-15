# Créditos de audio

Sonidos reales con licencia **Creative Commons 0 (CC0)**, descargados de Freesound.org y procesados con `tools/process_audio.sh` (ffmpeg): cada one-shot se alinea con su ataque, se iguala la loudness dentro de cada familia y se recorta la cola con fade.

- Los 5 disparos comparten loudness de ataque (-10 dB en los primeros 250 ms): antes había 27 dB de diferencia entre variantes y cada disparo sonaba a una distancia distinta.
- `slide.wav` se recorta a su golpe útil (0.4 s dentro del archivo original) para que la capa mecánica del disparo coincida con la corredera.
- `magin.wav` tenía 0.45 s de silencio delante: ahora el clic del cargador suena cuando entra.
- Se descartó `shot_6.wav` (S&W M&P9 Shield, AnthonyChan0): tras igualar su loudness (+21 dB) su ruido de fondo quedaba al mismo nivel que el disparo.

- `shot_1.wav`: "Gun Shot Close.wav" por udikagan — https://freesound.org/s/147317/ — CC0 (Freesound).
- `shot_2.wav`: "Gunshot_002.wav" por Brokenphono — https://freesound.org/s/344142/ — CC0 (Freesound).
- `shot_3b.wav`: "9mm pistol shot" por michorvath — https://freesound.org/s/427592/ — CC0 (Freesound).
- `shot_4.wav`: "Small pistol gunshot indoors" por acidsnowflake — https://freesound.org/s/402789/ — CC0 (Freesound).
- `shot_5.wav`: "9mm.mp3" por ngphil22 — https://freesound.org/s/233318/ — CC0 (Freesound).
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
