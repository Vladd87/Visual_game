# LANTERN

A small Flutter game for the Samsung Galaxy Z Fold8 Ultra. You guide a paper lantern down a stream at dusk; the ambition is that it looks like a photograph.

> **Status: Milestone 10, shipped.** Every system of the plan (`PLAN.md` §4) is built and went through the blind critic loop (`CRITIC_LOG.md`, 39 rounds):
> - M1: gameplay, fold/unfold, Flex mode and the platform layer
> - M2: the water
> - M3: scanned rocks and textured banks
> - M4: the blue-hour lighting with an amber lantern key
> - M5: light rain on the water
> - M6: ferns, sorrel and grass on wet-moss banks
> - M7: a paper toro nagashi lantern with its reflection, soft fireflies and leaf-shaped leaves
> - M8: a camera's signature (depth of field on the lantern, a vignette, phone-like sensor noise with shadow noise reduction, firefly motion streaks)
> - M9: the grade (a steep AgX curve with true neutral blacks, a deep amber pool, and water carrying the dusk sky)
> - M10: sound, the final settings and the release build
>
> **The realism target was not met:** critics score it about 4.5 out of 10 against a target of 7.5. `FINAL_REPORT.md` explains what was built, what still gives it away and what would raise it next.

## Install

**Final release (recommended).** `releases/lantern-final-release.apk`, about 40 MB ([direct download](https://github.com/Vladd87/Visual_game/raw/ccr-32d0ba79-c0iehd/releases/lantern-final-release.apk)). Copy it to the phone and open it (allow installs from your file manager if asked), or run `adb install -r releases/lantern-final-release.apk`. It installs as plain **"Lantern"** (package `dev.lantern.lantern`) and opens straight into the game.

**Milestone builds.** Every earlier build stays in `releases/` for comparison. From m7.2 on, each installs as its own app ("Lantern m7.2", package `dev.lantern.lantern.m7_2`), so several can sit side by side on the phone. They open on a small test menu (device bring-up): **Play** starts the game; **Auto test** runs the on-device diagnostics and **Copy** puts their report on the clipboard. Builds before m7.2 install as plain "Lantern", the same app as the final release, so installing one replaces the other. `lantern-m10a` is the test build of the sound.

**Debug build.** It's 110 MB, over GitHub's 100 MB file limit, so it's split in two. It's slower (JIT plus Vulkan validation) and useful for logs, not for judging smoothness. Reassemble it first:

```sh
cat releases/lantern-m1-debug.apk.part-* > lantern-m1-debug.apk
sha256sum -c <(grep debug releases/SHA256SUMS | sed 's/ (reassembled)//')   # optional check
adb install -r lantern-m1-debug.apk
```

Both builds are arm64-only, need Android 10 (API 29) or newer, and are signed with the Android debug keystore. Checksums are in `releases/SHA256SUMS`.

## How to play

- The current carries the lantern downstream; the stream flows from the top of the screen to the bottom.
- **Fireflies** feed the flame (+6 % each).
- **Rocks and banks** dim it when you hit them, more at speed. You'll feel a light haptic pulse.
- **Falling leaves** can land on the lantern: it dims and slows for a moment.
- The flame also burns down slowly on its own, a little faster in heavy rain.
- **Win:** reach the still pool at the end. Your fireflies rise into the sky.
- **Lose:** the flame goes out.
- A run lasts about 3–4 minutes.

### Controls

- **Drag (default):** touch anywhere and drag in the direction you want to nudge the lantern. The further you drag, the stronger the nudge (it caps out). Your finger never needs to cover the lantern.
- **Tilt:** tilt the phone toward where you want to go. The neutral pose is taken when a run starts or resumes, or when you change screen or posture. Use "recalibrate tilt" in settings anytime.
- **Pause:** the pause icon (top right). The game also pauses on its own when the app goes to the background or you switch screens.

### Foldable behaviour

| Situation | What happens |
|---|---|
| Cover screen | Tight portrait framing on the lantern |
| Inner screen | Wider diorama framing. The lantern sits beside the crease, never on it, and the HUD stays in the corners. |
| Fold/unfold mid-run | The run is kept and the camera reframes smoothly (no reload, no black frame). The game soft-pauses so you can re-grip: tap or CONTINUE. |
| Flex mode (half-folded) | The game plays in the top half; the bottom half shows flame, fireflies, time, best and pause. |

## Settings

Settings are on the title card and the pause card:
- **Control:** drag / tilt
- **Haptics:** on / off
- **Quality:** high / medium / low. High is the game; medium and low are only thermal fallbacks.
- **Sound:** on / low / off. Light rain and the stream's burble loop underneath; short cues play for a firefly caught, a knock on a rock or bank, a leaf landing on the lantern, and reaching the pool. Sound pauses when the app goes to the background.
- **Refresh:** 60 Hz (default, locked) / 120 Hz (Performance)

Your best run is saved on the device.

## Perf overlay

**Triple-tap** anywhere on the game to toggle it.

| Line | Meaning |
|---|---|
| `fps` | Frames in the last second (and the target rate) |
| `frame p95 / max` | 95th-percentile and worst frame interval over the last 10 s. At 60 Hz, p95 should stay ≤ 16.7 ms and max shouldn't spike. |
| `build / raster` | Last frame's UI-thread and raster-thread time (Flutter `FrameTiming`) |
| `scale / notch` | Internal 3D render scale and how many governor steps below the screen's default it is (0 = full High quality) |
| `thermal / headroom` | Android thermal status (none, light, moderate, severe…) and `getThermalHeadroom(10 s)`, where 1.0 means throttling |
| `screen` | Active profile (cover, inner, flex, wide), display mode and refresh rate |
| `[ export perf CSV ]` | Writes a once-per-second log to `Android/data/dev.lantern.lantern/files/lantern_perf_<time>.csv` (for a milestone build, the folder carries its tag, such as `dev.lantern.lantern.m9`). Copy it into `captures/device/`. |

## Repository

| Path | What |
|---|---|
| `app/` | The Flutter game (flutter_scene 0.24.3, Flutter 3.50.1 stable) |
| `app/lib/sim/` | Deterministic simulation (unit-tested: `cd app && flutter test`) |
| `app/android/.../kotlin/` | Display-mode lock, thermal, haptics, tilt |
| `tools/capture/` | Playwright harness: `node tools/capture/capture.js captures/<round>` (8 shots × inner/cover), and `smoke.js` for a flow test |
| `tools/build_apk.sh` | Builds an APK into `releases/`: `tools/build_apk.sh m11` for a tagged test build, `LANTERN_FINAL=1 tools/build_apk.sh final` for the plain release |
| `tools/audio/` | `synth_audio.py` generates every sound in `app/assets/audio/` |
| `captures/` | Web captures per round, and `captures/final/` from the shipping code; `captures/device/` is for your phone screenshots and perf CSVs |
| `references/` | Real reference photos for the critic (never shipped) |
| `ENGINE.md`, `PLAN.md` | Engine choice; plan and decisions log |
| `CRITIC_LOG.md`, `FINAL_REPORT.md` | Every critic round; the final honest report |
| `ASSETS.md` | Every asset and its CC0 source |

## Building

```sh
cd app
flutter build apk --release --target-platform android-arm64   # signed with the debug keystore
rm -rf build/app && flutter build apk --debug --target-platform android-arm64
flutter build web --release                                    # used by the capture harness
flutter test                                                   # simulation tests
```

Clear `build/app` before a debug APK build. With Flutter 3.50 on Gradle 9.5, Gradle's strict task validation trips on stale debug outputs inside the project directory (`compileFlutterBuildDebug`). A clean Android output dir avoids it. Release builds aren't affected.

## Known weaknesses

Blind critics still score every shot as clearly CG: about 4.4–4.6 out of 10 on the final panels, against a target of 7.5. In the separate A/B test they picked the real photo in every pair of all 39 rounds. In their order:
- **The banks** show identical grass tufts at even spacing over a flat, tiled ground, dry and matte (M6).
- **The water** does not read as rained on: few rings, no glitter path from the lantern, soft reflections and a milky sky sheen (M2, M5, M7).
- **The lantern's light** ends in hard-edged crescents on the bank crests, and banks a metre away are lit too brightly for a candle (M4, M7).
- **Dry materials:** no glints on wet stone, leaves or grass, so the brightest part of the range stays empty. A grade can't fill it without lifting the whole frame (M9).
- **The lantern** still reads as a clean glowing box at this camera distance (M7).

`FINAL_REPORT.md` estimates what each fix would gain and cost.

**Not yet confirmed on the phone:** the lantern paper's brush characters (fixed in m7.2) and the sound.

**Not measured,** as agreed: frame pacing over a 20-minute run, thermal stepping, 120 Hz behaviour, and tilt on each screen. Those need your playtest; the triple-tap perf overlay records them.

The final release is signed with the Android debug keystore, as planned. A store release needs a real signing key.
