# Generated tracks: module composition in free-polygon rooms

Implementation design, 2026-09-21. Source references are relative to this repo
at `451feeb` (generator version 7); proposed names/contracts below are **not
implemented**. This document follows the measured
[variety baseline](track-layout-variety-baseline.md), not a new seed farm.

Work packages: GURI-999 (Module catalog + connector contract), GURI-1000
(Free-polygon room model), GURI-1001 (Cyclic layout solver + loop closure).
These parenthetical names describe the work packages in this specification.

## 1. Decision and scope

Replace whole-route anchor templates with a **variable-length, labeled cycle
of authored modules**, embedded by a bounded deterministic constraint solver
in polygonal free space. Keep the existing generator shipping unchanged.
The new path is called **v8** here; schema 2 identifies its room recipe and
geometry contract. Enable it only after all 30 room/tier cells pass §7.

The pipeline is mandatory:

```text
versioned identity + gameplay requirements
  -> labeled gameplay cycle (moments, protected straights, section budgets)
  -> free-space room + spatial embedding + closure
  -> continuous geometry and sampled-route validation
  -> island/gates/racing lines + authored story placement
  -> optional local fill -> final collision/passability validation
```

No WFC route planning, bridges, elevation, figure-eights, extra lap branches,
seed walking, or reduced safety margins. An infield passage is a full-width
section of this same cycle, not a shortcut across it. The existing risky
shortcut is a lane choice within a route moment, not a second gameplay edge.
This preserves design-spec §11's opening, conflict, technical, speed and finish
moments (`docs/game-design-spec.md:542–568`) within the project's 2D model.

### Current seams and what changes

| Current source | Consequence / v8 seam |
|---|---|
| `scripts/race/track_route_grammar.gd:4–8,25–80,86–123` | Four standard and five marathon whole-anchor programs; replace selection of complete programs with section composition. Adding names is not the solution. |
| `scripts/race/track_seed_gen.gd:164–224,378–380` | Proposals use polygon bounds, and EL has special geometry dispatch. v8 passes a free-space model to placement; AABBs are broad-phase acceleration only. |
| `scripts/race/track_builder_core.gd:144–186,235–248` | `prepare_layout` is the shared headless/runtime integration seam. Dispatch here before room construction and generation, and pass the resulting authoritative centerline onward. |
| `scripts/race/track_route_sections.gd:12–96,99–152` | Reusable G1 two-arc profiles and pose-preserving excursions exist. Reuse their analytic construction ideas, not a resampling shortcut that loses the contract. |
| `scripts/race/track_seed_gen.gd:871–931` | Keep the validation layer: intersection, spacing, offset, room, setup, literal straight, bypass and radius checks. Add continuous checks, do not substitute module labels for validation. |
| `scripts/race/track_builder_planner.gd:14–92,96–141` | This is an obstacle/hazard planner after route generation, not the gameplay graph solver. Keep that responsibility separate. |
| `scripts/race/generated_circuit_identity.gd:80–87,170–176,213–216` | A single-version equality check, not dispatch. Version support must precede any geometry rollout. |

`docs/track-system-constraints.md` remains the v7 reference. Its fixed complex
counts and marathon/EL descriptions at lines 70–77 and 91–97 are not a v8
grammar: the baseline documents their drift from current code. Update those
standing rules alongside implementation, without rewriting v7 fixtures.

Keep the new implementation in small pure components with these boundaries
(names are proposed, not existing APIs):

| Component | Input → output |
|---|---|
| `TrackGeneratorRegistry` | Validated versioned request → the selected legacy/v8 result; never implicit fallback. |
| `TrackModuleCatalog` | Definition + parameters → analytic primitives, poses and local certificates. |
| `TrackRoomModel` | Versioned room recipe + seed + tier → canonical free space, regions and portals. |
| `TrackLayoutSolver` | Gameplay cycle constraints + room + route seed → instantiated closed analytic route or typed failure. |
| `TrackLayoutValidation` | Route + room + reservations → independent geometry/gameplay certificate or failures. |

`TrackBuilderCore.prepare_layout` remains the public preparation seam and the
scene builder remains downstream. The registry result adapts to existing
metadata keys while adding the explicit v8 fields in §5.3; no consumer should
need to know the solver's search tree to race a prepared layout.

## 2. Hard geometry contract

All distances are world units, after room sizing. Never scale road width,
vehicle hull, minimum radius or setup distance with tier.

| Requirement | Acceptance rule |
|---|---|
| One closed simple loop | Every section has one predecessor and successor; one connected cycle consumes all sections. Endpoint pose closes; continuous centerline has no crossing, retracing, nonadjacent touch or zero-length edge. Total signed tangent turn is ±2π. |
| Corridor half-width 125 | The swept nominal corridor is the curve's radius-125 neighborhood. Module mouths and all joins carry the full 250 width. Reserve 135 against room boundaries, retaining v7's extra 10-unit fitting margin. |
| Minimum turn radius 147 | Every analytic arc radius ≥147; lines have infinite radius; joins are G1, never angular corners. Initial catalog uses ≥180 for construction headroom. Final sampled-route radius check must also pass ≥147. |
| Self-distance ≥320 | For any two continuous points whose shorter cyclic arc separation is ≥960, distance ≥320. Also require a locally embedded width-250 tube and ≥320 between distinct return limbs, even when they are less than 960 apart in arc length. |
| Two setup straights ≥450 | Two distinct maximal straight regions, separated by a real turn, each contain an unmodified ≥450 interval. Preserve both literal heading tolerance ≤0.04 radians and setup chord/arc ratio ≥0.985 in the runtime samples. Splitting one line into two modules does not count twice. |
| Room fit | The entire reserved radius-135 sweep lies inside the outer polygon and outside all solid exclusions, including every edge of the EL notch. Vertex-only tests are insufficient. |
| Full-width passages | Every selected passage has a continuous radius-125 sweep clear of static collision; endpoints connect through full-width ports, with radius-valid bends. A point flood-fill or a 44-unit vehicle slit does not qualify. |

Self-distance cannot mean all pairs of adjacent points: arbitrarily close points
on one straight are necessarily less than 320 apart. The 960 local arc cutoff
is the existing `max(850, 3 * 320)` rule
(`scripts/race/track_seed_gen.gd:1293–1311`), made continuous rather than just
sample-to-sample. The extra return-limb/tube checks prevent hiding a squeezed
hairpin inside that exemption. A semicircular U connecting parallel limbs
needs `2r >= 320`, regardless of the 147 radius floor; construction radius 180
satisfies both. Do not inherit v7's physical-room clamp of requested separation
(`scripts/race/track_seed_gen.gd:185–190`): v8 rejects an infeasible room.

The return-limb check is global, not dependent on a module declaring itself a
hairpin: enumerate distinct-point stationary-distance pairs, where the joining
chord is perpendicular to both analytic tangents (including G1 join limits),
and require ≥320 there too. Exclude only the identical arc position, not all
pairs inside one module. Module limb annotations accelerate this test; they do
not exempt unannotated geometry.

No tolerance reduces these hard floors. Use conservative error bounds in
geometric comparisons; ambiguous contact fails closed. Existing whole-complex
bypass rejection stays (`scripts/race/track_seed_gen.gd:1159–1189`), in addition
to the requirements above. The nominal corridor is not a new invisible wall:
the room apron remains drivable where no visible solid exists.

## 3. Module catalog and connector contract

### 3.1 Data and pose

GURI-999 (Module catalog + connector contract) owns a small data-driven catalog
under `data/tracks/`, backed by pure geometry code under `scripts/race/`.
Follow the existing stateless section helpers and Resource-oriented data
convention; no scenes, textures, global RNG or editor dependency in the solver.

Each `TrackModuleDefinition` contains:

- Stable `id`, revision, semantic family and parameter domains; mirror/reverse
  transforms; allowed moment tags; analytic primitive recipe.
- Local entry pose `(x=0, y=0, heading=0)`, where +X is forward. Exit pose is
  **computed** from the chosen parameters, not approximated by a bounding box.
  A port includes tangent, left/right cross-section endpoints at ±125, width
  250, elevation 0, and support/surface continuity (no gap or jump).
- Exact length, signed turn and curvature bounds; maximal literal straight
  intervals; protected setup intervals; analytic radius-125/135 sweeps;
  return-limb pairs and their separation certificates. Bounds are functions of
  parameters, not one optimistic certificate for the entire parameter box.
- Optional keep-clear envelopes for gates, spawn grid and recovery lanes, and
  off-route sockets for story placement. These do not enlarge the driveable
  corridor or promise that a prop fits.

Compose poses as planar rigid transforms: `world_exit = world_entry * local_exit`.
Only translation, rotation and explicit mirroring are permitted; no anisotropic
warping or post-fit shrinking. Parameters may change only inside authored
domains, followed by recertification. Reverse swaps ports, reverses primitive
order and tangents, and exchanges opening/tightening corner semantics.

**Join tolerances:** position residual ≤0.01 units and wrapped heading residual
≤0.0001 radians, width difference ≤0.001; elevation exactly zero. These are
solver convergence checks, not permission to draw a tiny bridging kink. Rebuild
shared endpoints/tangents from one solved pose and recertify the final analytic
chain; if it cannot share an exact pose, reject. Curvature may step at a G1
line/arc or two-arc join; G2 smoothing is not required. Any future smoothing
must retain the geometry contract and gets a new generator revision.

### 3.2 Initial authored vocabulary

Notation: `S(l)` is a line ending at `(l,0,0)`. `A(r,a)` is a signed circular
arc; its local exit is `(r*sin(|a|), sign(a)*r*(1-cos(a)), a)`. Concatenation
uses pose multiplication; thus every compound below has a computable exit.
All values are initial v8 parameter domains, not claims of measured feasibility.
The solver chooses only subsets fitting room, length and moment budgets.

| ID / class | Recipe and domain | Exit / authored purpose |
|---|---|---|
| `straight_link` | `S(l)`, 180≤l≤2400 | `(l,0,0)`; ordinary connection, no guaranteed setup credit. Adjacent collinear links merge. |
| `straight_setup` | `S(l)`, 520≤l≤2400; finish instance l≥1000 | `(l,0,0)`; protected ≥450 interval. Finish has ≥450 on each side of checker; still only one maximal straight. |
| `corner_tight` | `A(r,a)`, 180≤r<260; abs(a) in {45°,90°,135°} | Arc exit; low-speed readable corner. |
| `corner_medium` | Same angles, 260≤r<520 | Arc exit; intermediate corner. |
| `corner_sweeper` | Same angles, 520≤r≤1000 | Arc exit; fast broad bend, not a setup straight. |
| `corner_opening` | `A(r1,a*f) A(r2,a*(1-f))`; 180≤r1<r2≤700, r2/r1≥1.25, f in {0.35,0.5,0.65}; same angles | Product of arc poses; decreasing curvature. |
| `corner_tightening` | Opening recipe with radii reversed | Product of arc poses; increasing curvature. |
| `u_return` | `A(r,±π)`, 180≤r≤520 | `(0,±2r,±π)`; return to an independently placed lane, not a mirrored whole layout. |
| `s_offset` | `A(r,a) S(d) A(r,-a)`, 180≤r≤520, abs(a) in {30°,45°,60°}, 180≤d≤900 | `(2r*sin(abs(a))+d*cos(a), sign(a)*(2r*(1-cos(a))+d*sin(abs(a))),0)`; diagonal/dogleg shift. |
| `chicane_return` | `A(r,a) A(r,-a) S(d) A(r,-a) A(r,a)`, 180≤r≤520, same angles, 180≤d≤900 | `(4r*sin(abs(a))+d,0,0)`; out-and-back excursion. Subject to bypass check; not merely a cosmetic wiggle. |
| `switchback` | `A(r,+90°) S(d1) A(r,-90°) S(w) A(r,-90°) S(d2) A(r,+90°)` and mirror; 180≤r≤360, 450≤d1,d2≤1600, 400≤w≤1200 | Pose product, net heading zero; independent depths and connector width. No forced paired teeth; validate each limb and full passage. |

There are **11 authored classes**. Handed copies, rotations, reverse traversal,
radius rolls and moment skins are not additional topologies. Everything is
elevation-free: the speed alternative to a jump is `straight_setup`, the
technical alternative to an overpass is a planar S/switchback, and a putative
crossing must route around reserved space or fail. No hidden z-order crossing.

Primitive recipes intrinsically enforce curvature and local tangent continuity.
Instantiation computes sweep/straight certificates; placement checks room and
other modules. Only complete-loop validation can prove closure, nonlocal
spacing, setup count and bypass absence. A valid isolated module does **not**
certify every combination of modules.

### 3.3 How much vocabulary does this create?

There is exactly **one unlabelled graph topology**, a simple cycle. The desired
variety is in section arrangements and their spatial embeddings. Unlike four
whole-program choices, a variable-length catalog has no fixed small ceiling on
such words; room area and tier budgets bound the accepted subset.

For a reproducible size illustration, consider eight cyclic slots choosing
straight / offset-S / return-chicane, ignoring parameters and hand. There are
`3^8 = 6561` ordered words and **498** after cyclic shift and reversal
equivalence (enumerate words, take the smallest rotation of word and reverse).
This is a **syntactic count only**, before adding the turning sections needed
for winding, closure, length, clearance and gameplay checks. It is not 498
playable compact circuits. Continuous deformations and renamed recipes add
zero to this count. The actual minimum accepted vocabulary is the per-cell
gate in §7, not an extrapolation of `M^k`.

Report two arrangement signatures. Expand compounds to their semantic turn and
straight structure, merge adjacent equivalent runs, and remove artificial
module splits. The **structural** signature retains turn-angle class, handed
order, return/offset arrangement and distinct straight regions, but drops
radii, lengths, IDs and moment tags. The **profile** signature additionally
retains tight/medium/sweeper/opening/tightening. Canonicalize rotations, mirror
(swap turn hands), reversal (also exchange opening/tightening), and their
combinations. Admission gates use structural signature plus shape, never the
seed-bearing `route_recipe` or profile bins alone. For structural tokens, merge
consecutive same-handed arcs with no intervening straight, even across module
boundaries; bin their summed absolute turn as (0°,60°), [60°,120°),
[120°,180°], or >180°. Merge collinear straight primitives before emitting S.
Use this expanded cyclic word for structural counts, so a hand-authored
switchback and the equivalent primitive composition cannot earn two entries.
Use the same expansion when reporting semantic section counts for §7; proposal
module budgets and measured section counts are deliberately different units.

## 4. Free-polygon room model

GURI-1000 (Free-polygon room model) supplies `TrackRoomModel`:

```text
recipe_id, recipe_revision, room_seed, tier, coordinate_scale, polygon_digest
outer: simple ordered PackedVector2Array
solid_exclusions: array of simple polygons (holes/immovable furniture)
regions: stable IDs + polygon masks + required visitation rules
portals: region pair + segment + clear-width interval + traversal capacity
free_components: eroded free-space components with containment hierarchy
reserved_passages: solved sweeps + full-width ports + owning route sections
```

Validate finite coordinates, winding, nonzero edges, simple boundary, disjoint
holes strictly inside the outer ring and no touching contours. Canonicalize
ring winding and starting vertex; sort holes by canonical coordinates. Keep
all components and hole ownership from boolean/offset operations. The v7
largest-contour helpers (`scripts/race/track_builder_geometry.gd:48–82,124–156`)
are unsuitable as a room representation: they can discard an arm or hole.

### 4.1 Room generation, not rectangular fitting

The six room keys remain recognizable **recipe families**, not six fixed
polygons. v7's exact four-/six-vertex polygons remain frozen
(`scripts/race/track_builder_catalog.gd:113–128`). v8 recipes author 2–4 usable
regions with independent leg dimensions and connected mouths, then union them
and vary supported boundary features: bevels, angled sides, asymmetric bays
and shallow concavities. Vertex noise alone does not count as room variety.

- `classic` / `square`: broad core with independently sized side bays and
  nonparallel/bevel alternatives; do not preserve rectangular route anchors.
- `wide` / `tall`: horizontally/vertically biased region chains, with unequal
  depths and optional offset end regions. Orientation is a room identity cue,
  not an instruction to rotate the same route template.
- `long`: elongated region chain with lateral pockets and at least one space
  for a turning/return envelope, not an arbitrarily thin scaled rectangle.
- `el`: two occupied arms connected around a real concave notch. The existing
  notch is the missing upper-right rectangle bounded by `(360,-60)` in the
  unscaled fixture (`scripts/race/track_builder_catalog.gd:117`). Import that
  polygon as a regression fixture; v8 varies both arm depths/lengths and notch
  offset independently. Both arms must carry ≥450 units of route beyond the
  shared junction **in every tier, including compact**. There is no arm-only
  fallback. Compact uses a compact two-arm recipe, not a giant L shrunk after
  route generation.

Keep tier length bands exactly as published
(`scripts/race/generated_circuit_rules.gd:19–24`). Use the old scaled room area
as an initial sizing budget, not as a final shape transform. Increase available
region area and module count together for larger tiers. Module counts start at
6–12 / 8–16 / 12–24 / 18–32 / 24–48 semantic modules for compact / standard /
long / endurance / marathon (before expanding compounds); these are proposal
budgets, not hard turn counts. Exact summed module lengths and reserved area
prune impossible combinations. Do not stretch a four-corner loop to 48k.
Any changes to these domains before rollout require fresh gate evidence.

### 4.2 Passability and placement

Define `F = outer minus solid_exclusions`. The centerline placement domain is
`E = erosion(F,135)` (erode the outer boundary and inflate each solid by 135).
Triangulate or convex-decompose each surviving component, retain adjacency, and annotate
shared portals with clearance and turning-envelope feasibility. Components
are not silently bridged. Connectivity of E is necessary, not sufficient for
a turning vehicle or two separated traversals.

A single passage needs width ≥250 (construction reservation 270). A neck used
twice by the simple cycle needs **two centerlines ≥320 apart**: minimum hard
width `125 + 320 + 125 = 570`, construction width `135 + 320 + 135 = 590`,
plus room for the chosen end-turn envelopes. Thus a 300-wide neck can admit
one car path but cannot be the only connection to a mandatory visited arm:
that arm requires entry and exit. Reserve two ordered portal lanes before
embedding either traversal. More traversals require `2*135 + (n-1)*320` and
explicit lane ordering; no crossing of connections inside a junction.

The 70-unit gap between two 250-wide corridors at separation 320 is **not**
another passage. Passage reservations describe the route's swept footprint
through infield space; no island rim, pocket seal, dressing or gate post may
fill that footprint. A feasible portal width alone does not guarantee a curved
module fits: test its full analytic sweep including bends and endpoints.

Placement uses the region graph to allocate cycle visits, oriented free-space
cells to propose entry poses, and exact boundary/sweep queries to accept them.
Use polygon area/portal constraints throughout, not a complete rectangle-fitted
route followed by a polygon rejection filter. Region connectivity is spatial
scaffolding, not a branching racing graph.

### 4.3 Carry the room through the runtime

The runtime must consume the same outer ring, solid exclusions and passage
reservations used by generation. The current scene builder assumes one inner
island (`scripts/race/track_builder_scene.gd:60–71`), creates outer walls from
polygon edges (`:80–92`), and seals pockets after story placement (`:160–166`).
For v8, subtract protected passage sweeps before deriving visible solid regions;
preserve multiple resulting pieces, never connect them with a bounding polygon.
Disable a pocket seal that intersects a reserved passage, not the passage.

Extend wall/floor rendering, island collision, placement queries and recovery
free-space membership to the full polygon-with-holes model. Keep the AABB only
for camera limits. Current recovery receives one `room_polygon` and one island
exclusion (`scripts/race/prototype_race.gd:559–562`); add multi-exclusion
membership before enabling holes. Geometry-only room fixtures can ship first, but runtime holes
cannot be advertised as supported until those consumers agree.

Gate rays currently consult only room + island and use a fixed 12000 reach
(`scripts/race/track_builder_nodes.gd:118–152`). v8 queries the nearest actual
solid boundary using room-bounds-derived reach. A gate's sensor must cross its
owned route section once, not a neighboring switchback limb; move its arc
position within its allocated region or reject the layout. Preserve legal
outer-apron detection, forward/reverse grid clearance and recovery envelopes.

## 5. Cyclic solver and loop closure

GURI-1001 (Cyclic layout solver + loop closure) is a pure deterministic search,
not a physics simulation or external optimizer dependency. It returns success
with a certificate, or a structured failure. It is deliberately bounded and
**not complete**: an exhausted search is not proof that a room has no solution.

### 5.1 Generate and embed

1. Resolve identity, room recipe, exact tier band and seed-stable family label.
   Generate the room independently of route search. Check region/portal
   feasibility before expensive placement. Do not mutate the room in response
   to a failed route; that would couple room identity to solver consumption.
2. Build a cyclic list of semantic slots with one predecessor/successor each.
   Reserve two distinct setup straights, finish in the longer one, a technical
   sequence and space for the existing story moments. Allocate a variable count
   from the tier budget. Signed turns must be capable of summing to ±360°.
   Insert mixed-handed sections, not just same-hand perimeter corners.
3. Map required region visits and portal traversals to consecutive slot ranges.
   EL's two arms are required; portal capacity must support leaving each visited
   arm. Choose a start pose inside a free-space cell, independent of a room
   corner. Reserve the finish straight, both approaches, grid and its closure
   neighborhood first.
4. Deterministic depth-first backtracking places a module at the current exit
   pose. Enumerate seeded module/parameter/pose options in stable order; prune
   radius, sweep/room containment, intersections, return-limb spacing, portal
   lane conflicts, setup destruction, and impossible remaining length/turn
   intervals. Use a segment/arc spatial hash for broad phase. Hard failures
   never enter a weighted aesthetic score.
5. Maintain remaining-length and closure-pose feasibility after every placement.
   Once only closure slots remain, solve them as below. A closed candidate then
   passes all of §5.3. Search a bounded set of feasible candidates, ranking soft
   targets seeded per identity: turn/straight mix, region occupancy, asymmetry,
   length proximity and moment spacing. Never rank against previously generated
   seeds at runtime; that would make generation order affect identity.

Make that enumeration finite: per module/slot, try the domain minimum,
midpoint and maximum legal parameter tuples, then five independently hashed
tuples (8 total; deduplicate). Sample listed angle/split choices discretely;
sample distances/radii on a 1/16-unit proposal grid. This is parameter selection,
not quantization of an already solved curve. At most eight initial entry poses
come from seeded triangle/region samples; subsequent entries are fixed by the
previous module's exit. Retry graph candidates change section order/count and
region allocation, not just dimensions. Stable score ties resolve by graph
candidate, start-pose index, then option indices; use fixed-point score bins
before tie-breaking. Pin ordering and scoring weights with the v8 release.

Initial deterministic work budget per request: at most 24 graph candidates,
2048 placement expansions per graph, 24 closure candidates per eligible frontier,
and two local repair passes per complete candidate. All consume an additional
shared cap of 50000 narrow-phase validation operations. Define one operation
as one primitive-pair or primitive-boundary interval query; recursive children
also consume it. Budget exhaustion returns `search_budget_exhausted` and the
stage/counters. Yielding to runtime loading stages may use wall time; accepted
output and stopping order may not. These are initial engineering limits to
profile, not a runtime-performance claim; freeze them with released v8.

### 5.2 Closure is a pose-and-space problem

Reserve 2–5 final semantic slots and a free-space lane back to the start port
**before** growing most of the loop. The lane is a sequence of convex free-space
cells/portals with enough capacity for a tube; it is kept unavailable to other
sections. It is not a promise that any final pose is closable. At each frontier,
use Euclidean distance as a safe lower length bound, remaining signed-turn
intervals and catalog length bounds to reject impossible returns. Do not use a
sampled reachability table as a proof of feasibility.

Use an explicit **forward-only arc/line pose connector**:

- At radii {180,240,360,520}, enumerate the six Dubins families LSL, RSR, LSR,
  RSL, LRL, RLR (L/R are circular arcs, S a straight). Compute tangent-circle
  solutions analytically between frontier and reserved start pose; reject
  degenerate, negative-length or out-of-domain solutions. Keep branches in a
  fixed family/radius order. Endpoint residuals must meet §3.1.
- Connector angles may be continuous rather than the catalog's ordinary angle
  menu; each arc is limited to ≤180°. No extra full revolution to consume
  length. Assign closure arcs to the same semantic classes/bins as ordinary
  geometry, not an unmeasured `magic_close` module.
- Test the **whole connector sweep** against the room, reserved lane and
  already placed sections. An obstacle-free Dubins solution does not establish
  obstacle-free room closure. Accept only winding ±360° with the preceding
  path, zero intersections and all spacing/straight/length rules satisfied.
- If no connector fits, backtrack the last ordinary modules (including their
  parameters and reserved-lane assignment). Do not append a straight chord,
  move the start, snap a gap, stretch the whole loop or reduce radius/width.
  This first solver need not solve every obstacle-constrained Dubins problem.

If closure is below the band floor, a repair may lengthen **unprotected** links
and re-solve the affected suffix, or replace a link with a certified offset/
return module whose endpoint contract fits. It must not consume protected
setup intervals. If above the ceiling, shorten only within domains and re-solve.
No arbitrary spline warp. Closing slots and accepted repairs enter the final
arrangement signature and all attempt/repair diagnostics.

### 5.3 Validation, representation and repair

Represent the authoritative route as an ordered analytic line/arc chain with
arc-length mapping. Do not send its sampled points back through Catmull–Rom:
the current sampler interpolates controls and changes geometry
(`scripts/race/track_curve_sampling.gd:13–51,55–89`). v7 keeps that sampler;
v8 evaluates its analytic route directly. `prepare_layout` selects the sample
path once; downstream consumers receive the committed result, not controls
that they reinterpret (`scripts/race/track_builder_core.gd:191,235,330–337`).

Validation stages, with first failure and offending section/edge IDs:

1. **Analytic:** finite parameters, shared port poses, primitive lengths,
   winding, exact radius bounds, straight intervals and continuous simple-loop
   intersection checks (line/line, line/arc, arc/arc including tangencies).
2. **Clearance:** exact primitive-to-boundary and primitive-pair distances, or
   conservative interval subdivision with error certificates. For the 960-arc
   exclusion, split parameter domains at the cyclic arc boundary rather than
   exempting whole long primitives. Subdivide ambiguous intervals until proven
   safe/unsafe; numerical/work-limit ambiguity rejects. Check both radius-135
   room containment and locally injective radius-125 offsets. Retain hole and
   component containment; never certify just offset vertices.
3. **Runtime samples:** at least 260 samples, maximum arc step 35, and adaptive
   arc subdivision with chord deviation ≤0.25 units. Keep primitive boundaries
   and protected straight endpoints. Use conservative sweep inflation by the
   known approximation error when testing polyline-based consumers. Sampling
   may add points, but cannot smooth, cut corners or reduce safety floors.
4. **Existing gameplay validation:** introduce a centerline-validation seam
   carrying the current checks in `scripts/race/track_seed_gen.gd:871–931`, with
   an unchanged v7 controls wrapper. v8 runs it on its actual samples with explicit 320 and
   both tier length bounds, plus analytic certificates. Preserve radius,
   setup/literal-straight and bypass checks. Revalidate after choosing the
   finish seam; reordering must not change geometry.
5. **Assembled layout:** final room solids, island rims, posts, scenery and
   static hazards cannot intersect protected passage sweeps or setup/grid/gate
   reservations. Safe/shortcut AI lines retain the 22-unit swept-hull clearance.
   Dynamic conflict moments stay outside protected passages/setups and retain
   their existing gameplay behavior; this is not a claim of collision-free
   driving through active hazards. Full-width static infield clearance is
   stricter than the obstacle planner's current 70.4-unit viable-width check
   (`scripts/race/track_builder_planner.gd:8–10,63–76`).

Repairs are limited to changing offending local parameters, re-solving a
suffix, replacing a compatible module, or removing/repositioning optional
dressing. Log before/after certificates and rerun whole-loop checks. Never
repair by dropping a hole/arm, clipping road width, deleting required moments
or manufacturing invisible collision. Required geometry that cannot be repaired
rejects the candidate; optional WFC/dressing failure may fall back to empty fill.

`GenerationResult` contains requested seed/version/room digest, gameplay cycle,
instantiated modules and poses, analytic route, samples, passage/keep-clear
reservations, structural/profile signatures, metrics, deterministic operation
counts, attempts/rejections and repair log. Timing is diagnostics only and is
excluded from fingerprints. Failure returns a reason, not an empty valid loop.

## 6. Strangler path, determinism and identity

### 6.1 Preserve v7; don't merely bump a constant

Add a small generator registry with explicit support for `(schema=1,
generator=7)` and `(schema=2,generator=8)`. Existing APIs default to v7 during
development. Opt-in v8 is explicit in the identity/options, never inferred from
room, tier, seed or an already-loaded cache entry. Leave `TrackSeedGen` and its
grammar as the legacy implementation; no monolithic rewrite or template bridge
that silently changes v7 output.

Preserving old identities is the compatibility policy of this design: v7
shares, favorites, history and in-progress championships stay v7. Versions ≤6
remain explicitly unsupported, as tested today; this does not promise to
reconstruct unavailable historical generators. Negative-seed authored fixtures
remain on their existing path. No automatic migration of records or lap times.

Required integration work before v8 activation:

- Version-aware `normalize`, `create`, event conversion, generation options,
  fingerprints and codecs. Today they embed global constants
  (`scripts/race/generated_circuit_identity.gd:118–143,268–278,281–327,363–382`).
  Unknown schema/generator/recipe must return a specific unsupported error;
  malformed payloads must not fall back to a new identity.
  In particular, replace the runtime options fallback that currently accepts
  sub-seeds after identity normalization fails
  (`scripts/race/prototype_race.gd:513–529`); a versioned request must not slip
  into default legacy generation with only its seeds preserved.
- Preserve PC1 serialization and fingerprints byte-for-byte, including enum
  order and domain seed values. Freeze the pinned v7 identity fixture
  (`tests/generated_circuit_identity_test.gd:15–35`) and extend generator
  fingerprints across **all tiers**; the existing benchmark is standard-only
  (`tests/track_seed_gen_benchmark.gd:40–51,75–103,106–121`). Diagnostics must
  not alter RNG consumption or the legacy fingerprint payload.
- Preserve saved championship versions. Its current mismatch path recreates
  events under the newest version
  (`scripts/progression/championship_circuit_identity.gd:64–85`); dispatch
  normalization by stored version instead. Library normalization silently drops
  identities rejected by `normalize`
  (`scripts/persistence/circuit_library.gd:54–67`), so mixed-v7/v8 persistence
  tests are required before a default-version switch.
- Preview and loaded scene use the same dispatch, room model and route digest.
  The current preview fingerprint samples only about 64 positions
  (`scripts/race/circuit_route_preview.gd:39–57`); retain it for v7, use the
  canonical analytic route + room digest for v8, and compare prepared/runtime
  samples separately. Namespace any preview/prepared-layout cache by complete
  identity, geometry version and room recipe digest, not bare seed.

### 6.2 Schema 2 room identity and seeds

Initial PC2 supports **seeded catalog room recipes**, not arbitrary player
polygon uploads. Its payload extends the PC1 fields with immutable numeric
`room_recipe_id`, `room_recipe_revision` and a 31-bit `room_geometry_seed`;
its prefix is PC2, checksum remains four SHA-256 bytes and strict trailing-data
validation remains. Keep recipe IDs/revisions byte-sized initially and fail
explicitly on exhaustion rather than reuse an ID. The old six room enum values
remain families. Generator version freezes the module catalog, solver budgets,
metric-independent selection policy and numerical contract; changing any
seed-affecting behavior after release requires another generator version.

PC2 byte order: existing six-byte generator/theme/room/reverse/danger/tier
header, recipe ID byte, recipe revision byte, room geometry seed as u32
big-endian, then the six existing u32 sub-seeds, the existing length-prefixed
material/palette strings, and checksum. Preserve PC1's decoder independently.
Derive the default room geometry seed from `room_composition` in a dedicated
v8 domain; explicitly supplied room seeds round-trip. Validate that the recipe
belongs to the encoded room family; tier sizes that recipe without altering
its seed. Do not infer a different room family from polygon aspect.

Canonical identity hashes include schema/generator, recipe ID/revision, room
geometry seed, tier, theme, direction and all existing composition domains.
Room polygon digest hashes canonical coordinates on a documented 1/16-unit
room-construction grid; query geometry uses those exact realized coordinates.
Store the digest with generated output and test it against reconstruction. Do
not quantize an analytic route after validation. Future externally authored
polygons require a new payload mode containing canonical geometry or an
immutable resolvable content ID; a hash alone cannot reconstruct a room.

Keep the requested route seed immutable. Derive named substreams for room,
graph candidate, module slot, placement, closure, repair and fill using a frozen
SHA-256 encoding of length-prefixed UTF-8 domain strings and big-endian integer
fields (u16 byte lengths, u32 integer fields in a version-pinned field order).
Take the first four digest bytes big-endian, masked with `0x7fffffff`, for each
draw; rejection sampling handles
bounded integer choices without modulo bias. Index draws by stable semantic
slot/attempt, not mutable array enumeration or global RNG state. Family and
target-length selection stay independent from room and dressing. Mirroring and
reverse cannot masquerade as new arrangements.

No wall-clock cutoffs, unsorted dictionary iteration, race between parallel
workers, or mutable runtime novelty archive in acceptance. Pin Godot 4.7.2 and
the v8 numeric/geometry implementation; verify cold/warm cache, repeated-process
and reordered/sharded farms on supported platforms. A custom hash stream alone
does not make floating-point booleans/trigonometry cross-platform deterministic:
cross-platform digest fixtures are a release gate. Engine upgrades require
compatibility verification or an explicit new version, not a promise based on
Godot RNG internals.

### 6.3 Failure and local WFC

While experimental, v8 failure reports its actual identity and bounded-search
reason. Do not regenerate the neighboring seed or return v7 geometry wearing a
v8 identity. Production stays on v7 until v8's release gates pass. If v8 later
fails, return a retryable preparation error for that identity; any user-selected
legacy circuit is a separate v7 request, not silent fallback.

WFC is optional and comes last. It may select non-colliding surface visuals or
dressing inside allocated off-route pockets, with boundary ports and occupancy
masks fixed by the committed layout. It cannot place a new racing connection,
close the loop, move ports, change surface physics, shrink a corridor, seal a
passage or alter required collision boundaries. Collision-bearing tiles must
have authored footprint envelopes wholly outside passage/setup/gate/recovery
reservations; boundary cells are pinned, not merely assigned friendly weights.

Guarantee passability by testing the union of actual placed solid footprints
against the committed swept corridors and AI hull sweeps, then full-width
connectivity across every selected portal in both directions. Flood-fill of
un-inflated tiles is only a debug aid. WFC has a separate named stream and
bounded backtracking; contradiction means deterministic empty/safe dressing in
that pocket, not a route reroll. Revalidate after fill. Existing authored story
placement is sufficient for the initial v8 release; WFC adds no topology credit.

## 7. Expressive-range gate and affordable verification

### 7.1 Extend the existing harness, not a parallel source of truth

`tests/track_diversity_sweep_test.gd:29–50,62–119,145–175,203–208` already covers
all six rooms × five tiers, validates outputs and produces deterministic
shape clusters. Its current default is **4 seeds/cell, 120 generations, 174 s**;
12/cell took 530 s. Low diversity is currently diagnostic, not a failing gate
(`:23`). Preserve that historical v7 mode and marker; do not pretend four
samples establish an expressive range.

Add validated selectors for generator, seed start, seed count (retain 1..200),
room/tier cell and farm shard; proposed names are `PC_DIVERSITY_GENERATOR`,
`PC_DIVERSITY_START`, `PC_DIVERSITY_CELL`, `PC_DIVERSITY_SHARD` plus existing
`PC_DIVERSITY_SEEDS`. These selectors **do not exist yet**. v8 goes through the
same room/generation dispatch as `prepare_layout`, not a test-only rectangular
parameter reconstruction. Generate once per case, cache analytic/sampled
features in memory, and independently validate the returned geometry without
calling generation again. Persist per-case JSON records for offline aggregation.

Records include full identity and room digest, status and all rejection classes,
structural/profile signatures, primitive/semantic counts, signed turn runs,
literal/setup counts, curvature-class histogram, length, region occupancy,
portal traversals/minimum widths, shape descriptor, repair/expansion counts,
stage times and output digest. Never omit failures from denominators. Keep
seq/rhythm columns for comparison but not as macro-topology gates.

Retain 128-point centroid/RMS normalization, transform equivalence and distance
threshold 0.055 (`tests/track_diversity_sweep_test.gd:227–274`); additionally
retain module-level features to detect local differences that resampling misses.
Merge shards by sorting complete records by cell then ascending seed **before**
greedy clustering. Summing shard cluster counts is invalid. Test missing cases,
duplicate identities, bad selectors and mismatched versions as farm errors.

### 7.2 Required thresholds (targets, not measured results)

Run fixed windows **0–47** and **100000–100047** separately in every cell:
2880 cases total. Both windows must independently pass the following; no
averaging EL/compact deficiencies into other rooms. Thresholds are initial
release requirements, not confidence intervals or claims about all 2³¹ seeds.

| Per-cell requirement, each 48-seed window | Compact | Standard | Long | Endurance | Marathon |
|---|---:|---:|---:|---:|---:|
| Nonempty, identity-correct, invariant-valid output | 48/48 | 48/48 | 48/48 | 48/48 | 48/48 |
| Distinct structural arrangements | ≥8 | ≥12 | ≥16 | ≥18 | ≥20 |
| Distinct normalized shape clusters | ≥12 | ≥20 | ≥24 | ≥26 | ≥28 |
| Largest arrangement's frequency | ≤12 | ≤10 | ≤8 | ≤8 | ≤8 |
| Distinct semantic section counts | ≥3 | ≥3 | ≥4 | ≥4 | ≥4 |
| Routes with both turn hands | ≥36 | ≥36 | ≥40 | ≥40 | ≥40 |

Additional all-tier gates:

- Zero silent seed changes, v7 substitutions, weakened constraints or exceeded
  operation caps. At most 12/48 candidates needing a complete-layout repair;
  report backtracking separately so it cannot hide as a repair success metric.
- Every output has two literal/setup straights and the entire selected tier
  band; every EL output meets the two-arm requirement. Every selected passage
  is full-width in the **assembled** collision model on integration fixtures.
- At least 3 populated curvature classes per cell and at least 3 occupied bins
  of `(semantic-count, straight-length fraction)` jointly: count bins 6–11,
  12–17, 18–23, 24+; fraction bins <0.35, 0.35–0.55, >0.55. This avoids buying
  uniqueness solely by tiny parameter differences. Catalog IDs are not bins.
- The room generator itself yields ≥3 normalized boundary-shape clusters per
  cell (same 128-point/0.055 method on outer rings); report notch/portal
  descriptors separately. At least three populated room clusters must each host
  ≥2 route structural arrangements in the window; report singleton outliers
  rather than forbidding them. No one-room-per-route hard-coded pairing.
- After a v8 baseline is approved, fixed-window arrangement and shape counts
  may not fall by more than 10% (rounded down loss) in any cell and must still
  exceed the absolute floors. A proposed new version publishes both tables;
  never overwrite the baseline or lower thresholds just to turn CI green.

Use a separately committed, reproducible shuffled holdout of 200 seeds per cell
(6000 cases) before activation and for scheduled QA. Choose/store the holdout
list before tuning, with no overlap with development windows. Require zero
invalid/empty/identity-drift cases; apply the same distinct-arrangement and
shape floors to each of four sorted, disjoint 48-case holdout blocks, and
validate the remaining eight. Archive smallest/largest, slowest, repaired,
most similar and least occupied cases. Make every failure a regression fixture,
not a seed exception. Numerical gates complement, not replace, operator review
of one shape-cluster medoid and pathological outliers in each cell.

### 7.3 CI cost and runtime gates

| Lane | Work / budget policy |
|---|---|
| Doc-only change | Source/reference review and `git diff --check`; no geometry claim, no 174-second rerun needed. |
| Fast geometry changes | Contract/connector fixtures, v7 identity pins, and a deterministic 30-cell single-seed v8 smoke including EL/compact and long/compact regressions. Target ≤60 s on a measured isolated reference worker; it proves safety, not statistical variety. |
| Release suite | Keep the 4-seed/cell v7 sweep as the default during migration; add a bounded v8 smoke. Do not silently double all farms in every `tests/*.gd` invocation. Full release suite stays in CI. |
| Scheduled / explicit pre-activation QA | 48-seed fixed windows plus holdout farm, sharded by cell/window in isolated Godot processes, aggregate once; run full expressive gates here. |

The current release runner auto-discovers `tests/*.gd`, isolates process user
data and allows 1200 s/test (`tools/build_release.sh:117–154`); PR smoke is cheap
per `AGENTS.md:46–50`. Keep expensive farm orchestration opt-in outside automatic
test discovery. Large windows must not become a hidden default. At the baseline
rate the 2880-case farm alone is roughly 70 minutes serial **before** extra
clustering/solver costs; 6000 cases exceed two hours. More samples make greedy
shape comparison superlinear, so benchmark aggregation separately. Use bounded
parallelism, cached features and broad-phase geometry, not skipped validators.

Measure p50/p95/max generation, validation and aggregation separately on an
isolated fixed worker. Before enabling v8, require per-cell generation p95 no
more than 2× a freshly measured v7 p95 on the same 48-seed window/worker; retain
the existing race-start responsiveness gate too. Farm shard target ≤15 minutes,
hard timeout 1200 s; if exceeded, reduce shard size, not seed coverage. Wall
time is a QA gate only, never a different geometry-selection path.

Geometry release verification extends existing seed, section, variety,
length-profile, identity/share, championship/library, composition, collision,
generated-runtime and racing tests. Add negative fixtures for a notch crossing
between valid vertices, split erosion components, a 569-wide two-pass neck,
near-seam intersection, sub-147 radius, sub-450 straight, sub-320 return limbs,
closure failure, lost hole, gate crossing two limbs and WFC passage obstruction.
Include exact-boundary positives and mirror/reverse/cyclic/scale-equivalence
metric fixtures; scale equivalence is a measurement transform, not legal road
rescaling.

Run four-car forward/reverse QA on all 30 room/tier cells, cycling all themes,
with representative tight/repair/closure outliers. Require legal ordered laps,
zero DNF on those release fixtures, and ≤3 recoveries/car; lap-time ceilings
must be tier-specific, not the compact/standard limits blindly applied to
marathon. Expand the harness first: the current large-tier mode is only one
wide-room case (`tests/ai_seed_sweep_test.gd:67–79`), not all-cell evidence.
No switch to v8 until final collision and physics checks pass as well as the
geometry farm.

## 8. Ordered, independently shippable implementation

Each row can merge with shipping generation still v7. Experimental v8 remains
explicitly opt-in until the final activation; do not accumulate an untestable
big-bang replacement. Scope and seed impact are part of each acceptance step.

| Step | Tracer bullet / acceptance | Risk | Existing seeds |
|---|---|---|---|
| 1. Observe and pin | Add per-attempt rejection categories without RNG changes; extend benchmark to tiers; pin PC1 shares, v7 route digests and prepared/preview agreement. Add the new farm's output/aggregation plumbing without enforcing v8 targets on v7. | Low: instrumentation can alter ordering if careless. | Must remain byte-identical; no new default. |
| 2. Version boundary | Add registry and schema-aware normalization/options, PC1/v7 frozen path and explicit unsupported errors. Exercise mixed-version library/championship persistence with a test-only v8 stub that fails explicitly. | Medium: persistence is more than changing `GENERATOR_VERSION`. | All v7 records preserved; ≤6 still unsupported; no auto-migration. |
| 3. Catalog kernel | GURI-999 (Module catalog + connector contract): analytic lines/arcs, ports, sweeps and fixtures. One hand-composed closed loop with two setup straights passes continuous and sampled validators. Render/drive it only as an opt-in development fixture. | Medium: robust clearance and port seams. | No change; no public v8 share codes yet. |
| 4. Room queries | GURI-1000 (Free-polygon room model): import six legacy polygons as fixtures, test holes/erosion/590-wide two-lane portals and notch; place the catalog fixture in a concave room without AABB fitting. Add polygon recipes independently. | High: offset components/holes and compact EL space budget. | v7 frozen; candidate v8 room recipes may still change. |
| 5. First solved lap | GURI-1001 (Cyclic layout solver + loop closure): graph/region assignment, bounded backtracking and analytic closure; headless generation plus plain runtime lap in classic/standard and EL/compact. Failure must be bounded and reproducible. | High: closure search/feasibility and performance. | v7 unchanged; experimental v8 outputs not compatibility promises. |
| 6. Runtime contract | Adapt `prepare_layout` to analytic samples; carry exclusions/reservations through floor, island, walls, posts, recovery, story planner and gates. Verify a full dressed forward/reverse four-car lap on the same two cases. | High: valid geometry can become blocked by assembly. | v7 branch and authored fixtures unchanged; v8 explicit only. |
| 7. All-cell expressive range | Complete variable section/region budgets and all 11 classes; every room/tier runs both windows, holdout, physics coverage and visual review. Fix bottlenecks with module/placement changes, not relaxed invariants or more whole-route templates. | High: compact feasibility, runtime, distribution collapse. | No v7 changes. Freeze v8 catalog/recipes/solver only after gates pass. |
| 8. Publish v8 identity, then activate | Finalize PC2 round trips, cross-platform digests, library/championship retention and cache namespaces. Enable new Quick Race/new-championship identities after operator acceptance. Rollback changes only new-request default, not stored v8 dispatch. | Medium: release/version ownership. | New requests may differ; existing v7 and already-issued v8 identities keep their geometry. |
| 9. Optional fill | Separate, nonessential local WFC pockets with blocked-passage/contradiction tests and independent seeds; compare route/room digests before and after. | Low topology risk, medium collision risk. | Route unchanged. If gameplay collision/composition changes, version that identity domain explicitly; do not invalidate old records silently. |

### Approval boundaries and unresolved evidence

No unresolved product question blocks the first seven steps: retain v7, use a
new opt-in path, preserve all safety floors, and cover every room/tier. **Fran's
approval is required to activate v8 as the new-request default**, after reviewing
the gate artifacts and playable fixtures; this document does not authorize
retiring v7 support or migrating stored circuits. Arbitrary polygon sharing and
elevation remain out of scope, not unanswered implementation choices.

The unproven engineering questions are whether compact two-arm EL meets its
length band with enough arrangements, whether bounded closure reaches the
per-cell floors, and whether continuous validation stays within the measured
runtime budgets. Steps 4–7 resolve these with evidence. If they fail, keep v7
shipping and revise the proposed catalog/search/room budgets openly; do not
weaken invariants or call an incomplete experimental path a release.

## 9. References and verification of this design

Repository evidence was read at `451feeb`, including the baseline, standing
constraints, design-spec §§11 and 59–60, generator, section/grammar/sampling
code, room catalog, builder geometry/scene/planner/gates, identity/preview/
championship/library code, sweep, benchmark, identity tests and release runner.
The 498-word combinatorial example was checked by exhaustive ternary-word
enumeration with cyclic/reversal canonicalization. No v8 implementation,
measured v8 expressive-range result or continuous proof for v7 is claimed.

Primary documentation checked 2026-09-21 (upstream current sources; engine stays
pinned to project 4.7.2, not upstream master):

- [Godot Geometry2D API source](https://github.com/godotengine/godot/blob/master/doc/classes/Geometry2D.xml):
  negative polygon offset erodes; results may contain multiple components and
  holes. This motivates explicit containment handling, not largest-piece loss.
- [Godot RandomNumberGenerator API source](https://github.com/godotengine/godot/blob/master/doc/classes/RandomNumberGenerator.xml):
  its underlying algorithm is an implementation detail. Do not promise long-term
  seed stability from that implementation alone.
- [WaveFunctionCollapse reference implementation](https://github.com/mxgmn/WaveFunctionCollapse):
  local pattern constraints can contradict and general satisfiability is hard;
  local fill is bounded and may fail without touching the committed gameplay loop.

Doc-only verification is source/contract review and `git diff --check`.
Implementation must supply the concrete tests and farm evidence specified above.
