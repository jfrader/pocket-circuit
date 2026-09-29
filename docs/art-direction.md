# Pocket Circuit Art Direction

## Visual Thesis

Tiny toy cars race through a warm, painted household. Environment art uses
orthographic overhead silhouettes, broad gouache-like material tones, colored
edges and quiet texture. Kitchen, Workshop and Office share that treatment but
have distinct materials, palettes and household stories.

This is a top-down 2D game. Cars remain crisp and readable at roughly 32–55 pixels
on screen. Vehicle art, portraits and HUD keep their existing production
treatment; environment regeneration does not redraw or resize the cars.

Everything is original. The project uses genre principles from Micro Machines,
Toybox Turbos, Mini Motor Racing and Circuit Superstars without copying their
vehicles, characters, branding, tracks or interface designs.

## Environment Art Contract

`data/world_prop_art.json` is the authoritative environment catalog. Its
`overhead_gouache_v1` entries describe source cells or approved-source reuse,
theme membership, roles, physical dimensions, scale/detail tiers, visual weight,
placement zones and clearance, repetition, collision and shadow behavior.

- **Perspective:** camera directly overhead. Cups have circular mouths; keyboards,
  cartons and appliances show their tops, not front-facing illustrations.
- **Contours:** edges use darker local material colors. Do not add a uniform
  black contour, a white sticker border or the rejected cel-palette filter.
- **Values:** broad material masses carry recognition. Small scratches and grain
  remain subordinate to the object, the racing line and the cars.
- **Light:** warm upper-left highlights and soft down-right contact shadows.
  Shadows follow physical footprints; they do not become oversized grey cards.
- **Materials:** wood, ceramic, matte metal, cloth, cork, paper and food retain
  recognizable surface cues without photorealism or glossy room reflections.
- **Scale:** one world unit is one millimetre. Both axes derive from visible alpha
  bounds at the collision threshold, not from transparent canvas padding.
  A tablespoon is 180 units long, a nail 40 and a keyboard 440. Placement changes
  the chosen object or location rather than shrinking an object to fit.
- **Collision:** raised scenery has visible, footprint-backed collision. Alpha
  props derive convex shapes from their art. Flat marks do not own rigid-body
  collision. A ground underlay must not conceal a solid island or pocket rim.

The active catalog contains 151 contracts covering 223 prepared output paths,
including materials and utility masks. `tools/prepare_environment_library.py`
rebuilds these outputs. `tools/prepare_track_art.py` delegates to that pipeline;
it no longer applies the rejected cel preparation.

## Room Identity and Procedural Materials

Material choices live in `data/household_material_patterns.json` and are rendered
by `HouseholdSurfaceMaterials` and the world-coordinate household surface shader.
They are generated parameters, not one fixed background picture per room.

| Room | Tabletop and apron | Handmade course | Raised island surfaces | Prop accents |
|---|---|---|---|---|
| Kitchen | Ivory or sage ceramics, terracotta inlay, cream laminate | Muted sage, slate or umber paint over the same countertop | Maple strips, end-grain board, walnut preparation board | Ivory, sage, terracotta, food colors |
| Workshop | Bench boards, oiled timber, plywood, narrower wood slats | Chalk, limestone or graphite paint over the same timber | Charcoal or kraft cutting grids, ribbed work pad | Red enamel, ochre, pale wood, matte steel |
| Office | Ivory/cool laminate, ash veneer, walnut herringbone | Slate, pearl or silver paint over the same desk | Ink-blue weave, oxblood desk pad, indigo twill | Ivory, ink blue, ochre, restrained brick red |

Workshop and Office must not collapse into two teal rooms. Their large value
masses, pattern families and edge colors must remain distinguishable before the
player identifies individual props.

Each theme offers four floor and three island profiles. The twelve existing
story families and curated palette identities constrain the choices; an
independent material stream varies profile selection, spacing, orientation,
phase, seams, stagger and grain. The same seed reproduces the same result.
Material changes must not alter route geometry or racing-line fingerprints.

The course is translucent paint at the existing road width. Its supporting tile
grid, timber joints and grain continue across the paint boundary; a second rigid
material must not be cut to the racing outline. Narrow, softly painted edge lines
and directional brush coverage distinguish the course without a raised edge,
shadow or taped paper joins. The apron remains drivable.

Each theme has three restrained pigment palettes. The independent material seed
varies brushwork and edge width without changing floor/island choices. Palette
selection uses the least opaque readable setting, from 38% to 90%, checking the
composited color against both the tabletop and island rather than testing the
pigment in isolation. Edge markings are also translucent.

Floor and course share the same world-coordinate surface sampler, profile and
texture. Only the brush marks use along-course coordinates. No overlapping
square cards, camera-relative grain or fake asphalt should appear at bends.
Paint is visual only; it does not add walls or change grip zones.

## Composition

`WorldEnvironmentCatalog` combines the asset contract, the twelve semantic
stories and supporting families in `data/environment_composition.json`.
`WorldEnvironmentPlan` produces physical placements without accessing a scene
or textures; `WorldEnvironmentArt` builds the visible objects with per-item
loading yields. Procedural and saved track fixtures use the same model.

- Select one fitting focal anchor, with supporting medium objects and restrained
  nearby micro dressing. Prefer recognizable arrangements over uniform scatter.
- Spread supporting groups across distinct route sectors. Object choice,
  placement and orientation are deterministic, with independent role streams.
- Keep object repetition within the catalog limits. Ground/decal placement and
  clipped gameplay-surface paint are bounded separately.
- Preserve negative space around the full nominal corridor and its clearances.
  Reserve gate posts, sealed bays, on-course obstacles and hazard sweeps before
  planning scenery.
- Outer boundaries use completed sets, not totals of loose objects. Long items
  form end-to-end runs; workshop hardware forms side-by-side rows. A set uses one
  family, follows the actual outer-edge arc and is fitted atomically without an
  inner-side fallback. Outer sets are reserved before supporting clutter.
- Quantity, family and run length vary within configured budgets. Inner accents
  are counted separately. An actual collision-free exit and open apron sector
  remain drivable; never back bare floor with an invisible outer wall.
- Solid objects retain their registered sizes and cannot intersect other planned
  solid footprints. The planner reports an unsuccessful fit instead of distorting
  a prop or changing the requested seed.
- The room ends at a visible furniture edge, with the dark `#111316` overscan void
  beyond it. Island and pocket surfaces have a visible side face and lip matching
  their physical boundary.

Technical surfaces, the faster low-grip shortcut, direction-specific hazards,
the speed section, finish approaches and ordered gates remain gameplay data.
Their art must remain visible and understandable. Grip-region paint uses the
authoritative polygons, feathered boundaries and physically scaled artwork;
rectangular texture stamps must not cover the course or hide solid edges.

## Vehicle and Effects

Vehicle and HUD accents retain their existing reference palette; environment
colors come from the room profiles above.

| Color | Vehicle/UI role |
|---|---|
| `#E85A2E` | Rustbug orange and energy accents |
| `#F4C65A` | Yellow highlights and boost fill |
| `#4A8FB8` | Windows and cool metal |
| `#F5F0E3` | Cream surfaces and warm highlights |
| `#1A1F23` | Ink outlines and deep shadows |

- Cars retain their existing rounded, chunky silhouettes, exaggerated wheels,
  roof/hood distinction, large windows and compact color masses.
- Existing art includes `rustbug_hero.png`, `vfx_drift_dust.png`,
  `vfx_boost_flame_trail.png`, `vfx_impact_flash.png` and `vfx_skid_mark.png`.
- Vehicle shadows are part of the existing generated car sprites; the obsolete
  standalone Rustbug shadow is not used by the scene.

Use only effects that communicate handling:

1. Short warm dust puffs and faint temporary skid marks during hard drifts.
2. A compact orange/yellow boost wisp with a few sparks.
3. A very brief impact flash and small vehicle squash.
4. A subtle one-to-two-percent camera pulse on boost or hard impact.
5. One or two ambient motions, such as a droplet loop or fruit wobble.

Effects never obscure the car, racing line, checkpoint or nearby hazards.

## HUD and Championship Shell

The championship shell remains a midnight workbench: focused controls and
editorial type on the left, with the driver, machine or route illustration on
the right. Focus changes the visual stage rather than adding explanatory copy.

- The lap/timer plate is rounded and restrained, with a cream surface and dark
  outline. The cartoon boost tube uses orange/yellow fill. No MMO card chrome;
  lap, position, timer and boost stay dominant. Debug telemetry is dev-only and
  visually separate.
- The left column carries controller-safe actions. The right stage shows Rae,
  rivals, room routes or the focused machine without requiring external source art.
- Vehicle selection exposes all four silhouettes and progression locks at once;
  focus updates the machine and its speed, grip, mass and drift profile.
- Driver portraits retain deterministic pixel features, individual hair,
  clothing, accessories and accents.
- Screen transitions remain a short slide and fade and are disabled by reduced
  motion. Camera and impact effects also respect reduced motion.

## Acceptance

Review native gameplay views at representative zoom for every theme, not only
source sheets. Compare several seeds: variation must include material structure
and composed arrangements, not only tint or prop jitter. Check deterministic
rebuilds, theme isolation, physical dimensions, overlap, visible collision,
route readability and the 250 ms loading-frame contract.

At 1280×720, the player must immediately identify the car, road, next route,
start/finish, nearby hazards and outer counter drop. Before a race, the
protagonist, rival, selected car, locked roster and relevant room must be visible
without reading body copy.

The game should read as one painted household world with distinct rooms while
retaining its original cars and existing race rules.
