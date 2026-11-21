# Engine spike (Step 0)

Throwaway test scenes behind `ENGINE.md`. Not part of the game.

- `scene_spike/`: flutter_scene 0.24.3 test scene. `?shadow=1` and `?upscale=1` URL params on web select the shadow proof and the custom-upscale path.
- `thermion_spike/`: Thermion 0.7.0 test scene (runtime-compiled Filament water material).
- `tools/`: Playwright capture scripts and a COOP/COEP static server (Thermion web needs cross-origin isolation).
- `captures/`: screenshots and console logs cited in ENGINE.md.
- `apk/`: release arm64 APKs of both spikes (debug-key signed) for an optional on-device fold test.

Spike-only assets:
- `scene_spike/assets/env.hdr`: Poly Haven "Kloppenheim 06" 1k HDRI, CC0.
- `thermion_spike/assets/*`: Thermion example assets (cube.glb, Filament default environment KTX), Apache-2.0.
