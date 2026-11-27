# Critic log

Every round follows the same steps (PLAN.md §5):
1. Capture the 8 fixed shots at both aspects: inner 2256×2504 and cover 1080×2520, rendered at half size.
2. Build a blind packet (`tools/critic/make_packet.py`): images only, re-encoded identically, references renamed, A/B pairs randomised. The answer key stays outside the packet.
3. A **fresh** critic subagent judges the packet with the prompt in `tools/critic/critic_prompt.md`. It gets no code and none of my reasoning.

**Scores** are realism, 1–10. The target is ≥ 7.5 for every shot.

**Stop rules:**
- A system stops after two consecutive rounds that each gain less than 0.3 in mean score, or after 8 rounds.
- Everything stops when every shot scores ≥ 7.5.

**Paired panel (from round 9, at your request).** Rounds 1–8 used one fresh critic each. Its own calibration offset made round-to-round changes noisy: in round 8, shots the changes never touched also dropped 0.5. From round 9:
- **Two fresh critics** score each round. Each gets its own packet holding the round under review **and the current best round of the same system**, as sets X and Y in an independent random order. They score both side by side; only one also runs the A/B test. Prompt: `tools/critic/critic_prompt_paired.md`.
- **Gain** = the median over critics of (new − best). Each critic's offset cancels in its own difference. **Absolute score** = the mean of the critics' scores for the new round.
- **Ratchet.** The new version becomes the best only if its gain is above zero. Otherwise the code goes back to the best version (clear bug fixes are kept) and the next attempt starts from there. The stop rule counts gains over the best: two consecutive rounds under +0.3 stop the system, at its best version.
- Aggregation: `tools/critic/panel_score.py`.
- **A/B, from round 10.** Until now the render half of each pair was a crop of a capture the same critic had just reviewed, so critics matched it rather than judged it (they said so). The pairs now go to a **separate fresh critic that sees only the 4 shuffled pairs**: no captures and no references (`tools/critic/critic_prompt_ab.md`, packet `<packet>_ab`). The scoring critics no longer get the pairs.

| Round | System | Inner mean | Cover mean | Overall | Min | A/B fooled | Notes |
|---|---|---|---|---|---|---|---|
| m1-greybox | (baseline, not critiqued) | | | | | | Plain-lighting greybox |
| round-1 | water v1 | 1.06 | 1.13 | 1.09 | 1 | 0/4 (see note) | Water read as opaque matte brown |
| round-2 | water v2 | 1.56 | 1.81 | 1.69 | 1 | 0/4 | +0.60. Water alone 1.5/10: pebble bed, planar reflection, but the surface still invisible |
| round-3 | water v3 | 2.06 | 2.13 | 2.09 | 1.5 | 0/4 | +0.40. Water 2/10; "glass over gravel", no sky reflection |
| round-4 | water v4 | 1.81 | 2.00 | 1.91 | 1.5 | 0/4 | −0.18 (1st sub-0.3 round). Water 2/10; sky sheen read as a uniform "frosted lavender veil" |
| round-5 | water v5 | 1.81 | 1.81 | 1.81 | 1.5 | 0/4 | −0.10 (2nd sub-0.3 round in a row → **water stops**). Water 3/10; depth and lantern spill work, the reflection is now too weak |
| round-6 | stone/moss v1 | 2.75 | 2.75 | 2.75 | 2 | 0/4 | **+0.94**. Stone/ground 3/10: scanned rocks read as rock; banks "camouflage", rocks not wet, no moss caps |
| round-7 | stone/moss v2 | 3.13 | 3.00 | 3.06 | 2 | 0/4 | +0.31 (continue). Stone 3.5/10: moss texture on every rock face, soft dark contact halos, uniform dirt lip |
| round-8 | stone/moss v3 | 2.50 | 2.44 | 2.47 | 2 | 0/4 | −0.59 (1st sub-0.3 round for M3). Stone 3/10: projected moss caps read as "lawn on rocks", stretched rock texels, blurred black bank edge |
| round-9 | stone/moss v4 (panel) | 3.22 | 3.03 | 3.12 | 2.5 | 0/4 | Paired panel vs round 7: **−0.56** (critics −0.56 / −0.56). v4 rejected; **M3 stops at v2** |
| round-10 | lighting/fog v1 (panel) | 3.69 | 3.91 | 3.80 | 3.5 | 0/4 (A/B-only critic) | Panel vs M3 final: **+0.83** (critics +0.91 / +0.75). New best; lighting alone 4.5 vs 3 |
| round-11 | lighting/fog v2 (panel) | 3.25 | 3.38 | 3.31 | 3.0 | 0/4 (A/B-only critic) | Panel vs round 10: **+0.38** (critics +0.38 / +0.38). New best; lighting alone 4.25 vs 3.75 |
| round-12 | lighting/fog v3 (panel) | 3.22 | 3.41 | 3.31 | 3.0 | 0/4 (A/B-only critic) | Panel vs round 11: **+0.45** (critics +0.41 / +0.50). New best; lighting alone 3.75 vs 3.25 |
| round-13 | lighting/fog v4 (panel) | 3.56 | 3.56 | 3.56 | 3.0 | 0/4 (A/B-only critic) | Panel vs round 12: **−0.11** (critics +0.38 / −0.59). Rejected; round 12 stays the best. 1st sub-0.3 round in M4 |
| round-14 | lighting/fog v5 (panel) | 3.25 | 3.33 | 3.29 | 2.75 | 0/4 (A/B-only critic) | Panel vs round 12: **+0.44** (critics +0.38 / +0.50). New best; lighting alone 3.5 vs 3.0 (both critics). Resets the sub-0.3 count |
| round-15 | lighting/fog v6 (panel) | 3.44 | 3.31 | 3.38 | 2.75 | 0/4 (A/B-only critic) | Panel vs round 14: **+0.36** (critics +0.22 / +0.50). New best; lighting alone 4.0 vs 3.5 (both critics) |
| round-16 | lighting/fog v7 (panel) | 3.41 | 3.44 | 3.42 | 3.0 | 0/4 (A/B-only critic) | Panel vs round 15: **−0.31** (critics −0.50 / −0.12). Rejected; round 15 stays the best. 1st sub-0.3 round since round 14 |
| round-17 | lighting/fog v8 (panel) | 3.75 | 3.86 | 3.80 | 3.25 | 0/4 (A/B-only critic) | Panel vs round 15: **+0.05** (critics +0.50 / −0.41). New best by the ratchet (gain above zero), within noise. 2nd sub-0.3 round in a row and M4's 8th round → **M4 stops at round 17** |
| round-18 | rain v1 (panel) | 3.56 | 3.84 | 3.70 | 3.25 | 0/4 (A/B-only critic) | Panel vs round 17: **−0.34** (critics −0.44 / −0.25). Rejected; round 17 stays the best. Rain alone 3.0 / 3.5 vs 2.0 (no rain). 1st sub-0.3 round in M5 |
| round-19 | rain v2 (panel) | 3.78 | 3.97 | 3.88 | 3.25 | 0/4 (A/B-only critic) | Panel vs round 17: **+0.31** (critics +0.31 / +0.31). New best; resets the sub-0.3 count. Rain alone split (2.5 vs 3; 3 vs 2) |
| round-20 | rain v3 (panel) | 3.69 | 3.81 | 3.75 | 3.25 | 0/4 (A/B-only critic) | Panel vs round 19: **−0.02** (critics −0.38 / +0.34). Rejected; round 19 stays the best. 1st sub-0.3 round since round 19 |
| round-21 | rain v4 (panel) | 3.44 | 3.72 | 3.58 | 2.75 | 0/4 (A/B-only critic) | Panel vs round 19: **+0.09** (critics +0.12 / +0.06). New best by the ratchet. 2nd sub-0.3 round in a row → **M5 stops at round 21** |
| round-22 | vegetation v1 (panel) | 3.97 | 4.03 | 4.00 | 3.5 | 0/4 (A/B-only critic) | Panel vs round 21 (M5 final): **+0.62** (critics +0.69 / +0.56). New best; vegetation alone 4 vs 2.5 (both critics) |
| round-23 | vegetation v2 (panel) | 3.53 | 3.62 | 3.58 | 3.0 | 0/4 (A/B-only critic) | Panel vs round 22: **−0.06** (critics −0.22 / +0.09). Rejected; round 22 stays the best. 1st sub-0.3 round in M6 |
| round-24 | vegetation v3 (panel) | 4.12 | 3.97 | 4.05 | 3.38 | 0/4 (A/B-only critic) | Panel vs round 22: **+0.33** (critics +0.31 / +0.34). New best; resets the sub-0.3 count |
| round-25 | vegetation v4 (panel) | 3.72 | 3.72 | 3.72 | 3.0 | 0/4 (A/B-only critic) | Panel vs round 24: **−0.14** (critics +0.03 / −0.31). Rejected; round 24 stays the best. 1st sub-0.3 round since round 24 |
| round-26 | vegetation v5 (panel) | 3.56 | 4.03 | 3.80 | 3.0 | 0/4 (A/B-only critic) | Panel vs round 24: **−0.11** (critics +0.12 / −0.34). Rejected. 2nd sub-0.3 round in a row → **M6 stops at round 24** |
| round-27 | lantern v1 (panel) | 4.09 | 4.44 | 4.27 | 4.0 | 0/4 (A/B-only critic) | Panel vs round 24: **+1.00** (critics +0.94 / +1.06). New best; lantern system 5 vs 2.5 and 5 vs 3 |

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


## Round 5: water v5 (final water round)

**Scores (1–10)**
- inner: 2, 1.5, 2.5, 2, 2, 1.5, 1.5, 1.5 (mean 1.81)
- cover: 2, 1.5, 2.5, 2, 2, 1.5, 1.5, 1.5 (mean 1.81)

**Water alone:** 3/10, up from 2. The critic credits the "depth darkening toward the channel and the warm light spill on the bed". The biggest remaining problem is "no surface reflection at all: no sky, no broken specular glitter, no reflection of the lantern".

**Top 5 giveaways**
1. Clay-egg boulders: no texture, wetness, moss or waterline. They fuse, and are not seated in the water (+2).
2. Featureless blurred green banks: a spline edge with a glassy rim and a yellow halo stripe (+1 to +1.5 inner).
3. Water:
   - no reflection, specular or Fresnel
   - swirl and smear flow artefacts (concentric arcs in shot 8, radial streaks in shot 4)
   - compressed tone: p1 ≈ 0.10 against ≈ 0.02 in the refs; p99 0.4–0.6 against ≥ 0.9
   - fine-detail energy 2–8× lower than the refs
4. Debug-looking sprites:
   - square orange leaves
   - outlined firefly discs
   - a ring of square specks in the pool
   - a hard dark trapezoid in shot 5
   - a "translucent grey cylinder" under the lantern in shots 2 and 6
5. The lantern: a clipped white box with a lens-flare star and no reflection.

**A/B:** 0/4 fooled, all at 100 % confidence. The critic notes that each render half is a recognisable crop of a capture under review, so A/B can't discriminate until the gap closes.

**Stop rule applied.** Round 4 (−0.18) and round 5 (−0.10) both gained less than 0.3, so water stops at v5. Overall scores are now held down by things water can't fix: rocks, banks, sprites, lantern and grade.

**Carried forward**
- **Reflection balance** (sky and canopy against the bed): v4 was too much, a veil; v5 too little, no surface. This is really a light-balance problem (sky radiance against lantern-lit bed), so it moves to **M4 lighting and fog** and is re-tuned there with real numbers.
- **Specular glitter** from the lantern on wavelets: M7 (lantern glow).
- **Tone compression:** M9 grade.
- **Swirl smears:** M8 (the TAA history on flow-advected detail is suspected).

**Bugs fixed before the M2 APK**
- The shot-5 trapezoid was the greybox leaf's shadow from the lantern's point light 3 cm away, magnified onto the bed. Leaves no longer cast shadows; M6 brings real leaves with soft shadows.
- The shot 2/6 "cylinder" is a greybox rock stretched down to the deeper bed (a regression in v5). The M3 scanned rocks replace it.


## Round 6: stone and moss v1 (M3)

**What changed:**
- The greybox egg rocks are replaced by 13 Poly Haven photogrammetry scans (decimated to 2.4k triangles), seated on gravel mounds.
- The rock shader darkens wet stone by height.
- The banks use ambientCG Ground037 and Moss001 cushions, with Poly Haven mud along the waterline.
- The shoreline wanders off the sim's spline.

**Scores (1–10)**
- inner: 3, 2.5, 3.5, 2.5, 3, 2.5, 3, 2 (mean 2.75)
- cover: 3, 2.5, 3.5, 2.5, 3, 2.5, 3, 2 (mean 2.75)

**Stone and ground alone:** 3/10. Biggest problem: "nothing is wet and nothing touches the water". The rocks and bank edges are dry and matte, with no darker wet band, sheen or moss caps. The banks are a flat painted texture.

**Top 5 giveaways** (the systems they belong to are in brackets)
1. The lantern is a clipped white emissive box with no paper, structure or reflection (M7).
2. The water has no surface: no reflection, Fresnel or glints; smear and swirl artefacts (M4 and M8, carried forward).
3. Game sprites: orange squares and square-pixel fireflies (M6 and M7).
4. Banks:
   - flat, painterly "camouflage" texture with tiled dark clover patches
   - dark "burn" decals
   - a bank cut of uniform width
   - lit like noon, not dusk (the lighting part goes to M4)
5. Rocks don't sit in the water:
   - no wet band, gloss or moss caps
   - fuzzy white foam rings and ruler-straight white streaks
   - some rocks lit gold "from no source"
   - a few box-like silhouettes

**A/B:** 0/4 fooled (99 %).

**Builder notes**
- The "burn decals" were bank hollows dipping within 3 cm of the waterline, which the mud-and-soak rule then turned to mud. A `noshadow=1` probe ruled out the lantern's shadow. Fixed: mud is limited to the stream margin, and the bank never sags back toward the waterline.

**Changes for round 7 (M3 v2)**
- Rocks:
  - moss caps on upward faces above the splash zone (Moss001, planar from above)
  - near-black wet stone with gloss in the splash band
  - albedo greyed and darkened toward refs 03, 09 and 13
- Render-only shore stones that step down into the water along both margins.
- The bank lip varies in width and steepness; moss reaches the water's edge in places; the mud strip is no longer uniform.
- Sharper height-based detile, so two photo taps no longer cross-fade into a painterly smear.
- Rock foam: the straight flank streaks are removed and the fuzzy collar softened. These belong to the rock-water contact, so they are handled here.


## Round 7: stone and moss v2 (M3)

**What changed:**
- Rock footprints are baked from the scans, so foam and contact hug each stone's real outline.
- Moss caps, a wet gloss band and render-only shore stones.
- Sharper detile, a varied mud strip and a varied bank lip.

**Scores (1–10)**
- inner: 3.5, 3, 4, 2.5, 3.5, 3, 3, 2.5 (mean 3.13)
- cover: 3, 3, 4, 2.5, 3.5, 3, 3, 2 (mean 3.00)

**Stone and ground alone:** 3.5/10. Biggest problem: rocks and banks "do not react to water or gravity":
- the same matte moss texture covers every face, including vertical sides and the waterline
- they meet the water with a soft dark halo

ref03 and ref09 show moss only on top, glossy black wet sides, and a bright wet line where stone enters the stream.

**Top 5 giveaways**
1. Water has no surface (M4 and M8). It also has a "pale grey plastic film" over the new shallow shelves, which **is** M3's doing: the water shader's shore term doubles the reflection where the water is thin.
2. The lantern is a white self-lit cube (M7).
3. Flat fake dusk:
   - lifted blacks (p1 15–26/255 against 3–14 in the references)
   - no blue/warm contrast
   - dark AO-like halos along the banks and under rocks (the halos are M3's contact term)
4. Flat orange squares, hard firefly dots, "glowing eye pairs" (M6 and M7).
5. Matte, copy-pasted ground and rocks:
   - moss on every rock face
   - stretched sides
   - a uniform dirt lip
   - blotches all the same size
   - no overhangs (overhangs are M6)

**A/B:** 0/4 fooled (99 %).

**Changes for round 8 (M3 v3)**
- Rocks:
  - the scan's own moss is suppressed on steep and low faces, which become dark wet stone
  - caps only on faces within about 35° of horizontal
  - the whole rock is rain-wet (glossy sides)
  - vertical stretch capped at 1.25×, with mounds doing the rest
- The contact halo is tightened and weakened.
- The water's thin-shore reflection boost drops from 2× to 1.3×, removing the plastic film on the shelves.
- The banks get a second, larger patch scale (whole mossy zones against bare litter zones), and more shore stones.


## Round 8: stone and moss v3 (M3)

**Scores (1–10)**
- inner: 3, 2.5, 3, 2, 2.5, 2.5, 2.5, 2 (mean 2.50)
- cover: 3, 2.5, 3, 2, 2.5, 2.5, 2.5, 1.5 (mean 2.44)

**Stone and ground alone:** 3/10, down from 3.5. "Nothing is wet or seated": the rocks are matte, with "the lawn texture projected onto their tops". There is no wet band, sheen or waterline.

**Top 5 giveaways**
1. The lantern is a flat white box or hexagon (M7).
2. Dusk lit like an overcast day:
   - the lawn is 2–3× brighter than the water
   - milky blacks (p1 0.06–0.10)
   - p99 only 0.52–0.71
   - a lavender cast

   This is M4, and the critic expects it to be worth +1 to +1.5.
3. Water has no surface: dark funnel shadows, swirl smears, a uniform cobble decal (M4 and M8).
4. Rocks and banks are dry and unseated:
   - lawn-like moss projected onto rock tops
   - stretched texels on rock sides
   - a blurred black halo at the bank edge
5. Debug-looking particles (M6 and M7).

The critic's ceiling estimate: even with all five fixed, about 5–6. The map-like framing with no haze and no grass blades at macro scale would remain (M4, M6 and M8).

**A/B:** 0/4 fooled.

**Builder notes.** The v2-to-v3 changes were small (rocks darker and wetter, a moss-zone scale), but the score dropped 0.59. A good part of that is likely critic-to-critic variance; I'm not reading it as a real regression. Three stone-level faults are concrete and mine, though:
- The Moss001 caps projected from above look like lawn at rock scale.
- The rock atlases at 1k are too coarse on sides lit by the lantern.
- Planar xz mapping smears the steep bank lip into a blurred black band.

**Changes for round 9 (M3 v4; decides whether M3 stops):**
- The projected caps are dropped. Rock tops keep the scan's own photographed moss, a little more saturated; it is real moss at real scale.
- The rock colour and normal atlases go to 2k (about +3 MB of APK).
- The ground uses dominant-axis triplanar mapping on steep faces, so the bank lip shows real soil and mud texture instead of smeared streaks.


## Round 9: stone and moss v4 (M3), the first paired panel

**What changed (v4):**
- Projected moss caps dropped; only the scan's own moss is kept, on top faces.
- 2k rock atlases.
- Arc-length bank UVs.

**Panel**

Two fresh critics each scored round 9 against round 7 (the best, v2), side by side, as unlabelled X and Y. The order was flipped between the two critics.

| Critic | Round 9 (new) | Round 7 (best) | Difference | Stone, new vs best |
|---|---|---|---|---|
| a (new = X, ran A/B) | 3.09 | 3.66 | −0.56 | 3.5 vs 4.5 |
| b (new = Y) | 3.16 | 3.72 | −0.56 | 3 vs 4 |

- **Gain −0.56**, with a critic spread of 0.00.
- The new round's absolute score is 3.12 (inner 3.22, cover 3.03; worst shot 2.5).
- A/B: 0/4 fooled.
- Tokens: about 350k for the panel (174k and 176k).

**Why v2 wins, in the critics' words:**
- v4 rocks are "bare, sharp-faceted charcoal with a violet cast", reading as "coal lumps or props".
- The denser shore stones look "dropped in": sharp, black and sitting on the turf.
- v2's moss caps over dark sides match refs 03 and 09.

Both critics also point out that the v2 moss is brown-olive (R above G, about 54/50/45) where real moss is yellow-green (about 70/78/46). That colour comes partly from the lavender dusk light (M4).

**Decision**
- Rounds 8 and 9 both failed to beat the best by 0.3 (−0.59 single-critic, then −0.56 panel), so **M3 stops at its best version, v2**.
- Kept from v3 and v4 as clear fixes: arc-length bank UVs, the weaker contact halo, the water thin-shore reflection fix, and the 2k rock atlases.
- The final M3 build is captured as `captures/m3-final/`. That is the baseline the first M4 round is judged against.
- The panel's highest-gain items for later systems:
  - the lantern (M7)
  - dusk light balance: darker, bluer ambient; a local warm key; grain (M4 and M8)
  - the water surface: sky reflection, glints, wakes (M4)
  - leaves and fireflies (M6 and M7)


## Round 10: lighting and fog v1 (M4)

**What changed:**
- **Sky:** a blue-hour sky (Poly Haven Aarfontein Dawn) behind a baked forest treeline; Venus and stars removed.
- **Light balance:** no directional light; the lantern is the key light (×1.6, 3 m range).
- **Atmosphere:** dark mist that hugs the ground, plus 8 cm ground-truth ambient occlusion.
- **Water colour:** amber tannin instead of red, which removed the magenta cast.

**Panel** (each critic compared this round with `captures/m3-final` side by side, order flipped)

| Critic | Round 10 (new) | M3 final (best) | Difference | Lighting alone, new vs best |
|---|---|---|---|---|
| a (new = Y) | 3.78 | 2.88 | +0.91 | 4.5 vs 3 |
| b (new = X) | 3.81 | 3.06 | +0.75 | 4.5 vs 3 |

- **Gain +0.83** (critic spread 0.16), so **this round becomes the best**.
- Absolute score 3.80 (inner 3.69, cover 3.91; worst shot 3.5). Highest so far.
- **A/B**, now judged by a separate critic that saw only the four pairs: **0/4 fooled**, 99 % each. The giveaway it named was the white glowing box.
- Tokens: 172k + 166k for the panel, 73k for the A/B critic.

**What both critics credit:**
- true dusk blacks (p1 0.01–0.04, against 0.05–0.10 before)
- a cool, neutral ambient (far grass about 38/42/41, against ref11's dusk tree mass at 43/47/51)
- the warm lantern dominating against the cool surroundings
- no grey veil

**What both critics flag as M4 problems:**
1. **The lantern lights like a stage light.** Bank slopes 400–500 px away glow in long, even bands that end at a hard line on the bank crest. A candle lantern's light should die within about a metre (refs 02, 03).
2. **Near-black shadow holes on the bed** under rocks. Under water, shadows are filled by the sky and broken up by caustics (refs 05, 06).
3. **Glossy "bean" highlights on submerged pebbles.** Stones under water lose their sheen; the highlight belongs on the water surface (refs 02, 07, 08).
4. **No glow in the damp air around the lantern**, and little loss of contrast with distance.

**Other giveaways, for later stages:**
- the lantern is a clipped white cube (M7)
- the water has no surface or glitter (M7 glints)
- sprite leaves and fireflies (M6, M7)
- flat tiled grass (M6)

**Changes for round 11 (M4 v2):**
- Lantern light range 3 m → 1.3 m, with the near pool kept, and a softer shadow.
- No specular on submerged ground.
- A small sky fill so shadows on the bed aren't black.
- Slightly denser dark mist, so contrast drops with distance.

## Round 11: lighting and fog v2 (M4)

**What changed** (the round-10 list):
- Lantern light range 3 m → 1.3 m, keeping the near pool; softer shadow.
- No specular on submerged ground or rocks.
- A small sky fill in the water, so shadows on the bed are not black.
- Slightly denser dark mist, so contrast drops with distance.

**Panel** (each critic compared this round with `captures/round-10` side by side, order flipped)

| Critic | Round 11 (new) | Round 10 (best) | Difference | Lighting alone, new vs best |
|---|---|---|---|---|
| a (new = X) | 3.28 | 2.91 | +0.38 | 4.5 vs 4 |
| b (new = Y) | 3.34 | 2.97 | +0.38 | 4 vs 3.5 |

- **Gain +0.38** (critic spread 0.00), so **this round becomes the best** and M4 continues.
- Absolute score 3.31 (inner 3.25, cover 3.38; worst shot 3.0). This is lower than round 10's 3.80 although both critics prefer round 11 in the same sitting. The absolute level drifts from panel to panel (calibration), which is why the ratchet uses only the paired difference.
- **A/B** (separate critic, pairs only): **0/4 fooled**, 97–99 %. It named the glowing white box lantern, flat card leaves and sprite fireflies.
- Tokens: 179k + 179k for the panel, 72k for the A/B critic.

**What both critics credit:**
- The lantern pool is tight: the bed and water fall to the ambient level away from it, as in ref02 and ref06.
- The far water is cooler (about 24/23/28 against 32/28/29), which keeps the warm-against-cool contrast of a dusk photo.
- The gravel-like highlights on submerged pebbles are gone.

**What they flag as remaining lighting problems:**
1. **The ambient is flat and directionless.** It reads as a darkened daytime render, not blue-hour skylight. The blacks are lifted (darkest 1 % at 7–13/255) and grain-free.
2. **No glow in the damp air** around the lantern: only a tight bloom (refs 01, 03).
3. **The key light is near-white.** The lantern core measures about 250/244/230. A paper lantern stays amber (ref02 paper about 248/170/95, ref10 about 248/214/124).
4. **The banks still catch a bright rim** of lantern light about a metre away, sometimes brighter than the water beside the lantern.
5. **The mist over the water reads as an even veil** with no ripple structure (critic a counts it against round 11, critic b in its favour).

**Other giveaways, for later stages:**
- the water has no surface: no sky reflection, ripples or glitter (M7 glints)
- the lantern is a featureless box (M7)
- flat tiled grass (M6)
- card leaves and dot fireflies (M6, M7)
- no grain or depth of field (M8 post)

**Changes for round 12 (M4 v3):**
- An amber key: amber light colour and an amber core instead of near-white.
- A soft glow around the lantern in the damp air.
- A directional blue-hour fill (brighter from the sky side), with the uniform ambient term lowered so the blacks go deeper.
- Less lantern spill on bank slopes about a metre away.

## Round 12: lighting and fog v3 (M4)

**What changed:**
- **Lantern colour:** amber light and paper; the emission is cut so tone mapping no longer bleaches it white. The light source now sits inside the paper; a larger sphere had lit the lantern's own outer faces.
- **Glow in the air:** low, wide bloom that only emitters pass.
- **Sky light:** a faint, cool, shadowless directional light from the open side of the valley.
- **Darker blacks:** a darker mist colour, and banks 25 % darker (rain-damp ground).
- **Reach:** lantern range 1.3 m → 1.0 m, in the engine light and in the custom shaders.

Cover shots 7 and 8 were captured in a second run from the same web build, after the first run hit its one-hour limit; the CPU was shared with device-bring-up browser tests.

**Panel** (each critic compared this round with `captures/round-11` side by side, order flipped)

| Critic | Round 12 (new) | Round 11 (best) | Difference | Lighting alone, new vs best |
|---|---|---|---|---|
| a (new = X) | 3.19 | 2.78 | +0.41 | 3.5 vs 3 |
| b (new = Y) | 3.44 | 2.94 | +0.50 | 4 vs 3.5 |

- **Gain +0.45** (critic spread 0.09), so **this round becomes the best** and M4 continues (round 3 of at most 8).
- Absolute score 3.31 (inner 3.22, cover 3.41; worst shot 3.0).
- **A/B** (separate critic, pairs only): **0/4 fooled**, 98–99 %. It named the cube lantern, tiled moss, card leaves, and missing water optics (caustics, reflections broken by stones).
- Tokens: 196k + 183k for the panel, 72k for the A/B critic.

**What both critics credit:**
- The lantern is no longer a clipped white box with a black outline. It is unclipped and warm: luma about 178, matching the paper in ref02.
- The surround is 12–14 % darker, so the single warm source dominates (refs 02, 05, 10, 11).
- The pool is warmer: red minus blue is 75–83 against 64–70, a stronger warm/cool split.

**What both flag as remaining lighting problems:**
1. **Hard-edged bright stripes on the bank slopes.** In shot 2 the lit bank is about 2.5 times as bright as the bed beside the lantern. A candle in paper barely lights a bank a few lantern-widths away (refs 01, 10).
2. **The cube is dimmer than its own hot spot:** about 178 against 235–249 directly beneath it, so it reads as a box on a lamp. A real lantern has an opaque base, so the bed right under it is shaded and the paper is the brightest thing in frame (ref01's darker base).
3. **Flat, directionless ambient and no visible glow in the air** around the light.

**Other giveaways, for later stages:**
- the stream reads as dry gravel, with no surface, glints or sky sheen (water; see the device note below)
- the cube lantern itself (M7)
- tiled grass (M6)
- card leaves and disc fireflies (M6, M7)

**Device note.** The first frames from the phone (test builds 10 to 12) found three problems the browser captures do not show:
- the pebble bed rendered as a regular lattice (16-bit shader precision; fixed);
- the water is not drawn at all on the phone: the effects probe measured about 1.4 luma change when the water is hidden, against 9.4 in the browser (being bisected in test build 13);
- the glow may be weaker.

The captures and this panel are browser-only.

**Changes for round 13 (M4 v4):**
- An opaque, dark base under the lantern that casts a shadow down: no hot spot beneath it, and the paper becomes the brightest thing.
- Lantern core slightly brighter, still amber.
- Softer, weaker bank spill: wider shadow penumbra, lower light intensity on the slopes.
- A faint glow around the lantern in the damp air.

## Round 13: lighting and fog v4 (M4), rejected

**What changed:**
- **Base:** a dark wooden base under the lantern, casting the lantern light's shadow downward.
- **Brightness:** amber core 0.6 → 0.9; light intensity about 15 % lower.
- **Shadows:** softness 5 → 11.
- **Glow:** a faint additive halo that fades out where it meets surfaces.
- **Banks:** a damp, darker margin within about 14 cm of the stream.

**Panel** (each critic compared this round with `captures/round-12` side by side, order flipped)

| Critic | Round 13 (new) | Round 12 (best) | Difference | Lighting alone, new vs best |
|---|---|---|---|---|
| a (new = Y) | 3.91 | 3.53 | +0.38 | 4 vs 3.5 |
| b (new = X) | 3.22 | 3.81 | −0.59 | 3.5 vs 4.5 |

- **Gain −0.11**, with a critic spread of 0.97, the widest so far. **Rejected: round 12 stays the best.** This is M4's first round under 0.3. If the next is under 0.3 too, M4 stops at round 12.
- Absolute score 3.56. This is higher than round 12's 3.31 from its own panel, but levels drift between panels; only the paired difference counts.
- **A/B** (separate critic, pairs only): **0/4 fooled**, 97–98 %.
- Tokens: 182k + 171k for the panel, 72k for the A/B critic.

**Why the critics split** (the lantern's base shadow):
- **Critic a:** the bed in shadow under the lantern makes it float above the water, and the tighter pool is right for a candle in paper (ref02, ref10).
- **Critic b:** the shadow reads as a hard-edged black hole beside the lantern, a teardrop, oval or wedge that "looks like missing geometry" (shots 3, 4, 5, 8; cover 1).
- **Both:** the shape is too clean, lumpy and evenly dark. A real one would be soft and broken up by the rippled surface (ref07).

**What both now rank first:**
- **The water has no surface:** no dusk-sky sheen, no broken reflection or glitter of the lantern, no flow. They estimate +1.5 to +2 for fixing it.
- Then the blank cube lantern, the tiled grass, the flat grey ambient with spotlight-like bank stripes, and the card leaves and dot fireflies.

**Changes for round 14 (M4 v5, built on round 13, judged against round 12):**
- The base shrinks to a 4 cm candle holder: a small, soft darkening under the lantern, not a void beside it.
- Lantern radiance well above the scene (emission about 1.6), so its mirror image and glints show on the water at a 55° view, the way a candle dominates ref02.
- Lantern light about 15 % lower again on the banks, to fight the stripes.


## Round 14: lighting and fog v5 (M4)

**What changed** (built on round 13, judged against round 12, the best):
- **Base:** the dark wooden base became a 4 cm candle holder, giving a small, soft darkening under the lantern.
- **Lantern radiance:** emission 1.6, well above the rest of the scene, so the lantern reads as the light source.
- **Bank spill:** lantern light about 15 % lower again.
- **Kept from round 13:** shadow softness 11, the faint additive halo and the damp bank margin.
- **Bug fix kept by the ratchet either way:** refraction offsets are capped at 6 mm, which ends the radial smears next to lit rocks (task 26, verified in the browser).

**Panel** (each critic compared this round with `captures/round-12` side by side, order flipped)

| Critic | Round 14 (new) | Round 12 (best) | Difference | Lighting alone, new vs best |
|---|---|---|---|---|
| a (new = X) | 3.42 | 3.05 | +0.38 | 3.5 vs 3 |
| b (new = Y) | 3.16 | 2.66 | +0.50 | 3.5 vs 3 |

- **Gain +0.44**, critic spread 0.12. **Round 14 is the new best.** It is M4's fifth round, so three remain (rounds 15–17). Round 13's sub-0.3 result no longer counts toward the stop rule, because this round cleared 0.3.
- Absolute score 3.29 (inner 3.25, cover 3.33); lowest shot 2.75.
- **A/B** (separate critic, pairs only): **0/4 fooled**, 99 % on every pair.
- Tokens: 183k + 173k for the panel; the A/B critic ran separately.

**Why both critics preferred round 14:**
- **The lantern reads as a light source.** Its body measures about L 213 against L 177 in round 12. Round 12's lantern looked like "a beige-grey box sitting in its own light".
- **The pool is tighter.** In round 12 the lantern-to-surroundings ratio was about 2.7:1. Now it is about 3.5:1. The references are about 4:1 (ref02) and 20:1 (ref10).
- **Shadows are cooler.** Critic b also noted the lantern's face is brighter and its warm pool tighter.

**What both now rank first (unchanged since round 12):**
1. **The water has no visible surface.** Open water measures L≈14–17, half the brightness of the grass (L≈31–37). In ref11 and ref01 the water is brighter than the banks because it mirrors the sky. Critic a calls this "the biggest lighting giveaway": the scene looks lit by a flat grey fill plus one point light rather than by a sky. Estimated gain if fixed: +1.5 to +2.
2. **The lantern is a featureless glowing cube.** Its light is pale cream: the spill's green-to-red ratio is about 0.77, against 0.44 in ref02.
3. **Flat, tiled, dry banks and matte rocks.**
4. **Sprite props:** flat orange quads and identical round fireflies.
5. **The "dusk" is a flat grey night.** There is no blue-hour colour in the darks (blue minus red is only about +4), no mist halos and no grain.

**A/B methodology note (from the A/B critic, recorded as given).** The test is weak as built. All four render halves are frames of the same scene with the same giveaways (the emissive cube, the tiled banks, the floating quads, the same overhead night view). The photos differ in subject, viewpoint and lighting. So the pairs only show that the renders are easy to tell apart, not how realistic the water, wet stone or moss looks. A stronger test would pair each photo with a render of a matching subject, framing and time of day. *My response:* the fixed camera and scene make true matched pairs impossible for most references. From round 15 I keep the test (you asked for it) and read it as a pass/fail floor, not a gradient. The paired panel remains the measure of progress.

**Changes for round 15 (M4 v6, built on round 14):**
- **Blue-hour sky in the water.** The sky gaps in the reflection get brighter and bluer, so open water reads lighter than the banks where it faces the sky. The treeline mask stays, to avoid round 4's uniform veil. This is sky brightness, a lighting parameter; the water shader's structure is unchanged.
- **Saturated amber light.** The lantern's light colour moves toward the candle amber of ref02. The body stays the brightest thing in frame.
- **Blue in the darks.** The skylight gets a cooler, deeper blue, so shadowed banks read blue-hour rather than grey. Black levels are kept.

## Round 15: lighting and fog v6 (M4)

**What changed** (built on round 14, judged against it):
- **Reflection balance.** The water reflects an open blue-hour sky at three times its old level (1.2 against 0.4; an earlier version of this entry said 0.8, the value of a browser test). It sees that sky through a leaf layer 2.5 m above the stream (half cover) and past a crisp treeline. Ripples move the reflected ray across those edges, so the surface breaks into sky gaps and leaf shadows (ref10).
  - A browser test without the leaves gave a uniform blue veil over the near water (round 4's failure), so the leaves are what makes this work.
- **Darker fill.** The canopy-shaded diffuse fill on banks, rocks and bed went from 0.25 to 0.19.
- **Skylight.** Bluer and slightly stronger: colour (0.32, 0.48, 1.0), intensity 0.09.
- **Lantern colour.** Light (1.0, 0.42, 0.13), paper (1.0, 0.44, 0.12); both were paler.
- **Browser tuning.** Look constants now read query parameters, so variants come from one web build. Android ignores them.

**Panel** (each critic compared this round with `captures/round-14` side by side, order flipped)

| Critic | Round 15 (new) | Round 14 (best) | Difference | Lighting alone, new vs best |
|---|---|---|---|---|
| a (new = X) | 3.28 | 3.06 | +0.22 | 4 vs 3.5 |
| b (new = Y) | 3.47 | 2.97 | +0.50 | 4 vs 3.5 |

- **Gain +0.36**, critic spread 0.28. **Round 15 is the new best.** It is M4's sixth round, so two remain (rounds 16 and 17).
- Absolute score 3.38 (inner 3.44, cover 3.31); lowest shot 2.75.
- **A/B** (separate critic, pairs only): **0/4 fooled**, 98–99 %. It read pair 3's "perfect concentric ripple rings" as a render tell.
- Tokens: 179k + 171k for the panel, 73k for the A/B critic.

**What the critics agree on**
- **Why the new round wins: the water now has a surface.** Sky sheen, ripples and flow detail replace "the bed as if through air" and "dry gravel".
- **The new blacks are deeper.** In critic b's measurements the darkest 5 % fell from about 12–15 to 8–11 out of 255. Critic a found the old round "lifted" by 0.015–0.02.
- **What limits the gain: the ripples now visibly look procedural.** The sky gaps reveal the ripple texture's structure:
  - fingerprint swirls (shots 1, 2, 3, 6, 7)
  - brushed-metal streaks (shot 4 and the covers of 2 and 6)
  - evenly spaced concentric rings across the pool in shot 8
  - critic a takes back X's advantage entirely in shot 4 and on cover 8
- **The water still has no glitter path.** It reflects the lantern only as a small blob at its base, with no broken column of glints (ref02).

**Top giveaways (both critics):**
1. Procedural ripple patterns and no glitter path (+1.0 to +1.5).
2. The lantern is a featureless glowing box (+0.5 to +1.5).
3. Flat, tiled bank carpet.
4. **A sourceless blue fill with no true blacks.** Measured against the references, the fraction of pixels below 0.03 is 33 % (ref05) and 66 % (ref10), against about 2 % here. The lantern lights the bank lips as long, evenly lit strips instead of falling off fast (ref10, ref02). There is no grain.
5. Card leaves and sprite fireflies.

**Changes for round 16 (M4 v7, built on round 15):**
- **Ripples without patterns.** The reflection's ripple slopes come from more scales, mixed so no single pattern dominates. This removes the visible rings, whorls and brushed streaks while keeping the broken sky gaps.
- **Deeper blacks.** Less canopy-shaded fill, so frames away from the lantern fall toward black, as in ref10. The water's sky gaps stay as they are, so the surface reads against darker banks.
- **Faster falloff.** The lantern light drops off faster with distance, so the banks show a bright spot near the lantern rather than long, evenly lit strips.

## Round 16: lighting and fog v7 (M4), rejected

**What changed** (built on round 15, judged against it):
- **Sky and leaf reflection.** It takes 30 % of the broad wave tilt and 140 % of the fine ripple tilt (it took 100 % of both). This was meant to remove the contour rings, whorls and brushed streaks.
- **Leaves.** Leaf clusters 2.2 times finer, with slightly softer edges.
- **Darker fill.** 0.19 → 0.13.
- **Lantern reach.** 1.0 m → 0.65 m.

**Panel** (each critic compared this round with `captures/round-15` side by side, order flipped)

| Critic | Round 16 (new) | Round 15 (best) | Difference | Lighting alone, new vs best |
|---|---|---|---|---|
| a (new = X) | 3.50 | 4.00 | −0.50 | 3.5 vs 4 |
| b (new = Y) | 3.34 | 3.47 | −0.12 | 4 vs 3.5 |

- **Gain −0.31**, critic spread 0.38. **Rejected: round 15 stays the best.** This is M4's seventh round and its first under 0.3 since round 14. Round 17 is the eighth and last M4 round under the stop rule.
- Absolute score 3.42; lowest shot 3.0.
- **A/B** (separate critic, pairs only): **0/4 fooled**, 99 % on every pair.
- Tokens: 187k + 184k for the panel, 75k for the A/B critic.

**Where the critics agree:**
- **The open water became a veil (the main loss).** Without the broad tilt, the open water away from the lantern turned into a smooth lilac-grey sheet. Over the darker banks it is brighter than they are (critic b: veil about 24/26/36, banks 19/23/25), so it reads as "frosted glass or ice". Critic a: "bluish-lavender veil with soft dark blotches and brush-like streaks". This repeats round 4's failure. At this steep view real water is mostly transparent, shows the bed (ref07, ref08) and carries reflections as glints and broken shapes. The rings were reduced but not gone (critic a still saw them in shot 8).
- **The shorter lantern reach is more photographic (both critics, though in opposite sets).** Critic a, for the new set: "X's tighter pool is closer to a candle"; light on a nearby surface dies within one or two lantern widths (ref10). Critic b, for the new set: distant rocks stay cool grey instead of glowing orange.
- **Darker fill:** split. Critic a preferred the brighter round 15 (more like blue-hour dusk, less like night). Critic b preferred the darker, cooler new round.
- **The new pool reflection in shot 8 is the one place the new water won** (critic b: "a real dusk pond reflecting trees").

**Top giveaways now (both critics):**
1. The water has no glints or broken lantern reflection, and the ring pattern persists.
2. The lantern is a glowing cube with a soft-capped core and no halation.
3. Flat, stamped bank texture.
4. Murky, compressed tones with no mist or scatter around the light.
5. Card leaves and dot fireflies.

**Ratchet.** The code goes back to round 15. Kept regardless of the result:
- **Water depth test.** The shader now skips any water fragment with opaque scene in front of it, with highp depth values. This fixes a device bug: water drawn over low bank grass (test17 run b, `captures/device/`).
- **The parameters themselves** (`sky_broad`, `canopy_scale`, `lantern_range`), set to round-15 values.

**Changes for round 17 (M4 v8, the last M4 round, built on round 15):**
- **Lantern reach 0.65 m.** Both critics preferred it.
- **Sky reflection: 60 % of the broad tilt.** Half-way between round 15 (rings) and round 16 (veil). The leaf edges stay round 16's slightly softer ones, so fewer contour lines show.
- **Halation.** Bloom intensity 0.12 → 0.18, so the lantern glows into the damp air (critics in rounds 14 and 16: "never enters the air as mist, scatter or halation"; ref03).

## Round 17: lighting and fog v8 (M4), the last M4 round

**What changed** (built on round 15, judged against it):
- Lantern reach 1.0 m → 0.65 m.
- The sky/leaf reflection takes 60 % of the broad wave tilt, with slightly softer leaf edges.
- Bloom intensity 0.12 → 0.18.

**Panel** (each critic compared this round with `captures/round-15` side by side, order flipped)

| Critic | Round 17 (new) | Round 15 (best) | Difference | Lighting alone, new vs best |
|---|---|---|---|---|
| a (new = Y) | 4.09 | 3.59 | +0.50 | 4 vs 3.5 |
| b (new = X) | 3.52 | 3.92 | −0.41 | 3.5 vs 4 |

- **Gain +0.05**, with a critic spread of 0.91. By the ratchet rule (any gain above zero) round 17 is the new best, but the result is within noise: the critics flatly disagree.
- Absolute score 3.80 (inner 3.75, cover 3.86); lowest shot 3.25.
- **A/B** (separate critic, pairs only): **0/4 fooled**, 98–99 %.
- Tokens: 172k + 186k for the panel, 74k for the A/B critic.

**The disagreement is about one thing: how far the lantern's light reaches.**
- **Critic a (for round 17's 0.65 m):** "A candle in paper is a weak source whose light dies off within about a lantern-width or two" (ref01). Round 15 "behaves like a large-radius point light", and its orange spreads so the frame "looks graded rather than lit".
- **Critic b (for round 15's 1.0 m):** surfaces facing a bright source should all catch some of its light (ref10's ceiling, ref11). Round 17's pool "reads like a game light radius". It also found the stronger bloom a uniform haze that washes out the pebble contact shadows, while ref10's lantern has "essentially no bloom".
- **Across rounds 16 and 17, three of the four critic opinions favoured the shorter reach.**

## M4 lighting and fog: summary

M4 stops at round 17 under the stop rules: two consecutive rounds under +0.3 (rounds 16 and 17), and its eighth round.

| | Round 10 (M4 v1) | Round 17 (M4 final) |
|---|---|---|
| Panel gains along the way | +0.83 over M3 | +0.38, +0.45, (−0.11), +0.44, +0.36, (−0.31), +0.05 |
| Lighting score, new set | 4.5 vs 3 (M3) | 4 vs 3.5 (critic a); critic b preferred round 15, 4 vs 3.5 |

The paired gains compound to roughly **+2.4 over M3's final version** in total, though gains measured on different panels don't add exactly. Absolute scores drift between panels (3.3–4.1), so the paired gains are the honest measure.

**What M4 achieved:**
- A blue-hour fill with deeper blacks.
- An amber paper lantern as the light that dominates the scene, falling off quickly.
- A water surface that reflects a sky gap through overhanging leaves.
- Bloom used as halation.
- On the phone: the black-screen fix, precision fixes, water drawn at all, and the depth test that stops water drawing over the banks.

**What critics still rank highest:**
1. **Flat, stamped banks.** Now the top giveaway for both round-17 critics: no blades or clumps; this is M6 vegetation.
2. **The lantern is a uniform glowing cube** (M7 lantern).
3. **The water has no glints and still shows procedural ripple swirls or rings.** It also has no rain rings (M5 rain).
4. **A flat, directionless ambient with no mist** (M5 rain and M8 post).
5. **Card leaves and dot fireflies** (M7).

## Round 18: rain v1 (M5), rejected

**What changed** (built on round 17, the M4 final, judged against it):
- **Streaks.** Rain streaks as particles. About 600 drops sit in a slab around the lantern and are lit by it; each glints like a small lens within 1 m. A faint share of sky light reaches them too. Streaks are about 1/40 s of motion. The game clock drives them, so captures freeze them like a photo.
- **Rain rings on the water.** Three offset cell layers, one drop per cell per 0.8–1.7 s. Each ring is a 1 cm crest train growing at 11 cm/s. A splash glint shows at impact. Slopes are doubled.
- **Wet banks and rocks.** Damp 0.35 → 0.7, and bare stone is glossier.

**Panel** (each critic compared this round with `captures/round-17` side by side, order flipped). `System` here scores the rain and wetness alone.

| Critic | Round 18 (new) | Round 17 (best) | Difference | Rain and wetness, new vs best |
|---|---|---|---|---|
| a (new = X) | 3.62 | 4.06 | −0.44 | 3 vs 2 |
| b (new = Y) | 3.78 | 4.03 | −0.25 | 3.5 vs 2 |

- **Gain −0.34**, critic spread 0.19. **Rejected: round 17 stays the best.** This is M5's first round under 0.3; if the next is under 0.3 too, M5 stops at round 17, with no rain.
- Absolute score 3.70; lowest shot 3.25.
- **A/B** (separate critic, pairs only): **0/4 fooled**, 97–98 %. It named "evenly spaced, perfectly straight rain streaks" of identical length and angle.
- Tokens: 193k + 184k for the panel, 73k for the A/B critic.

**Where the critics agree:**
- **The streaks read as an overlay, and they cost more than they add.** Both critics measured the same thing: every streak is about 1 px wide, the same length, the same lean and in sharp focus. Spread evenly up to a third of the frame from the lantern, they are "a field of streaks over the scene", not rain recorded by a lens.
  - A camera this steep would see drops foreshortened and converging toward the point straight below it.
  - Drops near the lens would be wide, soft smears.
  - Critic a: "Real rainy-evening photos often show no streaks at all" (ref05: puddles and wet sheen everywhere, no streaks). Ref03 shows rain only through what it does to the water.
  - Near the lantern the streaks lay "an orange, hairy halo" over the lit cobbles, with dark ticks over the bright water.
- **The water should carry the rain, and it barely reacts.** Both critics barely found the rings: "the water does not react to it". Ref03 shows "the dense field of small overlapping impact rings and splash crowns". The large ripple swirls are still there and still read as painted.
- **Wetness:** critic b preferred the new round's wet glints along the lantern-lit bank edges and rocks. It measured them 15–25 levels brighter, following the edges as on wet stone (refs 07, 01, 04), and found the darker banks right. Critic a saw the banks darker but "no wet sheen" and was neutral.

**Changes for round 19 (rain v2, built on round 17):**
- **No streaks.** The particle code stays but is off by default.
- **Rings and crowns carry the rain.** A dense field of small overlapping rings: four cell layers of 7–14 cm, crests 6 mm apart, about three times as many rings at once. Splash crowns catch the lantern's light strongly near it: a crown is a small vertical sheet of water facing every way, so it glints where a flat surface cannot.
- **Wetness is kept:** damp 0.7 and glossier bare stone.

## Round 19: rain v2 (M5)

**What changed** (built on round 17, judged against it):
- **No falling streaks.**
- **Denser, smaller rain rings:** four cell layers of 7–14 cm, crests 6 mm apart.
- **Splash crowns** glint with the lantern's light.
- **Wind ripples at half strength in rain.**
- **Wetness from round 18 kept:** damp 0.7 and glossier bare stone.

**Panel** (each critic compared this round with `captures/round-17` side by side, order flipped)

| Critic | Round 19 (new) | Round 17 (best) | Difference | Rain and wetness, new vs best |
|---|---|---|---|---|
| a (new = X) | 3.53 | 3.22 | +0.31 | 2.5 vs 3 |
| b (new = Y) | 4.22 | 3.91 | +0.31 | 3 vs 2 |

- **Gain +0.31**, critic spread 0.00. **Round 19 is the new best.** M5 continues; the sub-0.3 count resets.
- Absolute score 3.88 (inner 3.78, cover 3.97); lowest shot 3.25.
- **A/B** (separate critic, pairs only): **0/4 fooled**, 98–99 %. For the first time no tell was about the water or the rain. It named the cube lantern, the flat leaf cards and the tiled bed.
- Tokens: 180k + 169k for the panel, 73k for the A/B critic.

**What won: calmer water.** Both critics found the swirls far weaker in the new round.
- **Critic b:** the new water "reads as a calm, dark, reflective surface", while the old round is "covered in curl-noise swirls that look like fingerprints or brush strokes". No real water forms whorls (refs 01, 07, 10, 03).
- **Critic a, the other way round:** it saw the old round's whorls as oversized rain rings, "5–10 times too large and far too regular", and preferred the new round's "calm, glassy water with soft, wavy reflections".
- Both found the old round's concentric rings across the shot-8 pool read as "a pattern laid over the image".

**What still fails (both critics):**
- **The rain is too faint and at the wrong scale.** Light rain should show as "a fine, even pocking across the whole surface" from a distance (ref01). Close up it is many small overlapping rings with crowns (ref05). The new round has only a handful of crisp, identical rings, plus dark specks that "read as dust or insects".
- **The streaks should come back, inside the lantern's light only.** Critic b: "drops passing through a lamp's light should show as short bright streaks, not dark dots". Critic a: "no falling streaks anywhere, not even inside the lantern's light, where drops would catch it". Round 18's streaks failed because they spread a third of the frame out and were all identical, not because they existed.
- **The rest, unchanged:** the cube lantern; the tiled bank carpet with knife-cut, dry, matte edges; no glitter path; card leaves and dot fireflies.

**Changes for round 20 (rain v3, built on round 19):**
- **Pocking.** Two fine layers of tiny impacts (3 and 4.2 cm cells, rings to about 1 cm, 5 mm crests, 0.25 s life) give a dense stipple across all open water.
- **Varied rings.** Each drop gets its own strength and size, so the rings are no longer identical.
- **Streaks back, only inside the lantern's light.** Drops glint within its 0.65 m reach (round 18 used 1 m), so only a handful show near the flame. Fall speeds range 3–6 m/s, so streak lengths differ, and widths vary.
- **No dark specks.** The drifting foam flecks thin out in rain; dark against the sky sheen, they read as dirt.

## Round 20: rain v3 (M5), rejected

**What changed** (built on round 19, judged against it):
- **Streaks back, inside the lantern's 0.65 m reach only.** Fall speeds range 3–6 m/s and widths 2–6 mm.
- **Each rain ring varies.** Strength and size change per drop.
- **Two fine pocking layers** (3 and 4.2 cm cells).
- **Fewer foam flecks in rain.**
- **Fireflies shrink with their glow.** This had no effect: the glow never falls below 0.25 (see below).

**Panel** (each critic compared this round with `captures/round-19` side by side, order flipped)

| Critic | Round 20 (new) | Round 19 (best) | Difference | Rain and wetness, new vs best |
|---|---|---|---|---|
| a (new = X) | 3.34 | 3.72 | −0.38 | 3 vs 2.5 |
| b (new = Y) | 4.16 | 3.81 | +0.34 | 3.5 vs 2.5 |

- **Gain −0.02**, with a critic spread of 0.72. **Rejected: round 19 stays the best.** This is M5's first round under 0.3 since round 19; if round 21 is under 0.3 too, M5 stops at round 19.
- Absolute score 3.75; lowest shot 3.25.
- **A/B:** 0/4 fooled, all at 99 %. It named "identical straight streaks".
- Tokens: 184k + 192k for the panel, 73k for the A/B critic.

**The split is entirely about the streaks.**
- **Critic a: an overlay.** It measured detail 7–21 % more vertical near the lantern: "thin lines of similar length, almost perfectly vertical and parallel everywhere", laid "exactly on the brightest area" as "a scratched, striped texture".
- **Critic b: right in kind.** Warm, inside the lit zone only, and with "true perspective: the lean changes from about 12° at the left edge to about 1° at the right". It still found the length, width and brightness too uniform, saw no large out-of-focus drops near the camera, and noted the streaks stop sharply at the edge of the lit zone.

**Both found the pocking missing**, and they were right: it never reached the captures. The fine layers faded out where a crest spans under 3 pixels of the summed screen-space derivative (`fwidth`). At the half-resolution captures that fade removed about 85 % of the layers. At the phone's full resolution they show.

**Dark specks.** Critic b still saw "a patch of dark pepper specks on the pool in shot 8".
- I first blamed the fireflies' glow, wrongly.
- Isolation tests then ruled out, one by one: foam off (specks stay), lantern shadows off (stay), ambient occlusion off (stay). Hiding the fireflies (specks go) and turning the water reflection off (specks go) both cleared them.
- **The cause is the planar mirror.** It renders at 0.4 resolution, so a 13 mm firefly covers part of a pixel. The water treats any lit mirror pixel as "an object hides the sky here", so it swapped the sky reflection for that dim value, which shows as a dark speck.
- **The fix:** fireflies are now on a render layer the mirror skips. This also explains the "dark ring outlines" critics noted around fireflies since M2.

**Changes for round 21 (rain v4, built on round 19):**
- **Streaks off again.** They split the panel twice.
- **Pocking that survives the captures.** The fine layers fade only where a 7 mm crest spans under about 2 pixels on the worse axis.
- **Fireflies out of the mirror** (the speck fix).
- **Kept from round 20:** rings that vary per drop, and fewer foam flecks in rain.

## Round 21: rain v4 (M5), the last M5 round

**What changed** (built on round 19, judged against it):
- **Streaks off.**
- **Pocking sized to survive the half-resolution captures.**
- **Fireflies on a render layer the planar mirror skips** (the dark-speck fix).
- **Kept from round 20:** rings that vary per drop, and fewer foam flecks in rain.

**Panel** (each critic compared this round with `captures/round-19` side by side, order flipped)

| Critic | Round 21 (new) | Round 19 (best) | Difference | Rain and wetness, new vs best |
|---|---|---|---|---|
| a (new = X) | 3.53 | 3.41 | +0.12 | 2.5 vs 2 |
| b (new = Y) | 3.62 | 3.56 | +0.06 | 3 vs 2.5 |

- **Gain +0.09**, critic spread 0.06. By the ratchet round 21 is the new best. It is M5's second round in a row under 0.3, so **M5 stops at round 21**.
- Absolute score 3.58 (inner 3.44, cover 3.72); lowest shot 2.75.
- **A/B:** 0/4 fooled, all at 99 %. The tells it named were the box lantern, the repeating textures and the firefly dots; none was rain.
- Tokens: 206k + 190k for the panel, 73k for the A/B critic.

**What the gain was: the specks.** Both critics measured the old round's shot-8 pool against the new one.
- **Critic a:** the old round has "4–7× more dark specks".
- **Critic b:** "76 vs 42 isolated dark points, 12 vs 32 bright ones" in the new round's favour. Bright impact glints replaced black pepper.
- **Everything else** measured identical within noise.

**What still fails in the rain (both critics):**
- **Too sparse.** The rain is "a few sparse, crisp, dark-edged rings on an otherwise still mirror" rather than "a dense, even field of fine pocks catching the lantern light as glints" (refs 01, 04, 02).
- **Fine texture:** the fine pocking now registers only as 5–10 % more fine water texture (critic a).
- **Wetness:** rocks and banks still read matte and dry except the lit lip.

## M5 rain: summary

M5 stops at round 21 under the stop rule: two rounds in a row under +0.3 (rounds 20 and 21).

| Round | Change | Gain over best |
|---|---|---|
| 18 | lit particle streaks, rings, wet stone | −0.34 (rejected) |
| 19 | no streaks, denser rings, crowns, wind ripples at half strength | **+0.31** |
| 20 | streaks inside the lantern's light, varied rings, pocking (faded out of captures) | −0.02 (rejected) |
| 21 | no streaks, pocking visible, fireflies out of the mirror | +0.09 |

M5's net gain over M4 final is about +0.4. Most of it came from calming the wind ripples and from the dark-speck fix, not from rain itself.

**What M5 learned:**
- **Falling rain streaks split critics** whatever their density or extent: an overlay to one, rain to the other. A dusk photo mostly shows rain on surfaces.
- **At this steep 55° view,** water reflects about 2.5 %, so impact rings have little to catch. They need lit glints, which only exist near the lantern.

**Still open for later systems:**
- Rain visibility could come back through post (M8: grain, a little veiling glare in damp air) and through the lantern's reflection breaking on the rings (M7).

## Round 22: vegetation v1 (M6)

**What changed** (built on round 21, the M5 final, judged against it):
- **Plants on the banks:** Poly Haven `fern_02` (four variants) and `shrub_sorrel_01` (CC0 scans with alpha-masked leaves), plus procedural grass clumps of 16–28 tapering, arching blades.
- **Placement by distance from the noisy waterline:**
  - dense grass leaning over the water at the edge
  - ferns grouped near the water
  - grass stands across the bank
  - sorrel in the gaps
- **Patchiness:** a smooth noise field gives stands and bare patches.
- **Budget:** per-4 m-chunk instancing. Only ferns cast the lantern's shadow, and ground cover stays out of the mirror.

**Panel** (each critic compared this round with `captures/round-21` side by side, order flipped). `System` scores the vegetation and banks alone.

| Critic | Round 22 (new) | Round 21 (best) | Difference | Vegetation and banks, new vs best |
|---|---|---|---|---|
| a (new = Y) | 4.00 | 3.31 | +0.69 | 4 vs 2.5 |
| b (new = X) | 4.00 | 3.44 | +0.56 | 4 vs 2.5 |

- **Gain +0.62**, critic spread 0.12, the largest since round 10. **Round 22 is the new best.** Absolute score 4.00 (inner 3.97, cover 4.03); lowest shot 3.5.
- **A/B:** 0/4 fooled, all at 99 %. It named "identical repeated grass cards".
- Tokens: 166k + 166k for the panel, 72k for the A/B critic.

**Why both critics preferred it:**
- **Plants break the bank's outline and shade themselves.** The old banks read as "felt or carpet" or "a terrain prototype" (refs 01, 03, 05).
- **At the waterline, grass leans over the water.** It hides the hard spline-cut edge and the smeared, lantern-lit bank face. Near the lantern the blades "glow warm with light passing through" them. Critic b called this "the most photographic thing in either build" (ref02, ref07).
- **Grass shadows deepen the darks:** the darkest 1 % of pixels fell from about 7 to 2–3.

**What still fails in the vegetation (both critics):**
- **"One species of identical tufts, all the same size, evenly spaced on bare gravel,"** almost on a grid (right halves of shots 2, 6 and 7). There are no dense mats spilling toward the water, no dead brown blades and no mixed species. Real banks crowd where the ground is wet (refs 03, 05, 01, 09).
- **Flowers sprinkled at a constant density.** The ferns read as "flat dark cards".
- **The hard bank lip shows wherever there are no tufts.** It has stretched texture on the vertical faces and no dark wet band, silt or half-sunk stones.
- **Rocks are speckled props with no moss cushions** (critic b; refs 03, 09).

**Changes for round 23 (vegetation v2, built on round 22):**
- **Grass with mixed colour.** Each blade draws its colour from one of four columns: fresh green, olive, straw and dead brown. The mix leans brown away from the water.
- **Clump sizes range 0.5–2× and placement is irregular,** not one clump per grid cell.
- **Density rises toward the water:** a dense, continuous mat along the edge that spills over it.
- **Fewer, more clustered sorrel patches,** so the flowers stop sprinkling evenly.
- **Brighter ferns,** some bronze.

## Round 23: vegetation v2 (M6), rejected

**What changed** (built on round 22, judged against it):
- **Grass blade colours:** blades in four colours (green, olive, straw, dead brown).
- **Grass clumps:** low dense mats along the waterline; clump sizes 0.5–2× and placed irregularly; density rising toward the water.
- **Other plants:** fewer, clustered sorrel; brighter and partly bronze ferns.

**Panel** (each critic compared this round with `captures/round-22` side by side, order flipped)

| Critic | Round 23 (new) | Round 22 (best) | Difference | Vegetation and banks, new vs best |
|---|---|---|---|---|
| a (new = X) | 3.69 | 3.91 | −0.22 | 3.5 vs 4 |
| b (new = Y) | 3.47 | 3.38 | +0.09 | 3.5 vs 3 |

- **Gain −0.06**, critic spread 0.31. **Rejected: round 22 stays the best.** This is M6's first round under 0.3.
- Absolute score 3.58; lowest shot 3.0.
- **A/B:** 0/4 fooled, 98–99 %. It named "grass made of identical flat blade cards".
- **Interruption:** a usage limit stopped both scoring critics part-way. They were resumed from their saved state with the same packets.
- **Tokens:** 169k + 165k for the panel, 72k for the A/B critic.

**Where the critics agree and split:**
- **Split on the round-22 sorrel.** Critic a preferred round 22's low green rosettes between the tufts: green-dominant pixels were 1.5–1.8× round 23's, "where round 23's gaps are bare grey gravel that reads like asphalt". Critic b preferred round 23 for removing most of the "confetti" of identical pink flowers.
- **Both dislike the flowers.** They read as identical, evenly spaced pink dots.
- **The core complaint is the same for both:** "one spiky grass tuft repeated at even spacing over a flat grey gravel texture, with no moss, leaf litter, mixed species or wet darkening where the bank meets the water". The grey ground between plants, the photographed forest-ground texture, now dominates. Round 23's drier blades also made the banks "greyer, a dry gravel lot" (critic b).

**Changes for round 24 (vegetation v3, built on round 22):**
- **Mossy ground between plants.** Moss covers most of the bank, broken by soil only in patches, and the bank reads darker and damper. The gaps between plants become "moss running right to the waterline" (refs 09, 11), not grey grit.
- **Sorrel without flowers.** Its pink flower pixels are recoloured to leaf green at bake time. It stays the low green filler critic a credited.

## Round 24: vegetation v3 (M6)

**What changed** (built on round 22, judged against it):
- **Mossy ground.** Moss covers most of the bank between the plants (`moss_bias` 0.1), pushed to a deep, wet olive.
- **Sorrel without flowers.** Its flowers are cut out of the alpha mask at bake time.

**Panel** (each critic compared this round with `captures/round-22` side by side, order flipped)

| Critic | Round 24 (new) | Round 22 (best) | Difference | Vegetation and banks, new vs best |
|---|---|---|---|---|
| a (new = Y) | 4.31 | 4.00 | +0.31 | 4 vs 3.5 |
| b (new = X) | 3.78 | 3.44 | +0.34 | 3.5 vs 3 |

- **Gain +0.33**, critic spread 0.03. **Round 24 is the new best;** the sub-0.3 count resets.
- Absolute score 4.05 (inner 4.12, cover 3.97); lowest shot 3.38.
- **A/B:** 0/4 fooled, all at 99 %.
- Tokens: 178k + 174k for the panel, 72k for the A/B critic.

**Why both preferred it:**
- **Bank colour.** Round 22's ground was "cyan to blue-grey… grey gravel or ash under a cold grade" (median hue 180–200°, blue about equal to green). The new ground is green (hue about 160°, green 10 % above blue). It reads as "soil and grass", and as wet ground that keeps its colour in rain (refs 04, 06, 01, 05).
- **No flower decals.** Round 22 had 18–67 identical lilac specks per inner frame; the new round has 0–3.

**What still fails in the vegetation (both critics):**
- "Separate, near-identical tufts placed at even spacing on a flat, uniformly speckled ground".
- The waterline is "a clean, dry seam":
  - no moss running under the water
  - no plants rooted in the water
  - no dark wet band
  - no wet sheen on the ground or the blades
  
  Real banks show these things (iris clump standing in water in ref01, moss under a water film in ref09, ferns down to the waterline in ref02).
- **Critic a, beyond vegetation:** the frames sit at a median luminance of about 23/255, darker than a phone would auto-expose at dusk (refs 03, 07). They also lack the camera noise of a phone at blue hour. Both belong to the post and grade milestones.

**Changes for round 25 (vegetation v4, built on round 24):**
- **Plants rooted in the shallows.** Taller wet-grass clumps stand in the water up to 8 cm from the edge, their bases under the surface.
- **Irregular grass:** offsets up to about a cell beyond each grid cell, and clump sizes from 0.5 to 2×.
- **A wet waterline:**
  - a darker, glossier band where the bank meets the water
  - wet moss with a soft sheen instead of matte

## Round 25: vegetation v4 (M6), rejected

**What changed** (built on round 24, judged against it):
- **Grass rooted in the shallows:** taller, near-upright clumps standing up to 8 cm into the stream.
- **Irregular bank grass:** offsets up to most of a cell beyond the grid, sizes 0.5–2×.
- **A wet waterline:** a glossy soaked band (roughness 0.12) and wet moss with a sheen.

**Panel** (each critic compared this round with `captures/round-24` side by side, order flipped)

| Critic | Round 25 (new) | Round 24 (best) | Difference | Vegetation and banks, new vs best |
|---|---|---|---|---|
| a (new = Y) | 3.91 | 3.88 | +0.03 | 4 vs 3.5 |
| b (new = X) | 3.53 | 3.84 | −0.31 | 3.5 vs 4 |

- **Gain −0.14**, critic spread 0.34. **Rejected: round 24 stays the best.** This is M6's first round under 0.3 since round 24.
- Absolute score 3.72; lowest shot 3.0.
- **A/B:** 0/4 fooled, 98–99 %.
- Tokens: 179k + 186k for the panel, 73k for the A/B critic.

**Where the critics split and agree:**
- **Split on the clumps in the water.**
  - Critic a liked the "softer, untidy waterline" with grass leaning across it and tufts "rising out of shallow water", like ref01's iris clump and the plants trailing into the current in ref08.
  - Critic b found them "pasted on": grass standing in moving water with no wake or matching reflection. They also cover "the lantern-lit pebble bed, one of the most photographic parts of the frame".
- **Both found the lantern-lit grass wrong.** It was too bright and lemon-yellow. Critic a measured 3–5× as many pixels above level 120 and a red/green ratio of 1.24 against 1.37. Being taller as well, the tufts "read as self-lit props". In ref02, plants lit by a lantern go "amber-olive with a soft falloff".
- **Still common to both:** one clean green clump repeated, with "no variety of species, height, colour or dead material". The ferns are barely legible, and the edge has no wet, muddy band.
- **The A/B critic's "fine grid in the dark water"** lines up with the 8/16-pixel JPEG blocks of the packet (critic a). It is a compression artifact, not the render.

**Changes for round 26 (vegetation v5, built on round 24):**
- **Grass colour.** Blade tips are darker and more olive, so the lantern's light turns them amber-olive instead of lemon.
- **Some dead blades.** A light mix of straw and dead blades (about 10–15 %) goes into the mostly green clumps.
- **No clumps standing in the water.** The edge grass leans over the water from the bank, as in round 24.
- **Kept:** the glossy soaked band and the wet-moss sheen, which neither critic objected to.

## Round 26: vegetation v5 (M6), rejected; M6 stops

**What changed** (built on round 24, judged against it):
- **Darker, more olive blade tips.**
- **Straw and dead blades:** about 10–15 %, mixed into mostly green clumps.
- **Kept from round 25:** no clumps standing in the water, the glossy soaked band and the wet-moss sheen.

**Panel** (each critic compared this round with `captures/round-24` side by side, order flipped)

| Critic | Round 26 (new) | Round 24 (best) | Difference | Vegetation and banks, new vs best |
|---|---|---|---|---|
| a (new = Y) | 4.22 | 4.09 | +0.12 | 3.5 vs 3.5 |
| b (new = X) | 3.38 | 3.72 | −0.34 | 3.0 vs 3.5 |

- **Gain −0.11**, critic spread 0.47. **Rejected.** This is the second round in a row under +0.3 (rounds 25 and 26), so **M6 stops at round 24**. The code is back at round 24.
- Absolute score 3.80; lowest shot 3.0.
- **A/B:** 0/4 fooled, 98–99 %.
- Tokens: 176k + 169k for the panel, 73k for the A/B critic.

**What the darker tips did:**
- **Critic a, lantern-lit grass:** better. It became "amber or ochre" rather than lime, with "shadowed blades between the lit ones" that give the clump depth (refs 10, 03).
- **Critic a, the unlit field:** worse. The tufts became "dark stars stamped on lighter ground, which makes the even planting grid more obvious". From above, blade tips facing the sky should be lighter than the soil (refs 05, 01).
- **Critic b:** "sparse, stiff, near-black star-shaped tufts", teal-grey when unlit and straw-orange when lit.

## M6 vegetation: summary

M6 stops at round 24 under the stop rule: two rounds in a row under +0.3 (rounds 25 and 26).

| Round | Change | Gain over best |
|---|---|---|
| 22 | ferns, sorrel, procedural grass by zone and noise patches | **+0.62** |
| 23 | blade colour mix, edge mats, density toward the water | −0.06 (rejected) |
| 24 | mossy wet-olive ground, flowerless sorrel | **+0.33** |
| 25 | clumps in the shallows, irregular grass, glossy waterline | −0.14 (rejected) |
| 26 | olive blade tips, some dead blades | −0.11 (rejected) |

M6's net gain over the M5 final is about **+0.95**, the largest of any system since M2. Panel absolute scores are now about 4.0–4.2.

**What still fails (every critic):**
- **Identical tufts at even spacing over a speckled ground.** Real banks have continuous, mixed, overlapping cover with dead material (refs 03, 04, 05).
- **A hard, dry seam at the water.**

**Approaches likely to beat round 24:**
- **Fill the ground itself, not the tufts.** For example, a moss or turf material with real relief and blades in the texture, or shell-textured short grass, so no bare speckle shows between clumps.
- **Use several distinct grass meshes,** from scans or hand-built, instead of one procedural clump.

Both are bigger jobs than a tuning round. M7 comes first: the lantern, fireflies and floating leaves are now the top giveaways in every panel.

## Round 27: lantern v1 (M7)

**What changed** (built on round 24, judged against it):
- **The lantern** is a paper toro nagashi lantern instead of a glowing cube (ref02):
  - four slightly tapered paper panels (6.6 × 8.5 cm) standing in a dark wooden tray, open at the top
  - the paper shows the candle's light through it: a deeper orange band at the base, a pale hot spot above it, peach paper fading toward the rim, slightly darker folded corners and paper fibre
  - a column of brushed characters on each panel
  - brighter, paler inner faces seen through the open top
  - the candle no longer lights the lantern's own paper and wood, which had clipped them to white
- **Fireflies** are soft glows of varied size and brightness, a 4–6 mm core in a faint halo, drawn out into short streaks along their flight (ref06). Before, they were identical hard dots.
- **Floating leaves** are cupped leaf shapes with an outline, stalk, midrib, side veins and decay spots, tinted per leaf from rust and ochre to dull olive and soaked brown. Before, they were flat orange squares.

**Panel** (each critic compared this round with `captures/round-24` side by side, order flipped)

| Critic | Round 27 (new) | Round 24 (best) | Difference | Lantern, fireflies and leaves, new vs best |
|---|---|---|---|---|
| a (new = Y) | 3.72 | 2.78 | +0.94 | 5 vs 2.5 |
| b (new = X) | 4.81 | 3.75 | +1.06 | 5 vs 3 |

- **Gain +1.00**, critic spread 0.12. **Round 27 is the new best,** the largest single gain of any round so far.
- Absolute score 4.27 (inner 4.09, cover 4.44); lowest shot 4.0.
- **A/B:** 0/4 fooled, 97–98 %. The A/B critic still called the render's lantern "a glowing white cube" at its crop size.
- Tokens: 184k + 175k for the panel, 73k for the A/B critic.

**Why both preferred it** (the rest of each frame was identical, which both confirmed by difference maps):
- **The lantern.** The old one was "a single blown-out emissive block… a game pickup", with 2–4 times as many pixels above 200 near it. The new one "keeps the paper below clipping": walls, open top, tray, a calligraphy mark (refs 02, 11).
- **The leaves.** The old "flat orange squares… like confetti or UI tiles" are gone.
- **The fireflies.** The old spheres had "hard bright cores with a dark cap… tiny bug sprites"; the new ones are "soft round glows that fade smoothly" (ref06).

**What still fails in the lantern system:**
- **The paper is too pale and even.** Measured at about (221,175,132) against ref02's (249,176,98): it should be warmer amber, brightest at candle height low in the lantern, with bolder characters.
- **A bright blob at the waterline below the lantern,** brighter than the paper itself (about 245 against 210–220). In ref02 the lantern's reflection is a long, dimmer column broken by ripples.
- **Fireflies too pale and uniform:** about (213,209,167) against ref06's saturated yellow-green (about 208,231,127), all similar in size; a cluster in shot 8 looks evenly spaced.
- **Leaves too dark, one size and tone:** ref08's leaves are curled, mixed yellow and brown, some partly sunk.

**Beyond this system, both critics' top giveaways are unchanged:** the even grass field over speckled ground, water with too little rain or sky sheen and stair-stepped reflection edges, the clean point-light pool with hard edges on the banks, and no camera signature (grain, depth of field).

**Changes for round 28 (lantern v2, built on round 27):**
- **No waterline blob; the lantern's own reflection instead.** The blob was the candle light's specular reflection on the water. Treated as a small sphere about 70 times brighter than the paper is drawn, its 2.5 % reflection outshone the lantern. The candle light no longer reaches the water directly. The water now traces each pixel's reflected ray, tilted by ripples and rain, against the lantern's paper box. The reflection is then the paper's own shape and colour, dimmer than the lantern and broken at its edges (ref02).
- **A softer near field:** the candle light is treated as the 7 cm glowing box (radius 6 cm, not 3 cm), so the bed just under the lantern no longer outshines it.
- **Paper:** warmer amber, brightest at candle height and half as bright at the rim, with larger, bolder characters.
- **Fireflies** are saturated yellow-green, with a wider range of brightness.
- **Leaves** come in mixed yellows and browns, at sizes from 0.7 to 1.3. A third ride low, soaked, with their middles just under the surface.

