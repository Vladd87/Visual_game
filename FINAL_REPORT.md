# LANTERN: final report

LANTERN is a short Flutter game for Android built around one image: a paper lantern floating down a mossy stream at dusk, in light rain, seen from a fixed camera tilted 55°. Fireflies keep its flame alive, collisions dim it, and a run lasts 3–5 minutes. The target device is the Galaxy Z Fold8 Ultra. The game handles fold and unfold, Flex mode, dynamic resolution, a 60 fps lock and thermal stepping.

This report covers what was built, how close it got to looking like a photograph, and what is still missing. The detail behind every number is in `CRITIC_LOG.md` (39 critic rounds) and `PLAN.md` (every decision and why it was made).

## The verdict

**The realism target was not met.** The target was 7.5 out of 10 on every shot. Blind critic panels now score the final look at about **4.4–4.6** out of 10, which their rubric calls "clearly CG but with photographic elements". In the separate blind A/B test, critics picked the real photograph in **every pair of every round**: 0 fooled out of 4, in all 39 rounds.

The game itself is complete:
- gameplay, fold and Flex handling, the performance governor, settings, sound, and a signed release APK
- all ten systems of the plan were built and judged in order

## What each system gained

Each round, two fresh critics compared the new build with the best so far, side by side, with the order flipped between them, and a separate critic ran the A/B test. A round was kept only if it gained. A system stopped after two rounds in a row that each gained less than +0.3.

| Milestone | Rounds | Kept gain over the previous milestone | Where it stopped |
|---|---|---|---|
| M2 water | 1–5 | absolute about 1.1 → 2.1 (single critics then) | stop rule |
| M3 stone and moss | 6–9 | +1.25 (rounds 6, 7) | stop rule |
| M4 lighting and fog | 10–17 | +2.5 (6 kept rounds) | 8-round limit and stop rule |
| M5 rain | 18–21 | +0.40 | stop rule |
| M6 vegetation | 22–26 | +0.95 | stop rule |
| M7 lantern and fireflies | 27–30 | +1.50 | stop rule |
| M8 camera look | 31–35 | +0.92 | stop rule |
| M9 grade | 36–39 | +0.58 | stop rule |
| M10 ship | – | sound, settings, release build | – |

Paired gains do not add up to an absolute score.
- **The sum overstates:** the kept gains since round 6 add up to about +8, but the absolute panel score moved only from about 2.7 to about 4.5.
- **Why:** each pair of critics judges one change against the current best, on its own calibration. That is why the loop compares paired differences, and why those differences do not compound.
- **The absolute trend:** about 1 out of 10 at round 1, about 3 by M3, about 4 by M6, and about 4.5 at the end. This is the honest measure of progress.

## What still gives it away

These are ranked by how often the critics named them, across the last ten rounds:

1. **The banks.** The same grass tuft repeats at even spacing over a flat, tiled ground, with no wet sheen. This was the top or second giveaway in almost every round since M6.
2. **The water.** It does not read as rained on:
   - only a few large rain rings
   - no glitter path from the lantern
   - reflections are soft blobs rather than crisp, ripple-broken shapes
   - the sky sheen is milky
3. **The lantern's light.**
   - It ends in hard-edged crescents on the bank crests.
   - Banks a metre away are lit too brightly for a candle.
4. **Dry materials.** No glints on wet stone, leaves or grass. That leaves the brightest part of the tonal range empty, and the grade cannot fill it without lifting the whole frame.
5. **The lantern itself** still reads as a clean, glowing box at this camera distance, despite its paper, brush characters and reflection.

Several of these belong to systems that had already stopped. The stop rule kept the loop moving forward but never sent it back. Rounds 29–30, 34–35 and 39 also showed that tuning on its own had reached its limit: the remaining problems need new content, not parameter changes.

## What would raise the score next

These are my estimates, ranked by expected gain per unit of work:

1. **Wet materials** (about +0.5–1): specular sheen on stone and grass, and droplet glints near the lantern. This would also fill the empty highlights the grade critics asked for.
2. **A water rework** (about +0.5–1):
   - dense small rain dimples
   - a glitter path broken up by ripples
   - crisp reflections of the bank silhouettes
   - a darker, glassier sheen
3. **Bank ground cover** (about +0.5–1 on the inner screen):
   - several grass meshes instead of one
   - moss cushions with relief
   - litter, and a continuous rather than tiled ground
4. **A soft area light for the lantern** (about +0.5) in place of the point light, removing the hard crescents.

Each is a bigger job than a tuning round, roughly 1–3 days, plus critic rounds. Even critics who listed all of these expected a ceiling of about 6.5–7, not 7.5. The fixed high camera and the missing atmosphere (visible rain, mist) limit what this scene can reach.

## Running on the phone

I could not run the phone myself, so everything there depended on your screenshots and on the on-device auto test. Problems you surfaced and that are now fixed:

| Problem | Cause | Fix |
|---|---|---|
| Black screen after loading (test builds 3–9) | layout: the page Stack was 0 × 0 | `StackFit.expand` plus a pre-build title check |
| Water missing | the custom-ambient shader variant fails to build on the phone | water keeps environment lighting |
| Crash at launch (M3) | the ground shader bound more samplers than Android guarantees | textures packed; the capture harness now fails anything over 16 samplers |
| Pebble bed collapsed into a lattice | 16-bit shader precision | world positions and ids declared `highp` |
| Water drawn over the bank grass | a depth-guard issue | the water discards behind nearer geometry |
| Lantern paper looked inside-out, with no characters | its hash collapsed at 16-bit precision | a precision-safe hash (m7.2) |
| White specks over the water at full resolution | rain-splash glints far from the lantern | glints dimmed |

**Not yet confirmed on the phone:**
- the m7.2 paper fix (characters and paper fibre on the lantern)
- sound (m10a and the final build)

**Not measured at all, as you asked:**
- frame pacing over a 20-minute run
- thermal stepping
- 120 Hz behaviour

The perf overlay records all three; triple-tap to open it.

## Assets and licences

Everything is CC0 or self-made, and logged in `ASSETS.md`:
- **Poly Haven:** the HDRI, rock scans, fern and sorrel models, textures
- **ambientCG:** ground surfaces
- **Generated in code:** the water normals, the lantern paper, the leaves, the fireflies' texture, and all sound (`tools/audio/synth_audio.py`)

Reference photos are used only as the critics' bar, with sources in `references/SOURCES.md`; they are not shipped.

## Builds

Every milestone build is in `releases/`, with checksums in `SHA256SUMS`. From m7.2 on, each build installs as its own app ("Lantern m8", "Lantern m9" and so on), so builds can be compared side by side. The final release installs as plain **"Lantern"** and opens straight into the game, without the bring-up test menu. It is signed with the debug keystore, as planned. A store release needs a real signing key.
