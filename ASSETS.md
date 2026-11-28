# Assets

Only CC0 assets ship in the app. Every file is logged here with its source, URL and licence.

| File in app | Source | URL | Licence | Notes |
|---|---|---|---|---|
| `assets/env/blue_hour_forest.hdr` | Derived from Poly Haven "Aarfontein Dawn" by Greg Zaal (photography) and Jarod Guest (processing) | https://polyhaven.com/a/aarfontein_dawn | CC0 (derivative of a CC0 work) | Blue-hour sky (1k). `tools/bake/bake_env.py` removes bright points (Venus, stars) and puts a ragged forest treeline below about 21°, so only the open sky overhead lights the scene. Added in M4 to replace Qwantani Dusk 2 (M2–M3), whose purple mid-sky gave the lavender cast. |
| `assets/textures/water_normal.png` | Procedural, `tools/bake/bake_water_textures.py` | (generated) | CC0 (original work) | Tileable ripple normals and foam/rain noise, 512². |
| `assets/textures/caustics.png` | Procedural, same script | (generated) | CC0 (original work) | Tileable caustics from a photon splat through a rippled surface, 512². |
| `assets/textures/sky_blue.png` | Derived from `blue_hour_forest.hdr` above, `tools/bake/bake_sky.py` | (generated) | CC0 (derivative of a CC0 work) | 128x64 blurred equirect, sqrt-encoded (scale 1.3939), for the water's own sky reflection. Replaced `sky_dusk.png` in M4. |
| `assets/rocks/rocks.bin` | Poly Haven "Rock Moss Set 01" and "Rock Moss Set 02" by Kless Gyzen (photogrammetry) | https://polyhaven.com/a/rock_moss_set_01, https://polyhaven.com/a/rock_moss_set_02 | CC0 | 13 scanned mossy rocks from the 2k glTF, decimated to 2,400 triangles each by `tools/bake/bake_rocks.py`, then normalised and converted to native axes (1.0 MB). Added in M3. |
| `assets/textures/surfaces/rock_moss_set_0{1,2}_{col,nrm,arh}.jpg` | Same two Poly Haven sets (diffuse, GL normal, roughness, AO, displacement) | as above | CC0 | Rock atlases downsampled 2k to 1k and packed by `tools/bake/pack_surface_textures.py`; `arh` = AO, roughness, height. |
| `assets/textures/surfaces/moss_*.jpg` | ambientCG "Moss 001" | https://ambientcg.com/view?id=Moss001 | CC0 | Moss cushions on the banks; 1K JPG set, repacked. |
| `assets/textures/surfaces/forest_ground_*.jpg` | ambientCG "Ground 037" | https://ambientcg.com/view?id=Ground037 | CC0 | Damp forest ground, the bank base layer; 1K JPG set, repacked. |
| `assets/textures/surfaces/mud_*.jpg` | Poly Haven "Brown Mud 02" by Rob Tuytel | https://polyhaven.com/a/brown_mud_02 | CC0 | Wet mud band at the waterline; 1k, repacked. |
| `assets/plants/plants.bin` (ferns) | Poly Haven "Fern 02" | https://polyhaven.com/a/fern_02 | CC0 | Four fern variants (784–2,384 triangles each) from the 1k glTF, converted to native axes and centred by `tools/bake/bake_plants.py`. Added in M6. |
| `assets/plants/plants.bin` (sorrel) | Poly Haven "Shrub Sorrel 01" | https://polyhaven.com/a/shrub_sorrel_01 | CC0 | One ground-cover clump (3,319 triangles) merged from the 1k glTF's eleven sprigs by the same script. Added in M6. |
| `assets/textures/plants/{fern_02,shrub_sorrel_01}_col.png` | Same two Poly Haven models (diffuse and alpha maps) | as above | CC0 | Diffuse with the alpha mask packed into A (1k RGBA) for alpha-tested leaves. |
| Grass clumps | Procedural, `lib/render/vegetation.dart` | (generated) | CC0 (original work) | Tapering, arching blades built at load; colour from a generated base-to-tip gradient. |
| Course, terrain, rock placement and mounds, pebble bed, fireflies, leaves | Procedural (code) | (generated) | CC0 (original work) | The pebble bed is a shader (`assets/materials/ground.fmat`). The greybox icosphere rocks were replaced by the scans in M3. |

Planned sources (PLAN.md §3): Poly Haven models, textures and HDRIs, and ambientCG materials, all CC0. Audio will be synthesised offline (`tools/audio/`), so it is CC0 by construction.

`references/` holds the critic's benchmark photos. They have their own licences (see `references/SOURCES.md`) and are never packaged into the app.

## Audio (M10): procedural, CC0 by construction

`tools/audio/synth_audio.py` generates every sound from noise and sine waves (no recordings, no third-party samples), seeded for reproducibility. Output in `app/assets/audio/`, 22.05 kHz mono 16-bit WAV:

| File | What it is |
|---|---|
| `rain_loop.wav` | 20 s seamless loop: fine rain hiss plus about 45 tiny drop plinks per second of varied pitch and level |
| `stream_loop.wav` | 20 s seamless loop: slow water burble (band-passed noise through wandering resonances) with occasional bubble chirps |
| `firefly.wav` | soft glassy chime (E6 with fifth and octave partials), played when a firefly is collected |
| `knock.wav` | dull wooden knock with a short click, played on a collision |
| `rustle.wav` | wet leaf and paper rustle, played when a leaf smothers the lantern |
| `finale.wav` | slow, soft rising C-major arpeggio, played when the run is won |

