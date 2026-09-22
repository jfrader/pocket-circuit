# Pocket Circuit — generated-layout variety: handoff

**Read this first, then `docs/track-generator-architecture.md` (the spec) and
`docs/track-layout-variety-baseline.md` (the v7 baseline).**

- Repo: `~/Workspace/pocket-circuit` (main clone, currently on `dev`).
- Work happens in the worktree: `~/Workspace/Worktrees/pocket-circuit-guri-928`
- Branch: `jfrader/guri-928-layout-variety`, **HEAD `c44ed09`**, local (not pushed).
- Godot: `/usr/bin/godot` (4.7.2.stable, arch_linux). The worktree carries the
  vendored Gamestruments addon, so the live engine works there.
- Untracked `.uid` files in the worktree are expected local state — ignore them.
- Uncommitted at handoff: `tests/support/v8_holdout_seeds.gd` (a holdout fixture
  someone started; review, finish or delete before committing).

## Goal

Genuinely varied generated layouts across **every** room shape and **every**
length tier. Not marathon-specific. Standing rule from Fran: **never patch a
symptom — prefer the clean, general, consistent fix; replace a special-case
path rather than extending it.** v7 (the current generator) keeps shipping; the
new path (`v8`) is explicitly opt-in until Fran approves activation.

## Target architecture (decided, in the spec)

`playout graph -> spatial topology -> geometric layout -> local fill`:
graph-first authored **modules + connectors** composed into a closed cyclic
route graph, **free-polygon rooms**, WFC only for local fill, keep the
validation layer. Hard invariants any layout must hold:

- closed simple loop; corridor half-width 125; min turn radius 147;
  self-distance >= 320; at least 2 setup straights >= 450; no self-crossing;
  fits the room polygon including the `el` notch; full-width infield passages.

The 9 implementation steps and their acceptance are in the spec, section 8.

## Status: Steps 1–6 complete, Step 7 mostly done

Commits on the branch (oldest first):

```
451feeb  Step 0  generated-layout variety baseline + 30-cell sweep
2e7d407  Step 0  graph-first generator architecture spec
e6cce04  Step 1  observe and pin (rejection categories, all-tier benchmark,
                  PC1 shares / v7 route digests / prepared-preview guards)
45cbb24  Step 2  version boundary (registry, explicit schema dispatch, v7 frozen,
                  unsupported versions fail explicitly, failing v8 stub)
2461921  Step 3  v8 catalog kernel (analytic modules/ports/sweeps + validators)
e88c3e3  Step 4  free-polygon room queries (six legacy polygons round-trip,
                  holes/erosion/590 portals/EL notch, concave placement)
7344396  Step 5  first solved v8 laps (cyclic solver + Dubins closure, drivable)
a7a0cba  Step 6a prepare_layout consumes v8 analytic samples + room model
4e5e9f7  Step 6b-1 placement rejects reserved-passage / exclusion intersections
00826f1  Step 6b-2 story threads room_model into placement calls
4bb5d72  Step 6b-3 core flows the real v8 room_model into assembly
5e3658e  Step 6b-4 island-rim landmarks + gate posts respect the model
3c5771f  Step 6b-5 edge/apron decor respects the model
f96fb68  Step 6c dressed 4-car lap test (+ planner obstacle clearance fix)
18c6aa9  Step 7   canonical primitive signatures in the diversity harness
4ac4b33  Step 7   general module proposals + corrected suffix search budgets
8525f7d  Step 7   region/length-budget cycle construction (general graph builder)
f307f24  Step 7   budget excursions, portal counts from traversal, all 11 classes
93c5da2  Step 7   reserve junction space for legal turn/link envelopes
0784a24  Step 7   diversify accepted region compositions + class coverage
c44ed09  Step 7   vary technical sections within accepted region cycles
```

Measured at `c44ed09`:

- **120/120** room × tier cells generate (4 seeds each), **0 invalid**.
- **360/360** layouts accepted at **12 seeds/cell**; every cell has >= 2 shape
  clusters and >= 2 structural signatures; **all 11 module classes occur in
  accepted layouts**.
- Dressed 4-car laps (classic/standard seed 928, el/compact seed 1001, forward
  and reverse): **0 recoveries, 0 blocked passages**.
- v7 byte-identical throughout: the five pinned v7 route SHA-256 digests and the
  PC1 share fixture in `tests/generated_circuit_identity_test.gd` still pass.
- Coverage JSON from the last run: `/tmp/opencode/step7-cov2.json`.

Per-cell distinct shapes / structural signatures at 12 seeds (from the spec run):

| Room | Compact | Standard | Long | Endurance | Marathon |
|---|---:|---:|---:|---:|---:|
| classic | 5/6 | 5/6 | 5/7 | 7/6 | 9/9 |
| wide | 4/5 | 6/5 | 6/9 | 7/7 | 7/5 |
| tall | 3/5 | 4/3 | 4/3 | 11/6 | 11/10 |
| long | 5/5 | 5/7 | 7/7 | 6/10 | 8/9 |
| square | 4/6 | 5/6 | 6/7 | 8/6 | 9/8 |
| el | 3/2 | 3/3 | 6/8 | 7/7 | 11/8 |

## What remains

Step 7 is **not** finished to the spec's gate. See spec sections 7 and 8.

1. **Pin the holdout fixture first** (commit it before any tuning; there is a
   start at `tests/support/v8_holdout_seeds.gd`).
2. **Implement the full Section 7 gate**: the current
   `tests/track_diversity_sweep_test.gd` only requires 2 shapes / 2 structures
   for windows >= 12 seeds — not the spec's tier-specific floors.
3. **Run both documented seed windows and the holdout** across all 30 cells
   (the spec's section 7 defines the windows; a 48-seed run is slow — the
   12-seed run already takes ~11m34s). Fix any cell that misses its floor
   **structurally** (region/portal budgets, selection, optional-region routing);
   never relax an invariant or special-case a room/seed.
4. **Optional-region routing**: v8 currently selects required regions only, and
   portals are capacity 2 (620/660 units wide; four traversals would need
   ~1230 before turn envelopes). Either implement optional-region routing
   generally, or document the arithmetic cap and keep the gate green. Do not
   widen rooms ad hoc.
5. **Strengthen the dressed test**: it covers only two room/tier cells and its
   PASS only checks the first AI finishing, not the whole 4-car field.
6. **All-cell physics coverage + visual review.**
7. **Step 8**: publish v8 identity (PC2), cross-platform digests, library /
   championship retention, cache namespaces; then **activation is Fran's
   approval only**.
8. **Step 9 (optional)**: local WFC fill pockets, independent seeds, with
   route/room digests compared before and after.

## How to run things

```bash
# worktree, one-time import if .godot is missing
godot --headless --path . --editor --import --quit

# the seven regression tests
for t in track_layout_solver_test v8_plain_runtime_lap_test v8_dressed_runtime_lap_test \
         track_room_model_test track_catalog_kernel_test track_generator_registry_test \
         generated_circuit_identity_test; do
  godot --headless --path . --script "res://tests/$t.gd"
done

# v8 all-cell coverage (writes JSON); watch the runtime — 12 seeds already ~11.5 min
PC_DIVERSITY_GENERATOR=8 PC_DIVERSITY_SEEDS=12 \
  PC_DIVERSITY_OUTPUT=/tmp/opencode/step7-cov.json \
  godot --headless --path . --script res://tests/track_diversity_sweep_test.gd
```

The v7 default sweep (no `PC_DIVERSITY_GENERATOR`) must stay at
`120 cases, 105 shape clusters, 0 failures`.

## Key files (in the worktree)

- Spec + baseline: `docs/track-generator-architecture.md`,
  `docs/track-layout-variety-baseline.md`
- v8 path: `scripts/race/track_layout_graph.gd`,
  `scripts/race/track_layout_solver.gd`, `scripts/race/track_room_model.gd`,
  `scripts/race/track_module_catalog.gd`,
  `scripts/race/track_v8_development_generator.gd`,
  `scripts/race/track_layout_validation.gd`,
  `data/tracks/v8_module_catalog.gd`, `data/tracks/v8_room_recipes.gd`
- Step 2 boundary: `scripts/race/track_generator_registry.gd`,
  `scripts/race/generated_circuit_identity.gd`
- Builder threading: `scripts/race/track_builder_{core,scene,nodes,island,story,placement,planner,dressing}.gd`
- Tests: `tests/track_generation_observability_test.gd`,
  `tests/track_catalog_kernel_test.gd`, `tests/track_room_model_test.gd`,
  `tests/track_layout_solver_test.gd`, `tests/v8_plain_runtime_lap_test.gd`,
  `tests/v8_dressed_runtime_lap_test.gd`, `tests/track_generator_registry_test.gd`,
  `tests/track_diversity_sweep_test.gd`,
  `tests/generated_circuit_identity_test.gd`

## Gotchas

- **Never leave a non-compiling tree.** Commit per slice; if a slice can't be
  finished, `git checkout -- .` it.
- The v7 generator, grammar, identity and the five digest fixtures must not
  change — verify with `generated_circuit_identity_test.gd` after every slice.
- v8 is opt-in via schema/version; the default stays v7.
- The `el`/`tex` obstacle planner now skips one obstacle on tight cells to keep
  the racing tube clear — accepted trade-off, not a bug.
- Godot prints non-fatal UID/asset warnings and an ObjectDB leak warning at
  shutdown; they are pre-existing.
- Use the `stalberg-pcg` skill for the PCG doctrine, and `godot-dev` for
  editor/scene work.

## Also true at handoff (related, separate)

- Gamestruments music/engine work is shipped: 1.0.4 released, vendored into
  Pocket Circuit; the music per-circuit work is merged to Pocket Circuit `dev`.
- Pocket Circuit `dev` is ~26 commits ahead of `main`; promotion to `main` is
  Fran's release call and has not been done.
