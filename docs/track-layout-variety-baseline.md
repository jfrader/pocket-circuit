# Generated-layout variety: baseline and next steps

Measured 2026-09-21 against generator revision `01a234c`, generator version 7.
Worktree: `/home/fran/Workspace/Worktrees/pocket-circuit-guri-928`.
Branch: `jfrader/guri-928-layout-variety`. No production generator changes.

## Result

This is a general layout-vocabulary problem, not just a marathon problem.
In seeds 0–11, classic/compact accepts only dogleg; long/compact falls back to
the technical perimeter 9/12 times; every non-compact EL tier selects just one
base program. Conversely, several long/endurance cells produce 12/12 shape
clusters. The evidence does **not** say every cell has equally poor geometric
variation: parameter variation can produce distinguishable silhouettes without
adding any authored route skeletons.

There were **no empty circuits or validation failures** in either the default
120-case sweep or the expanded 360-case sweep. These windows overlap; this is
360 unique room/tier/seed cases, not 480 independent cases.

## Reproduce and verification output

Run from the worktree above, with Godot `4.7.2.stable.arch_linux.ed1daf0bf`:

```sh
godot --headless --editor --import --quit
```

The first import completed, but the subsequent test emitted
`Cannot get class 'GamestrumentsPlayer'` and an audio-director script error.
The pinned package was present in `vendor/`, not installed in the local addon
directory (which contained only its README). Fixed locally with the existing
release procedure, without touching the main checkout:

```sh
GAMESTRUMENTS_ADDON_DIR="$PWD/vendor/gamestruments" ./tools/sync_gamestruments.sh
godot --headless --editor --import --quit
godot --headless --path . --script res://tests/track_diversity_sweep_test.gd
```

Final default run, seeds 0–3 in each of 30 cells, exit 0:

```text
Totals: cells=30  sum_distinct_seq=120  sum_distinct_shapes=105  generation_fails=0
TRACK_DIVERSITY_SWEEP elapsed_ms=173883 invalid=0
TRACK_DIVERSITY_SWEEP_TEST PASS cells=30 seq=120 shapes=105 fails=0 seeds_per=4
```

Expanded measurement:

```sh
PC_DIVERSITY_SEEDS=12 godot --headless --path . --script res://tests/track_diversity_sweep_test.gd
```

```text
Totals: cells=30  sum_distinct_seq=359  sum_distinct_shapes=279  generation_fails=0
TRACK_DIVERSITY_SWEEP elapsed_ms=530393 invalid=0
TRACK_DIVERSITY_SWEEP PASS cells=30 seq=359 shapes=279 fails=0 seeds_per=12
```

The expanded run preceded the final marker-only rename to
`TRACK_DIVERSITY_SWEEP_TEST PASS`. Metrics and generation code were unchanged.
The final default rerun reproduced its earlier counts exactly. The old marker
was incompatible with the release runner; the final literal marker is accepted:

```sh
python3 tools/test_success_marker.py tests/track_diversity_sweep_test.gd
# TRACK_DIVERSITY_SWEEP_TEST PASS
godot --headless --path . --script res://tests/track_length_profiles_test.gd
# TRACK_LENGTH_PROFILES_TEST PASS
godot --headless --path . --script res://tests/track_variant_test.gd
# TRACK_VARIANT_TEST PASS
PC_DIVERSITY_SEEDS=bad godot --headless --path . --script res://tests/track_diversity_sweep_test.gd
# TRACK_DIVERSITY_SWEEP_TEST FAIL: PC_DIVERSITY_SEEDS must be 1..200
# Exit 1, no PASS marker (verified with a subprocess assertion).
```

The default stays at the prior implementation's **actual four seeds**, not its
incorrect comment claiming 48. At 174 seconds it is a bounded CI regression
measurement, not an interactive unit test: 120 circuit generations plus full
revalidation, no scene construction or racing simulation. Release CI already
discovers `tests/*.gd` and allows 1200 seconds per test
(`tools/build_release.sh:117–140`). Larger windows are opt-in; runtime on a
slower CI worker remains unmeasured. Full release/physics suites were not run.

## What the sweep measures

- **Seq:** distinct existing normalized sampled route signatures. The public
  implementation emits a token every five centerline samples, with three
  strength bins (`track_seed_gen.gd:101–137`). Length, sample phase, radius and
  bin crossings can change this string without changing the layout skeleton.
- **Rhythm:** the same signature collapsed into cyclic L/R/S runs, ignoring
  strength bins, then canonicalized again. This reduces token-density inflation
  but is still a sampled geometric proxy, not an authored module graph.
- **Shape:** greedy representative clusters in ascending seed order; 128
  arc-length samples of the actual sampled centerline, centroid/RMS normalized,
  minimum RMS distance across rotation, reflection, traversal direction and
  discrete cyclic phase shifts. Merge when distance is **less than 0.055**.
  Finite phase resolution and threshold/ordering affect the result. Small local
  features can still be missed. This is not an exact equivalence relation.
- **T histogram:** number of cyclic L/R runs → number of circuits. These are
  not individual authored corners or the existing broad-complex peak metric.
  Same-handed turns can merge if no sampled S separates them.
- **S histogram:** literal heading-stable straight regions of at least 450
  units, using the generator's 0.04-radian criterion. Unlike the original
  sweep, an S token is not counted as a whole straight.
- Per-cell stdout also includes mean canonical L/R run counts and mean S.
  Canonical L/R labels do not describe the chosen race traversal's handedness.
- Rooms come from `TrackBuilderCatalog.ROOM_SHAPES`; tier scales and
  room-specific minimum lengths match `TrackBuilderCore.prepare_layout`.
  Every accepted output is revalidated with corridor clearance 135, explicit
  nonlocal self-distance 320, simple closure/intersection checks, radius 147,
  two setup and two literal straights, room-polygon clearance and bypass checks.
  Failures include room, tier, seed and reason, finish the table, and exit 1.

All legal circuits are mathematically simple cycles. Here “topology variety”
means different labeled section arrangements and spatial embeddings—not
different unlabelled graph topologies. **None of Seq, Rhythm, or Shape is an
exact count of those arrangements.** Do not sum cell counts as global uniques.

The adopted test retains the original sweep, table and shape-distance approach;
it fixes the misleading defaults, runtime room duplication, token-as-corner
counts, eight-point undersampling, unused fingerprint, unconditional PASS and
release-marker incompatibility. Built-in fixtures check cyclic run merging,
empty signatures, equivalent transforms, reversed/shifted traversal and a
dogleg-versus-oval negative control. It deliberately does not encode today's
low diversity as a permanent acceptable floor.

## Default baseline: four seeds per cell

Each cell is **Seq / Shape**. Generation failures: **0 in every cell**.

| Room | Compact | Standard | Long | Endurance | Marathon |
|---|---:|---:|---:|---:|---:|
| classic | 4/3 | 4/3 | 4/4 | 4/4 | 4/4 |
| wide | 4/4 | 4/3 | 4/4 | 4/4 | 4/4 |
| tall | 4/4 | 4/4 | 4/3 | 4/4 | 4/3 |
| long | 4/3 | 4/4 | 4/4 | 4/4 | 4/4 |
| square | 4/3 | 4/4 | 4/4 | 4/4 | 4/4 |
| el | 4/4 | 4/2 | 4/2 | 4/2 | 4/2 |

## Expanded baseline: twelve seeds per cell

Histogram notation is `value:frequency`; each histogram sums to 12.
Programs: D=dogleg, H=harbour, I=infield, W=switchback,
P=technical_perimeter, DC=deep_comb, DS=double_switchback, MC=multi_comb,
ML=multi_lobe, SE=serpentine, EL=el_safe, EF=el_folded.
Generation failures and invalid outputs: **0 in all 30 cells**.

| Room/tier | Seq/Rhythm/Shape | T distribution | S distribution | Accepted programs | Fallbacks |
|---|---:|---|---|---|---:|
| classic/compact | 12/8/6 | 5:3 6:1 7:1 8:7 | 2:9 4:2 5:1 | D:12 | 0 |
| classic/standard | 12/10/11 | 7:2 8:6 9:2 10:1 11:1 | 2:2 3:4 4:1 5:4 6:1 | D:4 H:3 I:3 W:2 | 0 |
| classic/long | 12/12/12 | 7:1 8:1 9:6 10:2 12:1 13:1 | 5:3 6:5 7:1 8:3 | D:4 H:3 I:3 W:2 | 0 |
| classic/endurance | 12/11/12 | 8:1 9:2 10:6 11:1 13:2 | 6:2 7:4 8:4 10:2 | D:4 H:3 I:3 W:2 | 0 |
| classic/marathon | 12/11/11 | 18:3 21:2 22:1 23:1 24:1 25:2 31:1 32:1 | 15:3 16:1 18:1 19:3 20:2 21:1 28:1 | DC:4 MC:4 ML:2 SE:2 | 0 |
| wide/compact | 12/8/8 | 6:1 7:2 8:6 9:2 10:1 | 2:8 3:3 4:1 | D:9 W:2 P:1 | 1 |
| wide/standard | 12/10/11 | 6:2 8:2 9:1 10:3 11:3 12:1 | 2:4 3:2 4:2 5:3 6:1 | D:4 I:6 W:2 | 0 |
| wide/long | 12/10/12 | 6:1 7:1 8:1 9:4 10:2 11:1 12:2 | 5:3 6:3 7:3 8:2 9:1 | D:5 H:2 I:3 W:2 | 0 |
| wide/endurance | 12/12/12 | 7:1 8:1 9:3 10:4 11:1 13:1 14:1 | 6:2 7:4 8:3 10:2 11:1 | D:4 H:3 I:3 W:2 | 0 |
| wide/marathon | 12/11/11 | 18:2 21:4 22:1 23:1 24:2 32:2 | 15:3 16:1 17:2 18:1 19:3 23:1 29:1 | DC:4 MC:4 ML:2 SE:2 | 0 |
| tall/compact | 12/8/6 | 5:1 6:3 7:6 8:2 | 2:9 3:3 | D:7 I:5 | 0 |
| tall/standard | 12/9/11 | 5:1 7:4 8:5 9:2 | 2:4 3:2 4:1 5:5 | D:5 H:4 I:3 | 0 |
| tall/long | 12/10/11 | 8:1 9:4 10:5 11:1 12:1 | 5:2 6:4 7:4 8:2 | D:1 H:6 I:3 W:2 | 0 |
| tall/endurance | 12/11/12 | 8:1 9:3 10:4 11:2 12:1 15:1 | 6:2 7:3 8:5 10:1 11:1 | D:4 H:3 I:3 W:2 | 0 |
| tall/marathon | 12/11/11 | 20:2 21:1 23:3 24:1 25:4 31:1 | 16:1 17:3 18:4 20:1 21:1 22:1 25:1 | DC:4 DS:2 MC:3 SE:3 | 0 |
| long/compact | 11/8/3 | 6:1 7:1 8:7 9:2 10:1 | 2:10 3:2 | W:3 P:9 | 9 |
| long/standard | 12/12/7 | 6:1 7:1 8:2 10:2 11:5 13:1 | 2:8 3:3 5:1 | D:4 W:8 | 0 |
| long/long | 12/9/11 | 6:3 8:1 9:4 10:2 11:1 13:1 | 5:5 6:4 7:1 8:2 | D:5 H:3 I:2 W:2 | 0 |
| long/endurance | 12/10/12 | 7:2 9:4 10:4 13:1 14:1 | 6:5 7:1 8:3 9:1 11:2 | D:4 H:3 I:3 W:2 | 0 |
| long/marathon | 12/10/10 | 16:2 21:3 22:2 24:2 25:1 30:1 32:1 | 15:2 16:1 17:1 18:1 19:5 24:1 28:1 | DC:3 MC:5 ML:2 SE:2 | 0 |
| square/compact | 12/9/7 | 6:3 7:7 8:2 | 2:8 3:1 4:3 | D:10 I:2 | 0 |
| square/standard | 12/10/11 | 7:6 8:5 9:1 | 3:3 4:4 5:5 | D:6 H:3 I:3 | 0 |
| square/long | 12/10/12 | 8:2 9:2 10:7 12:1 | 5:1 6:4 7:4 8:3 | D:4 H:3 I:3 W:2 | 0 |
| square/endurance | 12/11/12 | 8:2 9:3 10:1 11:4 12:2 | 6:2 7:3 8:5 9:1 10:1 | D:4 H:3 I:3 W:2 | 0 |
| square/marathon | 12/12/11 | 18:3 19:1 20:2 21:1 23:1 24:2 25:1 30:1 | 15:3 16:2 17:2 18:3 19:1 20:1 | DC:4 MC:3 ML:2 SE:3 | 0 |
| el/compact | 12/10/9 | 5:2 6:1 7:5 8:3 9:1 | 2:11 3:1 | D:7 I:5 | 0 |
| el/standard | 12/10/4 | 8:5 9:5 10:1 11:1 | 2:10 3:2 | EL:12 | 0 |
| el/long | 12/12/5 | 8:1 9:3 10:5 11:1 12:2 | 2:3 3:3 4:4 5:2 | EL:12 | 0 |
| el/endurance | 12/12/4 | 8:1 9:2 10:5 11:2 12:2 | 3:4 4:3 5:2 6:2 7:1 | EL:12 | 0 |
| el/marathon | 12/5/4 | 21:10 22:1 23:1 | 17:2 18:2 19:7 20:1 | EF:12 | 0 |

## Ranked variety caps

Paths below are relative to `scripts/race/` unless specified. Counts are
authored skeleton/choice bounds, **not** bounds on all floating-point shapes or
sampled signatures. They overlap and must not be multiplied indiscriminately.

| Rank | Mechanism and evidence | Representation cap versus constant cap; estimated vocabulary |
|---|---|---|
| 1 | Fixed ordered anchor programs: `track_route_grammar.gd:4–8,25–80,86–123`; tier dispatch `track_seed_gen.gd:399–408,579–597`. | **Representation:** choose one complete anchor list, then fit/round it; no sequence search over independently connected modules. **Constants:** four non-marathon program names and five marathon names. At most 4 standard authored base skeletons; 5 folded programs, but double-switchback and deep-comb share the same anchor-order topology (`:163–195`), so at most 4 folded structural archetypes before chamfers/motifs. Similarity can identify fewer. Increasing a list length adds only those authored alternatives, not compositional combinations. |
| 2 | EL bypasses shared grammar: `track_seed_gen.gd:211–224,637–676,695–780,814–854`. | **Representation:** special room-name dispatch to an L footprint instead of fitting a general route graph to free space. Standard/long/endurance each have **1 base L skeleton**, plus optional excursion; fallback is another fixed L realization, not another traversal pattern. Marathon has **1 three-tooth L skeleton**, plus possible fallback L. Compact uses the normal 4-program vocabulary in a preferred capped left-arm rectangle (2000×1400); the right/bottom arm is only a fallback fitting region, not a freely composed route across both arms. |
| 3 | Fixed section counts and coupled symmetry: `track_route_grammar.gd:45–53,131–195,203–255`; folded EL `track_seed_gen.gd:718–735`. | **Representation:** shared spine/waist/depth coordinates force paired repeated structures. **Constants:** switchback has 12 anchors; double-switchback/deep-comb 20; serpentine 3 teeth per side (28 anchors); multi-comb 3 teeth (16); multi-lobe 4 arms (12); folded EL 3 teeth (18 before chamfers). Each count gives **1 section-count choice per program**, not a variable-length section sequence. Independent depths can yield more shapes but add **0 new section-order topologies** on their own. Not every route is symmetric: deep-comb and dogleg already introduce asymmetry. |
| 4 | Rectangular fitting and scaling: `track_seed_gen.gd:166–190,378–381,401–434,857–868`; `track_route_grammar.gd:27–31,69–79,88–91`; `generated_circuit_rules.gd:19–24`; builder `track_builder_core.gd:155–163`. | **Representation:** room polygon becomes its AABB for proposal construction; polygon is primarily a reject filter. Tall rooms rotate the same templates. Width/height fraction ranges (0.83–0.94 / 0.78–0.88), uniform length fitting and room scales (0.95/1/1.8/2.8/4.5) add **0 section-order alternatives**. They permit many geometric deformations, but long/endurance reuse the same four base programs rather than gaining sections with distance. A rectangle is not mandated by the loop invariant. |
| 5 | Acceptance funnel and first-valid fallback: `track_seed_gen.gd:15,193–207,237–263,286–356,421–437,600–608,1484–1490`. | **Constants/policy, not representation:** 12 primary attempts cycle over 4 or 5 programs; they are not 12 distinct topologies. Four fallback attempts share **1 eight-anchor perimeter skeleton**. Standard has a 0.78 fit floor and forced long aspect >2.5 / tall >1.2. Length bands, 400-unit lane floors and 180-unit construction radius reduce feasibility further. Observed compact classic admits only D; compact long admits W plus P, with 75% fallback. Per-attempt rejection tracing is still needed to attribute those losses to particular validators; do not claim every rejection is the aspect guard. |
| 6 | Local decoration cannot replace route composition: `track_route_grammar.gd:14–18,295–323,369–432`; `track_route_sections.gd:12–18,99–143`; `track_seed_gen.gd:1382–1445`. | **Representation:** same-handed two-arc profiles add **0 macro section orders**. One symmetric four-arc excursion is spliced into at most **1** straight; only the top 3 eligible runs × 3 radii are attempted (9 geometries, at most 3 placement orders plus absence). Standard chamfers cut at most 2 convex corners; folded programs request up to 4. For E eligible corners, standard has at most E singles + E(E−1)/2 pairs, plus no cut when none are eligible; adjacency and the deterministic chooser reduce that loose bound. Raising `maximum` alone does **nothing** on the `require_roll=true` path, which explicitly selects only one or two. Mirrors/global rotations add **0** topology classes under the metric. |
| 7 | Metadata and measurement can overstate variety: `track_seed_gen.gd:32–41,101–137,149–150,384–408`; recipe `track_route_grammar.gd:80,123`; `track_curve_sampling.gd:5–6,34`. | Six family names are seed-stable labels, **not six extra geometry programs**; recipe names embed the seed and can be unique for the same skeleton. Centerline count grows with length, so sampled sequence uniqueness can grow without new topology. There were 359 per-cell distinct signatures among 360 outputs, versus 279 shape clusters and the much smaller program vocabulary above. Fixing the metric reveals the cap; it does not itself add layouts. |

`track_builder_planner.gd:14–23,39–92,96–141` is **not a route-graph planner**:
it places obstacles/hazards on an already supplied centerline. Its 1–3 obstacle
budget and safe-placement skips add zero route topologies. Enlarging that budget
would change driving clutter, not solve generated-layout variety.

The closed-simple-loop representation itself does not force rectangles,
symmetry, fixed teeth or these program counts. Keep that invariant; change how
the cycle's labeled sections and embedding are chosen.

## Plan, ordered by impact/risk and dependencies

1. **Keep trustworthy measurement and add rejection visibility — safe on the
   current generator; low risk.** Adopt this test now. Next, instrument bounded
   per-attempt program/rejection categories without changing RNG consumption or
   accepted geometry; verify byte identity with the existing fingerprint
   benchmark. Compare all 30 cells on seed windows 0–47 and 100000–100047,
   separately reporting fallbacks, coverage and clusters. Use those broader
   results and visual review to agree diversity floors; do not gate on raw
   signature uniqueness. Large windows belong in scheduled QA, not this default
   CI test. Prioritize compact long and EL, but retain all-cell gates.

2. **Broaden the existing vocabulary as a bounded bridge — high near-term
   impact, medium risk; current representation, new geometry version.** Author
   compact-friendly two/three-section dogleg/U/S arrangements with independent
   leg lengths and full-width connectors, not miniature marathon combs. Add
   alternative notch-safe EL embeddings and independent paired depths/counts
   where physical leg budgets permit. Select counts from the length/space
   budget for every tier, not `tier == marathon`. Validate each complete loop;
   preserve two protected setup straights. Measure whether compact-long
   fallback concentration actually drops. Do not lower the 125/147/320/450
   safety constraints or merely increase retries. This is compatible with the
   existing fitter, but **not safe as a silent version-7 seed-map change**.
   Avoid investing in dozens more monolithic templates: that repeats cap #1.

3. **Establish versioned dispatch before enabling new seed geometry — low
   direct variety impact, essential compatibility gate.** Version 7 is a hard
   equality check today (`generated_circuit_identity.gd:6–9,80–87,170–176,
   213–216,363–382`), not a multi-generator dispatcher. Specify supported old
   identities, explicit unsupported-version behavior, cache/fingerprint keys
   and share-code round trips. Preserve version-7 generation behind its dispatch
   if old shares must remain playable; otherwise reject explicitly, never
   silently regenerate them differently. Free-polygon room payloads also need
   schema/room-identity work: current identity only admits six enum rooms
   (`:20–21,42–46`). Compatibility policy is an operator decision before coding.

4. **Build graph-first module composition — highest structural impact, high
   implementation risk; new versioned generator path.** Author reusable modules
   with entry/exit poses, protected footprint, centerline, length interval,
   signed turn, minimum radius, straight budget and connector compatibility.
   Start with sweepers, hairpin/U, dogleg, S and variable-radius corners; reuse
   the existing section geometry where appropriate. Construct a variable-length
   labeled cyclic route graph first. Each module/connector has one predecessor
   and one successor, the graph is connected, and exactly one cycle consumes
   all sections. Bound deterministic backtracking and reserve the closing
   connector's pose/space/length budget early. Avoid branches, figure-eights,
   seed walking and an unrestricted solve followed by last-minute closure.
   Canonical module order—not a recipe hash—becomes a measurable arrangement
   signature. M module choices over k slots gives up to M^k ordered words before
   cyclic/mirror equivalence and feasibility, rather than four whole layouts;
   this is a search-space illustration, not a promised accepted-layout count.

5. **Embed that graph in free-polygon rooms — high impact, high risk; same new
   path, incremental rollout.** Use polygon erosion/free-space queries and
   reserved swept corridors to place modules/connectors, not an AABB as the
   room model. Keep both EL arms and the notch in the constraint set throughout
   placement (compact arm-only occupancy must be an explicit tier policy).
   Reject intersecting edges or connections without full-width passage; reserve
   width 250 plus the required branch separation and turn envelope. Let tier
   length add module count/layout choices before simply scaling the canvas.
   Retain the current full-loop validator after realization and reordering;
   supplement it with continuous segment/offset checks for narrow concavities.

6. **Only then add local WFC fill — low topology impact, bounded risk.** WFC may
   choose dressing/surface/connector-local detail within already reserved
   module footprints. It must not choose the global loop, move the route, close
   its last gap or narrow a passage. Feed the committed route to the existing
   obstacle/story planner, then rerun collision, gate and AI-route clearance.

Release acceptance for geometry changes: all 30 room/tier cells must generate
without invariant violations; compare accepted module arrangements, shape
clusters and fallback concentration on fixed and unseen windows; inspect
representative layouts. Run generator, route-variety, length-profile, section,
composition, collision, generated-runtime and identity/share-code tests plus
four-car forward/reverse AI coverage. Existing AI large-tier mode only exercises
one wide-room case (`tests/ai_seed_sweep_test.gd:67–79`); expand that QA matrix,
do not interpret it as all-room/all-tier coverage. Full release gate remains CI.

## Unresolved and limits

- Only measurement/report work is delivered; generated layout variety itself
  is not changed, and no target architecture implementation is claimed.
- The requested `docs/track_system_constraints.md` exists as
  `docs/track-system-constraints.md`. It was read, along with design spec §11.
  Its marathon “two programs” and blanket EL descriptions at lines 70–77 and
  95–97 lag current code (five programs, folded EL, compact arm handling).
  The plan's target architecture comes from this task, not an already shipped
  graph-first system. This report records the discrepancy without rewriting
  the standing spec during a measurement task.
- Full-width route validation is exercised through the generator's existing
  sampled centerline and corridor-offset contracts; this is not a new proof
  of continuous geometry or final scene collision clearance. No physics or
  visual gameplay acceptance is claimed.
- Some runs, including unchanged neighboring tests, emitted an intermittent
  `1 ObjectDB instance was leaked at exit` warning. Final default sweep did
  not. No audio script errors remained after syncing the native addon. The
  shutdown warning's owner was not diagnosed in this scope.
- Linear, Engram and Godot editor mutation/validation tools were not available
  in this session's callable tool set. No tracker/memory update is claimed;
  actual pinned-engine headless execution supplied script validation. No
  existing Graphify cache was present in this worktree; analysis uses the
  current source files, not an inferred graph.
- Import created local `addons/gamestruments/gamestruments.gdextension.uid`
  and `tests/track_marathon_programs_test.gd.uid`; these unrelated sidecars
  remain untracked and are not adopted. The new diversity test's own UID is
  adopted with the test. `.godot/` and native addon payloads remain local.
- No main-checkout edits, remote operations, push, PR, merge or release.
