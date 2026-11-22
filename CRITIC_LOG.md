# Critic log

Every round follows the same steps (PLAN.md §5):
1. Capture the 8 fixed shots at both aspects: inner 2256×2504 and cover 1080×2520, rendered at half size.
2. Build a blind packet (`tools/critic/make_packet.py`): images only, re-encoded identically, references renamed, A/B pairs randomised. The answer key stays outside the packet.
3. A **fresh** critic subagent judges the packet with the prompt in `tools/critic/critic_prompt.md`. It gets no code and none of my reasoning.

**Scores** are realism, 1–10. The target is ≥ 7.5 for every shot.

**Stop rules:**
- A system stops after two consecutive rounds that each gain less than 0.3 in mean score, or after 8 rounds.
- Everything stops when every shot scores ≥ 7.5.

| Round | System | Inner mean | Cover mean | Overall | Min | A/B fooled | Notes |
|---|---|---|---|---|---|---|---|
| m1-greybox | (baseline, not critiqued) | | | | | | Plain-lighting greybox |
| round-1 | water v1 | 1.06 | 1.13 | 1.09 | 1 | 0/4 (see note) | Water read as opaque matte brown |
| round-2 | water v2 | 1.56 | 1.81 | 1.69 | 1 | 0/4 | +0.60. Water alone 1.5/10: pebble bed, planar reflection, but the surface still invisible |

## Round 1: water v1

**Scores (1–10)**
- inner: 1, 1, 1.5, 1, 1, 1, 1, 1
- cover: 1.5, 1, 1.5, 1, 1, 1, 1, 1

**Top 5 giveaways, worst first**
1. **Opaque matte water.** No mirrored lantern, banks or sky; no glitter path; the bed isn't visible; a scratchy "brushed metal" overlay; the lantern light reads as a spotlight on a matte floor. Estimated +1.5 to +2.
2. **Stones.** Untextured ellipsoids with no waterline, no wet darkening, no moss, interpenetrating; hairy foam fringe. Estimated +1 to +1.5.
3. **Banks.** A featureless blurred mint-green void. Estimated +1 inner, +0.5 cover.
4. **Lantern.** A pure-white unshaded emissive box. Estimated +0.5 to +1.
5. **Hard artefacts.** Black polygonal shadow wedges, a sawtooth rim and black bar at the pool, square tan leaf quads, firefly dots that look pasted on stones. Each one caps its shot at 1.

Also flagged: no photographic camera response. Blacks are lifted (p1 luma 23–44 vs < 20 in the references), highlights are capped, there's no grain, and edge detail is low.

**A/B:** the critic picked the real photo in 4/4 pairs at 100 % confidence. That result is invalid because the packet was flawed:
- the real halves were crops of photos also present in `references/`
- a source-JPEG comment leaked through re-encoding

Fixed in `make_packet.py`: the A/B photos are now held out of `references/`, and pixels are copied into fresh images with no metadata.

**Plan for round 2** (water system; fixing artefacts that cap every shot):
- pebble bed under the water, so refraction and caustics have something to show
- planar reflection (lantern, rocks, banks) plus a dusk-sky HDRI for sky reflection
- foam reshaped into streaks trailing downstream
- soft lantern shadows
- ground extended past the pool
- smoother pool rim

Stones, banks, lantern and grade belong to later systems (M3, M6, M7, M9), but their artefacts are noted here.


## Round 2: water v2

**Scores (1–10)**
- inner: 1.5, 1.5, 2, 1.5, 1.5, 1.5, 1, 2 (mean 1.56)
- cover: 2, 1.5, 2.5, 2, 1.5, 1.5, 1, 2.5 (mean 1.81)

**Water alone:** 1.5/10.

**Top 5 giveaways, worst first**
1. Rocks are untextured eggs. Some looked like open shells with gravel inside (this was a water bug, see below).
2. No visible water surface: no sky or bank reflection, no lantern glitter path; the light pool reads like "a lamp over a driveway".
3. The banks are a featureless blur with a fur fringe.
4. The lantern is a flat white card.
5. Placeholder effects: rectangle leaves, fur-like foam, fireflies with dark halos, a smeared bottom edge.

Also flagged:
- Lifted blacks (p1 ≈ 40 vs 0–14 in the references) and compressed highlights.
- Water issues in detail:
  - no reflective surface
  - no motion cues (no ripples, flow lines, wobble or caustics; foam reads as fur)
  - the bed has no depth or variety

**A/B:** the critic picked the real photo in 4/4 pairs at 99 %. Each render crop contained a placeholder (egg rocks, leaf rectangles).

**Verified myself before fixing**
- **"Open shell" rocks** were a water bug, not geometry. I had exaggerated the refraction reach ×2.5, which also overshot the flat (apparent-depth) bend, so lookups behind a submerged rock landed on gravel. A no-water capture showed intact rocks.
  - Fix: physical reach, with only the ripple-induced part amplified, plus a depth-discontinuity guard so refraction never samples across an object's edge.
- **Smeared bottom edge** is real but mild: the last ~8 rows, from the bicubic upscale clamping at the border. Logged for M8 (post).

**Changes for round 3**
- the refraction fix above
- drifting foam flecks and bubbles carried by the current, denser in wakes (still-frame motion cue)
- stronger absorption and a cooler murk veil (depth cue)
- sky sheen at F0 0.04 (a deliberate mild cheat)
- a meniscus highlight at waterlines
- big cobbles and silt flats in the bed
- softer, greyer, partly transparent foam instead of fur
