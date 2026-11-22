# Assets

Only CC0 assets ship in the app. Every file is logged here with its source, URL and licence.

| File in app | Source | URL | Licence | Notes |
|---|---|---|---|---|
| `assets/env/qwantani_dusk_2_1k.hdr` | Poly Haven, "Qwantani Dusk 2" by Greg Zaal and Jarod Guest | https://polyhaven.com/a/qwantani_dusk_2 | CC0 | Dusk sky for image-based lighting and water reflections (1k, 1.6 MB). Added in M2. |
| `assets/textures/water_normal.png` | Procedural, `tools/bake/bake_water_textures.py` | (generated) | CC0 (original work) | Tileable ripple normals and foam/rain noise, 512². |
| `assets/textures/caustics.png` | Procedural, same script | (generated) | CC0 (original work) | Tileable caustics from a photon splat through a rippled surface, 512². |
| Course, terrain, rocks, pebble bed, fireflies, leaves | Procedural (code) | (generated) | CC0 (original work) | The pebble bed is a shader (`assets/materials/ground.fmat`). |

Planned sources (PLAN.md §3): Poly Haven models, textures and HDRIs, and ambientCG materials, all CC0. Audio will be synthesised offline (`tools/audio/`), so it is CC0 by construction.

`references/` holds the critic's benchmark photos. They have their own licences (see `references/SOURCES.md`) and are never packaged into the app.
