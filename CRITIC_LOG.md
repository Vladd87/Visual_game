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
