# LANTERN

A small Flutter game for the Samsung Galaxy Z Fold8 Ultra. You guide a paper lantern down a stream at dusk; the ambition is that it looks like a photograph.

> **Status: Milestone 8 (everything through the lantern and fireflies, plus the camera look).** Gameplay, fold/unfold, Flex mode and the platform layer are in (M1). These systems went through the blind critic loop (`CRITIC_LOG.md`):
> - M2: the water
> - M3: scanned rocks and textured banks
> - M4: the blue-hour lighting with an amber lantern key
> - M5: light rain on the water
> - M6: ferns, sorrel and grass on wet-moss banks
> - M7: a paper toro nagashi lantern with its reflection, soft fireflies and leaf-shaped leaves
> - M8: a camera's signature (depth of field on the lantern, a vignette, phone-like sensor noise with shadow noise reduction, firefly motion streaks)
>
> The AMOLED grade and audio come next (see `PLAN.md` §4).

## Install

**Release build (recommended).** `releases/lantern-m8-release.apk`, about 35 MB ([direct download](https://github.com/Vladd87/Visual_game/raw/ccr-32d0ba79-c0iehd/releases/lantern-m8-release.apk)); it installs as "Lantern m8". Copy it to the phone and open it (allow installs from your file manager if asked), or run `adb install -r releases/lantern-m8-release.apk`. It opens on a small test menu (device bring-up): **Play** starts the game; **Auto test** runs the on-device diagnostics and **Copy** puts their report on the clipboard. Earlier milestone builds (`lantern-m1-…`, `m2`, `m4`, `m5`, `m6`, `m7.2`) stay in `releases/` for comparison. From m7.2 on, each build installs as its own app ("Lantern m7.2", package `dev.lantern.lantern.m7_2`), so several versions can sit side by side on the phone; older builds share the plain "Lantern" and replace each other.

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
| `[ export perf CSV ]` | Writes a once-per-second log to `Android/data/dev.lantern.lantern/files/lantern_perf_<time>.csv`. Copy it into `captures/device/`. |

## Repository

| Path | What |
|---|---|
| `app/` | The Flutter game (flutter_scene 0.24.3, Flutter 3.50.1 stable) |
| `app/lib/sim/` | Deterministic simulation (unit-tested: `cd app && flutter test`) |
| `app/android/.../kotlin/` | Display-mode lock, thermal, haptics, tilt |
| `tools/capture/` | Playwright harness: `node tools/capture/capture.js captures/<round>` (8 shots × inner/cover), and `smoke.js` for a flow test |
| `captures/` | Web captures per round; `captures/device/` is for your phone screenshots and perf CSVs |
| `references/` | Real reference photos for the critic (never shipped) |
| `ENGINE.md`, `PLAN.md` | Engine choice; plan and decisions log |

## Building

```sh
cd app
flutter build apk --release --target-platform android-arm64   # signed with the debug keystore
rm -rf build/app && flutter build apk --debug --target-platform android-arm64
flutter build web --release                                    # used by the capture harness
flutter test                                                   # simulation tests
```

Clear `build/app` before a debug APK build. With Flutter 3.50 on Gradle 9.5, Gradle's strict task validation trips on stale debug outputs inside the project directory (`compileFlutterBuildDebug`). A clean Android output dir avoids it. Release builds aren't affected.

## Known weaknesses (M8)

Blind critics still score every shot as clearly CG: about 4.0–4.6 out of 10 on recent panels, against a target of 7.5. In their order:
- **The banks** show identical grass tufts at even spacing over a flat, tiled ground, dry and matte (M6).
- **The water** does not read as rained on: few rings, no glints, no sky sheen, and the lantern's reflection is an intact copy (M2, M5, M7).
- **The lantern's light** ends in hard-edged crescents on the bank crests (M4, M7).
- **The tone** sits in a compressed, murky band, with no blue-hour colour (M9 grade).

Not yet measured on the phone: frame pacing over a 20-minute run, thermal stepping, and tilt on each screen. Those need your playtest; the triple-tap perf overlay records them. The test menu and bring-up materials are scaffolding and go before the final release. No audio yet (M10).
