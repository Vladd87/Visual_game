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
| round-3 | water v3 | 2.06 | 2.13 | 2.09 | 1.5 | 0/4 | +0.40. Water 2/10; "glass over gravel", no sky reflection |
| round-4 | water v4 | 1.81 | 2.00 | 1.91 | 1.5 | 0/4 | −0.18 (1st sub-0.3 round). Water 2/10; sky sheen read as a uniform "frosted lavender veil" |

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


## Round 3: water v3

**Scores (1–10)**
- inner: 2.5, 2, 2.5, 2, 1.5, 2, 2, 2 (mean 2.06)
- cover: 2.5, 2, 2.5, 2, 1.5, 2, 2, 2.5 (mean 2.13)

**Water alone:** 2/10.

**Water issues**
1. No sky, lantern or rock reflection and no glitter path: the stream reads as glass over gravel.
2. No foam, wakes or waterlines around obstacles; no visible ripples.
3. Bed: a single-scale pebble pattern; caustics read as smears rather than a network; no depth falloff; a "plastic film" strip along both edges.

**Other giveaways** (later systems): egg rocks with shell slits and fur (M3); featureless blurred banks with a perfectly circular pool (M3/M6); box lantern, square leaves, pin-dot fireflies (M6/M7); milky lifted blacks with p1 ≈ 42/255 (M9).

**A/B:** 0/4 fooled, 99 % confidence on each.

**Verified myself:** the water's sky reflection was effectively absent. The engine IBL specular was gated by the mirror capture's alpha, which appears to be 1 over empty background. Even ungated, a physically weighted dusk sky at the diffuse environment level is only 1–5 % of the lantern-lit bed.

**Changes for round 4**
- The water now computes its own sky reflection from a blurred equirect baked from the same HDRI (`tools/bake/bake_sky.py`, engine IBL off for water). Mirrored objects replace it only where the capture is non-empty.
- The reflected sky is 2.5× the diffuse sky level. This stands in for channel occlusion of the bed's sky light until the lighting milestone.
- A broad 0.5 m undulation layer makes the sky reflect in soft patches.
- Caustics: geometric mean of two layers with a power curve gives crisper filaments.
- Narrower meniscus line (removes the edge "film" strip).


## Round 4: water v4

**Scores (1–10)**
- inner: 2, 2, 2, 1.5, 2, 2, 1.5, 1.5 (mean 1.81)
- cover: 2, 2, 2.5, 2, 2, 2, 1.5, 2 (mean 2.00)

**Water alone:** 2/10.

**Water issues**
1. Still "no surface": a uniform frosted-lavender veil with no sky or bank reflections and no glints.
2. No ripples, flow lines or foam at rocks and lantern.
3. Uniform haze with no depth darkening; refraction smears in shot 8; a single-colour bed.

**Other giveaways** (later systems): egg rocks with clipping and seams; geometric shorelines (the pool is a circle joined by a notch); the lantern is a white box with a star flare; milky grade with p1 ≈ 47–51/255 and mean saturation 0.15.

**A/B:** 0/4 fooled, 99 % confidence on each.

**Reading of the regression:** the reflected-sky boost added haze, not structure. Physically, a 2.5 % Fresnel sky over a clear, lantern-lit shallow bed is swamped. In refs 02, 08 and 11, deep water goes dark and tannin-coloured, and only the margins show the bed; the dark water is what makes glints and sky patches visible.

**Changes for round 5**
- **Deeper channel** (≈28 cm centre, shallow margins) with **tannin absorption** (7, 9, 13 per metre): a dark reflective centre and visible shallows.
- **Rocks** extended down to the deeper bed so none float.
- **Reflected sky broken by a canopy/treeline mask**, so ripples alternate bright sky gaps and dark foliage (refs 06, 11). The boost is reduced to 1.6×.
- **Whiter foam** in the fast sections.
