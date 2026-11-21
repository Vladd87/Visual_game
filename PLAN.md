# LANTERN: plan

This plan covers what LANTERN should look like, how it is built, the order of work, and every decision taken without asking you (logged at the end, with reasons). It is written against `ENGINE.md` (flutter_scene 0.24.3 on Flutter 3.50.1 stable) and the approved `references/`.

---

## 1. Art direction

**The photograph we are faking.** A dusk macro shot of a garden rill in light rain, taken from a footbridge with a long lens wide open. One warm paper lantern drifts through a cold blue-grey world. Everything outside a thin band of focus melts. Refs 02, 11 and 12 are the camera; refs 01, 04 and 13 are the surfaces; refs 03, 07 and 14 are the warm light; ref 15 is the mood.

### Palette

Display-referred targets after AgX. These are checked with a colour picker against captures, never eyeballed.

| Role | Value | From |
|---|---|---|
| Fog / sky base, dusk | `#2A323C` → `#141920`. Darkest scene black never below `#07090B`. | 01, 15 |
| Water body (deep) | olive-brown `#1C1D15`; shallow areas over pebbles `#4A3F2A` | 08, 09, 12 |
| Water reflections | sky slate `#5D6874`; warm glints only near the lantern | 02, 10 |
| Wet stone | warm near-black `#1A1917`, broad sheen `#6E747A` | 01, 04, 13 |
| Dry stone tops | `#4D4B46` | 04 |
| Moss, shade | `#33401E` | 04, 13 |
| Moss, lantern-lit | `#7A8B37` with a fuzzy rim | 11 |
| Lantern paper | core `#FFC27A` (≈2400 K) to edge `#C9692A`; never pure white | 02, 14 |
| Candle flame | `#FFE3A8` core, under 2 % of lantern area | 14 |
| Fireflies | `#D6F05A` dashes, ≤ 3 px at inner-screen native res | 06 |

### Light

- **Sky:** one dusk HDRI from Poly Haven (CC0) at low intensity. It supplies ambient light and the sky seen in water reflections.
  - Candidates, A/B-tested in the lighting system: `qwantani_dusk_2`, `kiara_9_dusk`, `mossy_forest`, `dark_autumn_forest`.
  - The sun is already set, so there's no key sun. A weak cool directional "sky" light gives contact shadows only.
- **Lantern:** the only strong light. A warm point light inside it casts cube-map shadows, with a small radius and fast falloff (ref 14).
- **Fog:** height fog, thicker over the water. Near the lantern it is lit warm by an analytic in-scatter term (ref 03) and goes cold-neutral between sources.
- **Fireflies:** emissive only. At most four nearby ones get tiny unshadowed point lights.

### Lens

- **Camera:** fixed and tilted, 55° pitch, about 2.2 m from the lantern at real-world scale. Vertical FOV is 24° on the inner screen and 28° on the cover screen (≈ 56 mm and 48 mm equivalent).
- **Depth of field:** physical (f-stop, focal length, sensor height), focused on the lantern. About f/2 gives a ≈ 15–20 cm sharp band, which is the tilt-shift miniature look (ref 11).
- **Film:** subtle vignette, fine film grain, no chromatic aberration beyond a hint, and no lens flares.

### Five target adjectives

**hushed · wet · tactile · warm-in-cold · miniature**

### Five things it must never look like

1. **Plastic.** Uniform specular, clean normals, rocks that read as smooth blobs (the spike's look).
2. **A mobile-game glow fest.** Big bloom halos, neon fireflies, saturated magic sparkles.
3. **Crushed OLED black.** Stone, moss and water detail clipped to `#000` where the references still show texture.
4. **Tiled and copy-pasted.** Visible texture repeats, identical rocks, regularly spaced ferns.
5. **A CG water plane.** Mirror-flat, uniform blue, no depth tint, no foam at rocks, rain rings that look stamped on.

---

## 2. Game design (kept small)

- **Scale.** Real-world metres.
  - Lantern: 7 cm paper cube with a candle.
  - Stream: 0.45–0.9 m wide, about 40 m long.
  - Rocks: 4–35 cm. Ferns: 20–45 cm.
- **Run.** 3–5 minutes at 0.15–0.25 m/s of current. There are six sections of about 30–50 s each, each with its own hazards, rain level and fog density:
  1. calm mossy reach (tutorial by doing)
  2. rock garden with foam and eddies
  3. fern tunnel with falling leaves
  4. rain swell and firefly meadow
  5. misty narrows with strong eddies
  6. the still pool (end)
- **The stream.** Generated from a seed as a spline. Its banks and scatter are streamed in 2 m chunks with recycled instances. The same seed gives the same run, which the captures depend on.
- **Flame.** Starts at 1.0. It decays slowly (it would go out at about 4.5 min with no fireflies) and a little faster in heavy rain.
  - **Fireflies:** each one collected adds +0.06.
  - **Collisions:** take 0.04–0.20 depending on impact speed, with a haptic pulse scaled the same way.
  - **Leaves:** one landing on the lantern dims and slows it briefly.
- **Lose:** the flame goes out. A smoke wisp rises, the lantern drifts on in the dark, and a retry prompt appears.
- **Win:** the lantern reaches the still pool. The collected fireflies rise into the sky; their count is the score, with remaining flame and time as tie-breaks.
- **Saved:** the best run, using shared preferences.
- **Controls.**
  - **Drag (default):** a relative nudge from anywhere on screen, so the finger never covers the lantern. Force is clamped and the current does the rest.
  - **Tilt:** device gravity rotated into the active screen's coordinates. This accounts for display rotation and whether you're on the inner screen, cover screen or Flex mode. Tap the calibrate button to re-zero.
- **No characters, no text in the world.** The UI is a thin flame meter and a firefly count in the corners.

---

## 3. Architecture

```
app/                       Flutter project "lantern" (dev.lantern.lantern)
  lib/
    main.dart              boot, immersive mode, lifecycle → pause
    app/                   screens: loading/warm-up, title, run, results, settings
    sim/                   pure Dart, no Flutter imports, unit-tested
      rng.dart             seeded PRNG
      stream_course.dart   spline, sections, width/depth profile
      flow_field.dart      current velocity, eddies (Rankine vortices), rock wakes
      lantern_body.dart    2D rigid body on the water plane, buoyancy bob, spin
      collisions.dart      circle/capsule vs rocks and banks, impulses
      fireflies.dart       spawning and pickup
      leaves.dart          spawning and drift
      run_state.dart       flame, score, win/lose, section timeline
      world.dart           fixed 120 Hz step, interpolation for render
    render/
      scene_root.dart      owns Scene; builds chunks from sim data; instancing pools
      camera_rig.dart      framing per screen profile, crease-aware anchor, smooth reframe
      materials/           .fmat sources: water, wet_stone, moss, paper, fern, leaf, rain
      water.dart           water mesh, flow texture baked from flow_field, foam SDF
      scatter.dart         rocks, moss tufts, ferns, pebbles (InstancedMesh, LOD)
      lantern_fx.dart      flicker light, flame card, paper material params
      fireflies_fx.dart    billboards plus a few small lights
      rain_fx.dart         streak particles, splashes, water ripple normals
      post.dart            EnvironmentSettings per quality tier; DoF focus tracking
      upscale.frag         Catmull-Rom upscale + CAS sharpen + TPDF dither (Flutter shader)
      present.dart         internal-res RenderTexture → upscale painter at native res
      quality_governor.dart  render-scale and effect ladder, hysteresis, thermal input
      warmup.dart          draws every material/pipeline once behind the loading screen
    platform/              Dart side of the channels below
    ui/                    HUD, Flex-mode panel, perf overlay, settings
  android/app/src/main/kotlin/.../
    MainActivity.kt        immersive, configChanges, display-mode request
    DisplayModeHelper.kt   pick a 60 Hz (or 120 Hz) mode for the current display; reapply on display change
    ThermalHelper.kt       PowerManager thermal status listener and getThermalHeadroom()
    PostureHelper.kt       androidx.window WindowInfoTracker → FoldingFeature (hinge bounds, HALF_OPENED, orientation)
    HapticsHelper.kt       VibrationEffect with amplitude by impact
    TiltHelper.kt          rotation-vector sensor plus display rotation; sent as screen-space gravity
  test/                    sim unit tests (determinism, collisions, flame math)
tools/
  capture/                 Playwright harness for the 8 fixed shots × 2 aspects; blank-canvas detector
  critic/                  critic prompt and scoring template
  refs/                    reference fetch tools (done)
captures/round-N/{inner,cover}/   web captures per round
captures/device/                  your phone screenshots and perf logs (these override web captures)
releases/                  APKs
```

### Key mechanisms

- **Render path.**
  1. flutter_scene renders the 3D scene into a `RenderTexture` at internal resolution (inner default 0.70 × native, cover 0.80), with TAA, DoF, bloom and tonemapping.
  2. A Flutter `FragmentShader` upscales it to native resolution (Catmull-Rom + contrast-adaptive sharpen + ±1 LSB TPDF dither).
  3. The UI draws at native resolution on top.
  - Changing the internal resolution only resizes the off-screen target, never the display surface. This was proven in the spike.
- **Fold and unfold.**
  - The activity declares `screenSize|smallestScreenSize|screenLayout|density` config changes, so Android never recreates it and the Flutter GPU context, materials and meshes survive.
  - On a size change the sim keeps running from the same state. `camera_rig` moves the framing to the new profile over about 0.5 s with a critically damped spring. The present step keeps drawing the last completed frame until the new-size target has rendered once, so there is no black frame.
  - **Screen switch = soft pause.** The run is frozen under a minimal "tap to continue" veil while the camera reframes. Background also pauses.
- **Flex mode.** When the FoldingFeature is HALF_OPENED with a horizontal hinge, the game viewport moves to the top half (camera reframed for that aspect) and a minimal panel takes the bottom half: pause/resume, flame, fireflies, time, best. The game keeps running.
- **Crease and cutouts.**
  - The hinge rectangle comes from the FoldingFeature, never a hard-coded centre line. `camera_rig` anchors the lantern in the larger region beside the hinge, at about 32 % of width on the inner screen. The wider bank shows on the other side, which suits the diorama framing.
  - HUD sits in the corners away from the hinge, inside `MediaQuery.viewPadding` and display-cutout insets on both screens.
  - Hazards are spawned relative to the lantern's lane, so the action stays beside the crease rather than on it.
- **Frame pacing.**
  - **60 Hz:** `DisplayModeHelper` sets `preferredDisplayModeId` to a 60 Hz mode on the current display (plus `preferredRefreshRate`), and reapplies it on every fold and display change, so the LTPO panel locks to 60 instead of hunting between 60 and 120.
  - **120 Hz:** an optional Performance toggle requests the 120 Hz mode instead.
- **Thermal governor (High is the game).**
  - **Inputs:** the thermal status listener, `getThermalHeadroom(10 s)` polled every 2 s, and frame timings from `SchedulerBinding.addTimingsCallback` (build and raster).
  - **Ladder:** one notch at a time, with a cooldown of at least 8 s and hysteresis.
    1. **Render scale first.** 0.70 → 0.65 → 0.60 → 0.55 on the inner screen. TAA hides each 7 % step.
    2. **Then effects, one knob per step:** planar reflection 0.40 → 0.30 scale, then GTAO slices, then DoF quality high → medium, then rain particle count −30 %, then shadow map 1024 → 768.
  - **Recovery:** climbs back the same way.
  - **Medium/Low presets:** exist only as manual thermal fallbacks in settings.
- **Shader warm-up.** The loading screen draws every material × geometry pipeline once at tiny scale (`Scene.preload`, `scene.warmUp`, a pass through every `.fmat`) before the title screen. Debug builds log any pipeline build ≥ 8 ms, and that list must be empty mid-run.
- **Perf overlay (triple-tap).**
  - **Shows:** fps (1 s), p95 and max frame time (rolling 10 s, from frame timings and vsync deltas), internal render scale and resolution, quality tier and ladder notch, thermal status and headroom, active screen (inner/cover/flex) and refresh mode.
  - **Export:** a button writes a CSV log to app storage so you can drop it into `captures/device/`.
- **Determinism for captures.**
  - In capture mode (`--dart-define=LANTERN_CAPTURE=true`), URL parameters choose the shot, aspect and seed.
  - The sim is stepped to the shot time at a fixed dt. The view is then held while TAA, auto-exposure and DoF converge (64 frames), and the page sets `window.__lanternReady`.
  - The harness screenshots each shot in a fresh page, and fails if the canvas is blank or flat (pixel-variance check). A blank canvas is a harness bug, not a scene problem.

### Assets (CC0 only; every file logged in ASSETS.md with URL and licence)

- **Poly Haven models:** `rock_moss_set_01/02`, `moss_01`, `fern_02`, `stone_01`, `boulder_01`, `namaqualand_stones_01`
- **Poly Haven textures:** `mossy_rock`, `rock_pitted_mossy`, `river_small_rocks`, `ganges_river_pebbles`, `forest_ground_04`, `brown_mud_rocks_01`, `forest_leaves_02`
- **ambientCG:** `Moss001–004` as fallbacks
- **Formats:** flutter_scene's build hook cooks textures to `.fstex` (block-compressed, transcoded at load to ASTC where the GPU supports it, as Adreno does) with full mip chains. ETC1S KTX2 is used for large colour maps only if APK size forces it. Meshes go into `.fsceneb` at build time.
- **Procedural** (where it beats scans): water normals and flow, caustics, rain, ripples, fog, fireflies, the candle flame, and leaf variation.
- **Audio:** rain and stream ambience is synthesised offline (filtered-noise and droplet models) by a script in `tools/audio/`. It is CC0 by construction and needs no download.

---

## 4. Milestones

Every milestone ends with a commit and push, plus a fresh APK.

| # | Milestone | Done when |
|---|---|---|
| M0 | Engine spike, references | ✅ Approved |
| **M1** | **Playable greybox**, gameplay first. Course, flow field, lantern physics, collisions, fireflies, leaves, flame, win/lose, title and results, best run. Drag and tilt, haptics. Fold/unfold reframe, Flex-mode panel, crease-aware framing, immersive mode, pause. Perf overlay, quality governor skeleton, 60 Hz mode request. Internal-res present with upscaler. Capture harness working (blank-canvas check). Plain lighting. | Debug APK in `releases/`; sim unit tests pass; web build runs start to finish in captures at both aspects; README stub. **I'll stop for your playtest feedback.** |
| M2 | **Water**: flow-mapped normals, refraction and depth tint, Fresnel against the HDRI plus a planar reflection of banks and lantern, foam at rocks and banks, caustics on the bed, lantern glints | critic rounds per §5 |
| M3 | **Stone and moss**: scanned mossy rocks, wet darkening and sheen by height above water, moss sheen and fuzz, pebble bed, bank blending | critic rounds |
| M4 | **Lighting and fog**: HDRI A/B, lantern shadows, contact shadows, GTAO, height fog plus analytic lantern in-scatter | critic rounds |
| M5 | **Rain**: velocity-stretched streaks lit by the lantern, ripple normals on water, splashes on stones, wetness and puddles, per-section intensity | critic rounds |
| M6 | **Vegetation**: instanced ferns, grass and moss tufts with wind (vertex stage), LOD, falling leaves | critic rounds |
| M7 | **Lantern glow and fireflies**: paper diffuse transmission, flame card with flicker, light flicker coupled to flame value, firefly blink dashes, rise at the end | critic rounds |
| M8 | **Post**: DoF tracking and bokeh, TAA tuning, bloom restraint, grain, vignette, upscaler and sharpen tuning | critic rounds |
| M9 | **AMOLED grade**: AgX and LUT with a lifted toe (no crushed blacks), dither audit for banding in fog, sky and water; low- and high-brightness check (captures re-encoded through dim/bright display curves) | critic rounds |
| M10 | **Ship**: audio, settings, signed release APK (debug keystore), README (install, controls, settings, known weaknesses, perf overlay), final captures both aspects, final honest report | your sign-off |

The visual systems are strictly sequential, never in parallel. Each one ends with a release arm64 APK in `releases/` and a capture round.

---

## 5. Builder/critic loop

1. **Capture.** After each system, `tools/capture/capture.js` builds the web release and takes **8 fixed shots** at **inner 2256×2504** and **cover 1080×2520**. The cover resolution is my assumption; I'll correct it from your device screenshots. Both are rendered at half size (1128×1252 and 540×1260) because SwiftShader is slow. Quality features stay on; resolution goes down instead.
   - Output goes to `captures/round-N/{inner,cover}/`.
   - Fixed seed, fixed times, each shot in a fresh page, temporal effects settled.
   - **The shots:**
     1. opening reach, wide
     2. lantern beside foaming rocks
     3. firefly cluster close pass
     4. heavy rain on open water
     5. moss bank and ferns
     6. collision moment (flame dipped)
     7. misty narrows (lantern in-scatter)
     8. end pool with fireflies rising
2. **Critique.** A **fresh critic subagent** gets only a copied folder containing that round's captures, `references/` and `captures/device/`. It gets no repo path, no code and none of my reasoning, and is told not to look elsewhere. It:
   - scores realism 1–10 per shot per aspect
   - ranks the top 5 CG giveaways
   - runs a blind A/B (one capture plus one reference, randomised and unlabelled: which is real?)
3. **Log.** I fix the top issues, recapture and re-critique, and log every round in `CRITIC_LOG.md` (scores table, mean, giveaways, A/B outcome).
4. **Stop rules.**
   - A system stops after two consecutive rounds gaining < 0.3 mean, or after 8 rounds.
   - Everything stops when every shot scores ≥ 7.5, or when you say so.
   - Realism is never bought with a cost the phone can't hold for 20 minutes: if a fix is expensive, I find the cheaper trick and note it.
   - Your `captures/device/` screenshots and perf readings override web captures whenever they disagree.

---

## 6. Budgets (planning numbers, to be corrected by your device readings)

| | Inner (2504×2256) | Cover (≈1080×2520) |
|---|---|---|
| Internal render scale (High) | 0.70 (≈1753×1579, 2.8 MP) | 0.80 (≈864×2016, 1.7 MP) |
| Target GPU frame | ≤ 11 ms at 60 Hz (headroom for 20 min warm-room sessions) | ≤ 9 ms |
| Draw calls | < 150 (instancing everywhere) | same |
| Shadow casters | lantern cube shadow at 512²/face; static banks cached (`shadowStatic`) | same |
| APK | ≤ 95 MB target (hard cap 200 MB) | |

The APK target is 95 MB so it can live in git; GitHub rejects single files over 100 MB.

---

## 7. Decisions log (made without asking; tell me to change any of them)

| Decision | Why |
|---|---|
| flutter_scene 0.24.3 / Flutter 3.50.1, pinned | Passed every must-have in the spike; pre-1.0 API, so no mid-project upgrades unless blocked. |
| Real-world metric macro scale | Physical DoF values (f-stop, focal length, sensor) then give a believable tilt-shift band without hand-tuned fake blur. |
| Procedural seeded stream, streamed in chunks | A 40 m course at macro scale doesn't fit as one authored mesh; seeds make captures deterministic. |
| Own upscale pass (RenderTexture → Flutter shader) | The engine composite is bilinear on Android; ours is Catmull-Rom + sharpen + dither, and resizing the internal target never touches the display surface. |
| Dither instead of 10-bit | Flutter's Android surface is 8-bit and offers no 10-bit/wide-gamut option. ±1 LSB TPDF dither in the final pass prevents banding in fog, sky and water. |
| 60 Hz via `preferredDisplayModeId`, reapplied on display change | LTPO judder comes from refresh hunting; a fixed mode request per display is the reliable Android lever. |
| Screen switch = soft pause with reframe | You asked for both "continues seamlessly" and "pause on screen switch". Run state is kept, the camera reframes smoothly behind a pause veil, one tap resumes. Flex mode keeps playing. |
| Lantern anchored beside the hinge, from FoldingFeature bounds | Keeps gameplay off the inner crease on any orientation, and turns the extra width into the diorama bank. |
| Drag is the default control, tilt optional | Drag is precise on both screens; tilt is offered and posture/rotation-aware. |
| Synthesised CC0 ambience audio | No account or API key needed (Freesound requires one), so there is no licence ambiguity. |
| Game lives in `app/`; spike stays in `spike/` | Keeps the repo root readable. |
| minSdk 29, targetSdk 36, arm64-v8a only, release signed with the debug keystore | As specified; arm64-only keeps the APK small. |
| APKs committed to `releases/`, one current file per kind, overwritten each milestone | You asked for APKs in the repo. History grows by roughly one APK per milestone; I'll say if that becomes a problem. |
| Critic gets a copied folder, not the repo | The closest practical way to guarantee "no access to code or reasoning". |
| CC BY-NC reference (ref12) kept | References never ship, so non-commercial terms don't bind the app. |

## 8. Risks I'm watching

- **Web vs device.** Captures render through WebGL2/SwiftShader; the phone runs Vulkan. Your device captures win.
- **Planar reflection cost.** It's an extra scene render. If it's too expensive I fall back to SSR plus the HDRI with lantern glints from the point light.
- **Point-light cube shadows** on many casters. Mitigated with static-cached casters and caster channel masks.
- **flutter_scene web/native differences** in custom `.fmat` shaders. Both backends are built and checked every milestone.
- **Thermal behaviour** of a 4.1 mm phone can't be simulated here. The governor's thresholds will be tuned from your perf CSVs.
