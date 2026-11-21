# LANTERN: engine spike

**Pick: flutter_scene 0.24.3 on Flutter 3.50.1 stable.** I'm waiting for your OK before writing PLAN.md and the reference set.

Both candidates now run on the **stable** channel. flutter_scene stopped needing master in Flutter 3.47, so "prefer stable" doesn't decide this. Thermion fails two must-haves (depth of field and dynamic render resolution); flutter_scene passes all of them.

Spike date 2026-11-21. Toolchain: Flutter 3.50.1 stable (Dart 3.14.0), Android SDK cmdline-tools, platform 36, build-tools 36.0.0, AGP 9.3.1, Kotlin 2.4.20, JDK 21. Sources are in `spike/`, evidence screenshots in `spike/captures/`, and both release APKs (arm64-v8a, signed with the debug key) in `spike/apk/`.

## The test scene (same for both engines)

A small stream:
- a 12 m bed
- two banks
- a custom water material on a plane
- 20 to 40 instanced rocks or cubes
- a "lantern" (emissive body plus a warm point light that casts shadows)
- a cool key light that casts shadows

The camera is the game's: about 55° pitch, a long lens (24–28° vertical FOV), with framing chosen by aspect ratio.

The scene ran on the Flutter **web** build in headless Chromium (SwiftShader WebGL2) through Playwright. Mid-run, the viewport was resized 564×626 → 300×700 → 564×626 (inner screen → cover → inner) without a reload, to stand in for fold and unfold. The same code was built as a **release arm64 APK**.

## Pass/fail

| Must-have | flutter_scene 0.24.3 | Thermion 0.7.0 (Filament 1.77.2) |
|---|---|---|
| Custom shaders/materials (water) | **PASS**: `.fmat` with a vertex stage (displacement), fragment `Surface()`, and engine inputs `scene_color` (refraction) + `scene_depth` (absorption by water thickness). Compiled at build time for Vulkan/GLES/WebGL. One trap: the vertex stage has no `GetTime()`, so time is passed in as a material parameter. | **PASS**: Filament `.mat` compiled at runtime (`runtime_materials: true`) on web and native. Screen-space refraction is built in. |
| PBR + IBL from an HDRI | **PASS**: a Poly Haven `.hdr` loads directly (`scene.loadEnvironment`), prefiltered on device. Supports a blurred skybox. | **PARTIAL**: IBL must be a pre-filtered KTX from Filament's `cmgen`. Thermion ships no HDR→IBL path and no `cmgen`. The spike used the example KTX. |
| Shadows | **PASS**: cascaded directional with PCSS, cube-map point-light shadows, contact shadows. Verified (`flutter_scene_shadow_test.png`). | **PASS**: sun + point `castShadows`, PCF/VSM/soft options. |
| Bloom | **PASS** | **PASS** |
| SSAO/GTAO | **PASS**: GTAO, half-res, bent normals | **PASS**: GTAO via `AmbientOcclusionOptions` |
| Depth of field | **PASS**: physical DoF (focus distance, f-stop, bokeh, quality tiers). This is the tilt-shift look. | **FAIL**: Filament has DoF, but thermion_dart's View API and C API don't bind it. Fixing it means rebuilding the native Filament/Thermion libraries for Android and wasm from source. |
| TAA | **PASS**: Halton jitter, variance clipping, object motion vectors, and a **built-in post-resolve sharpen** | **PASS**: `setAntiAliasing(taa: true)` |
| Fog | **PASS**: exponential + **height fog** (`fogHeight`/`fogHeightFalloff`) + sun in-scatter | **PASS**: Filament height fog with in-scattering |
| Tonemapping | **PASS**: AgX (with white/contrast), ACES, PBR Neutral, plus a `.cube` LUT | **PASS**: ColorGrading builder (AgX available in Filament) |
| Instancing | **PASS**: `InstancedMesh` (40 rocks in one draw) | **PASS**: glTF `createInstance` (20 instances) |
| Dynamic render resolution | **PASS**: `scene.renderScale` toggled 0.7 ↔ 0.85 every 4 s for 60 s with no errors. There is also a built-in adaptive controller (`renderQuality.adaptive`). The engine's own composite is bilinear on native, so I built and verified our own high-quality path: the scene renders at 0.7× into a `RenderTexture`, then a Flutter fragment shader does Catmull-Rom upscale + contrast-adaptive sharpen + TPDF dither at native res (`flutter_scene_custom_upscale.png`; the shader is also compiled into the APK). | **FAIL**: no dynamic-resolution or render-scale binding. The only workaround is a smaller platform texture plus Flutter scaling: bilinear, no TAA upsampling, and it reallocates the external texture. |
| Survives fold/unfold resize without losing GPU state | **PASS (web); native by design.** Two live resizes, every resource intact (`flutter_scene_after_fold.png`, `flutter_scene_after_unfold.png`). Natively it renders inside Flutter's own Impeller/Vulkan context, and the activity declares `screenSize\|smallestScreenSize\|screenLayout\|density` config changes. A fold resizes the Flutter surface; the activity and GPU context are not recreated. **Device test needed** (APK provided). | **PASS (web); riskier natively.** It survived both resizes on web. On Android, Filament runs a *second* GPU context and composites through a `SurfaceTexture`/`SurfaceProducer` (RGBA8). Resizing goes through its surface cleanup/recreate callbacks, which adds one more thing to lose on a fold. |
| Flutter web build for captures | **PASS**: no flags. It has its own WebGL2 backend, the build took 32 s, and it renders under SwiftShader. | **PASS, with friction**: the multithreaded wasm (9.6 MB) needs cross-origin isolation (COOP/COEP headers). I wrote `spike/tools/coi_server.py` for that. |
| Release arm64 APK builds | **PASS**: 20.7 MB. Needs only `<meta-data io.flutter.embedding.android.EnableFlutterGPU=true>`. | **PASS after a workaround**: 30.9 MB. thermion_flutter's Android module compiles against android-33, which fails AndroidX AAR checks until a root Gradle override forces compileSdk 36. |

**Tally:** flutter_scene passes all 13 rows. Thermion fails 2, is partial on 1, and needed workarounds on 2.

### Extras checked because the game needs them

| | flutter_scene | Thermion |
|---|---|---|
| Screen-space reflections / planar reflection for water | SSR, parallax-corrected reflection probes, and a `PlanarReflectorComponent` with a `planar_reflection` material input | Not bound |
| Particles / billboards (fireflies, rain) | Particle system, `BillboardGeometry`, flipbooks, trails | None built in |
| Shader warm-up behind a loading screen | `Scene.preload()`, `SceneView(warmUp:)`, and `scene.warmUp(views)`. Debug builds log any pipeline build ≥ 8 ms. | Materials compile at load; no explicit pipeline warm-up API |
| Agent skill | **Installed**: 6 skills (idioms, looks, performance, procedural, kit, verification-loop) in `.claude/skills/` | None |
| Banding | No dither in the engine's resolve. Our upscale pass adds ±1 LSB TPDF dither (verified). | Filament has `setDithering` |
| 10-bit / wide-gamut output | Not exposed on Android: Flutter's Android surface is 8-bit, so this applies to both engines. Mitigation is dithering in the final pass. | Same limit (the RGBA8 texture option applies on Apple platforms only) |

## Why flutter_scene

1. **The look depends on depth of field and dynamic resolution.** Tilt-shift DoF that tracks the lantern is how this concept passes for a macro photo. Dynamic internal resolution + TAA + upscale is how it holds 60 fps for 20 minutes in a 4.1 mm phone. Thermion has neither without rebuilding Filament's native libraries from source for arm64 and wasm. That's hours of CPU here and a fork to maintain afterwards.
2. **One GPU context, no external-texture hop.** flutter_scene draws inside Flutter's own Impeller/Vulkan frame. That gives:
   - no extra frame of latency
   - no second swapchain, and nothing to rebuild on a fold
   - frame pacing tied to Flutter's vsync, which matters for the locked 60 Hz on LTPO
3. **Everything the visual roadmap needs already exists.** It has water inputs (scene color, scene depth, planar reflection), particles, SSR, reflection probes, GTAO, height fog, AgX, LUT grading, and warm-up. The web capture path also needs no special server.

## Known risks with the pick, and what I'll do

- **Pre-1.0 API that changes fast.** Pinned to `flutter_scene: 0.24.3` and Flutter 3.50.1. I won't upgrade mid-project unless something blocks us.
- **Web captures use WebGL2; the phone uses Vulkan.** Same shaders, different backend. Captures stand in for the look, not the device. Your `captures/device/` files override them, as you specified.
- **Changing `renderScale` reallocates the swapchain.** The governor will use quantized steps (e.g. 0.60 / 0.65 / 0.70 / 0.75 / 0.80) with hysteresis and a cooldown, changing at most every few seconds. Because TAA re-converges, a step won't be visible. With our own `RenderTexture` + upscale path, a step only resizes the internal target, never the display surface.
- **No GPU timer queries yet.** The engine's adaptive controller measures frame period on the UI thread. The governor will combine that with Android `PowerManager` thermal status and headroom over a platform channel. It steps resolution first, then effects (AO samples → DoF quality → SSR off), never in one jump.
- **The vertex stage can't read engine time.** Animated vertex shaders get time through a material parameter (already done in the spike).
- **Engine- and platform-level work that's the same for either engine** (not tested here, needs the device):
  - display refresh-rate request (`Surface.setFrameRate` / `preferredDisplayModeId`)
  - thermal APIs
  - Flex mode via `androidx.window` `FoldingFeature`
  - the crease and cutout safe areas
  - haptics
  - tilt sensors

## How to check this on your Fold

- `spike/apk/flutter_scene_spike-arm64-release.apk`: install, then fold and unfold while it runs. The overlay shows fps, the current render scale (alternating 0.7/0.85 every 4 s), the viewport size and a resize counter. It passes if the scene keeps rendering through every fold with no black frame or restart, and the resize counter climbs.
- `spike/apk/thermion_spike-arm64-release.apk`: the same scene, for comparison.
- Performance numbers from these APKs are only a sanity check. The spike runs debug-style overlays and no governor.

## Network notes

- Nothing was blocked.
- Maven Central returned **429 Too Many Requests** once during the first Gradle sync; Flutter's automatic retry succeeded.
- `commons.wikimedia.org` answered 429 to an anonymous root probe. I'll send a proper User-Agent and rate-limit when I build the reference set.
