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
