# Pocket Circuit Art Direction

## Visual Thesis

A hand-illustrated Saturday-morning cartoon household where chunky toy cars
race through oversized friendly objects under soft cel-shaded light, with a
readable material track, strong inked silhouettes, warm surfaces, and dense
small details that sell the miniature scale.

This is a top-down 2D game. Visuals must read while rotating at speed and at
roughly 32-55 pixels on screen. Everything is original; no protected vehicle,
track, character, branding, or UI designs are copied.

The championship shell presents that world as a midnight workbench: editorial
type and focused controls occupy the left side while an illustrated garage,
driver, machine, or route board occupies the right. The visual stage reacts to
the focused screen or vehicle so the cast and four-car roster are always
visible rather than described only in text.

## Reference Principles

The direction uses genre principles observed across classic *Micro Machines*,
*Toybox Turbos*, *Mini Motor Racing*, and *Circuit Superstars*: oversized room
objects sell scale, cars need distinct top-down silhouettes, and every track
edge or shortcut must be legible before the player reaches it. These references
are evaluation targets only. Pocket Circuit uses its own cast, machines,
rooms, route geometry, palette, interface, and story.

## Palette

| Color | Role |
|---|---|
| `#3F2A22` | Deep wood and counter shadow |
| `#5C4638` | Main counter wood |
| `#8C6F55` | Counter highlights and warm edges |
| `#2A2F33` | Track asphalt |
| `#E85A2E` | Rustbug orange and energy accents |
| `#F4C65A` | Sponge, cereal highlights, start/finish |
| `#2E8B57` | Lime, scrub pad, wet-area accents |
| `#C81E2E` | Apple red and hazard accents |
| `#4A8FB8` | Windows, ceramic, cool metal |
| `#F5F0E3` | Ceramic, crumbs, warm highlights |
| `#1A1F23` | Ink outlines and deep shadows |
| `#111316` | Void beyond the counter |

## Shape Language

- Cars are rounded and chunky, with exaggerated wheels, a strong roof/hood
  read, large windows, and three or four clear color masses.
- Major silhouettes use closed dark outlines. Hero assets use thicker outlines
  than dressing assets.
- One upper-left key light governs the whole race scene. Highlights use warm
  cream rather than pure white; every vehicle, prop, obstacle, and landmark
  shadow falls down and right with a soft warm dark-brown tint. Rectangular
  objects retain rectangular footprints, and giants add a faint longer cast.
- Track edges are broad, rounded, and slightly hand-drawn rather than perfect
  vector radii. Track value contrast must remain clear at speed.
- The full inner island is a visibly raised solid feature: a dark side face,
  textured theme edge, warm top lip, and small edge landmarks communicate the
  exact physical rim from every approach.
- The room apron is open Micro Machines-style diorama space. No invisible
  corridor wall sits under bare floor; collision is reserved for real visible
  household assets, the raised island, and room walls.
- Traversable shortcuts include authored surface lanes inside the racing
  corridor. The raised island physically closes the inside line; ordered gates
  stop there but extend across the open outer apron. If a car penetrates the
  island or persists the wrong way, it returns to its last legal gate.
- Kitchen props are oversized, friendly, and readable from directly above.
  Details are broad shapes, not thin linework.
- Micro details such as crumbs, fibers, droplets, scratches, and wood grain use
  low contrast and never compete with the racing line. These painted/material
  marks remain flat; recognizable loose hardware is physical even at micro scale.
- One to three household landmarks per generated room establish the tiny-car scale.
  Their silhouettes retain the physical dimensions in `data/world_prop_art.json`, with footprint-matched
  contact shadows, longer down-right cast shadows, full trimmed-footprint
  collision, and enough breathing room to remain readable without covering the
  corridor. If an object reads raised or solid, its center and extremities must
  stop a car; only art that reads painted onto the ground may be drive-over.

## Track Composition

- Opening straight: bold start stripes, crumbs, and a half-visible counter
  landmark behind the line.
- Mug chicane: two distinct hero mugs, one cream and one blue, with readable
  handles and coffee surfaces.
- Right technical: two contrasting cereal towers act as visual bookends.
- Top shortcut: a large wet sponge, puddle edge, droplets, and scrub fibers.
- Left technical: ruler and spoon create long graphic directional forms.
- Fruit cluster: apple and lime add color and scale detail.
- The outer counter edge reads as a dangerous drop into the dark kitchen void.

### Generated Room Density

- Generated rooms layer density by scale: 1-3 giant household landmarks,
  authored story clusters, 2-4 broad ground anchors, 60-120 low-contrast floor
  details, and 60-150 tiny edge/apron details. Painted/material micro details
  are non-colliding; raised rails and recognizable loose props use
  silhouette-matched collision.
- Edge details remain outside the drivable area and recovery lanes while sitting
  close enough to both sides of the corridor to prevent empty floor bands.
- The room surface ends at its fully backed perimeter wall; the 760-unit camera
  overscan beyond it is the dark void rather than more floor material.
- Thirty-two faint material marks break up each generated corridor. They read
  as wood grain, cork, or desk-pad texture rather than painted racing lines.
- Four to eight readable grip patches add themed material changes inside the
  corridor. Decals communicate the surface before handling changes, and they
  stay clear of the start, finish, checkpoints, and designed surface moments.
- Giant landmarks use Kitchen food and utensils, Workshop sports and tool
  silhouettes, or Office desk objects. Every giant is physical scenery with a
  collider covering its visible center and ends, while every placement stays
  clear of route and checkpoint safety space.

## Asset Plan

Environment sprites use a smooth cel-illustrated 2D language: anti-aliased
silhouettes, confident dark contours, controlled color bands, tight contact
shadows, and restrained directional shading. Wood, ceramic, matte metal, cloth,
cork, paper, and food keep distinct surface cues without becoming pixel art,
photorealism, or a 3D render. Textures do not bake in room reflections or glossy
streaks.

Repeated roles use prop families rather than one stamped sprite. Boundary runs
mix related utensils, rulers, sticks, corks, and hardware; ambient clusters mix
silhouettes, colors, patterns, wear, and material variants. Purposeful clutter
that explains the route stays dense. Unstructured micro-speckle is subordinate
to the track and never substitutes for recognizable household objects.

### Hero Landmarks

- `kitchen_mug_hero.png`
- `kitchen_mug_blue.png`
- `kitchen_spoon_bridge.png`
- `kitchen_cereal_tower_a.png`
- `kitchen_cereal_tower_b.png`
- `kitchen_counter_surface.png`
- `kitchen_track_surface.png`
- `kitchen_counter_edge.png`

### Support Props

- `kitchen_sponge_wet.png`
- `kitchen_ruler_plank.png`
- `kitchen_fork.png`
- `kitchen_apple.png`
- `kitchen_lime.png`
- `kitchen_cup.png`
- `kitchen_plate.png`
- `kitchen_cutting_board.png`
- `kitchen_toaster_edge.png`
- `kitchen_napkin.png`

### Micro Dressing

- `kitchen_crumb_cluster_01.png`
- `kitchen_crumb_cluster_02.png`
- `kitchen_cereal_scatter.png`
- `kitchen_wood_scratch.png`
- `kitchen_water_droplet_01.png`
- `kitchen_water_droplet_02.png`
- `kitchen_spill_decal.png`
- `kitchen_start_stripe_decal.png`
- `kitchen_skid_mark.png`

Generated tracks also draw from `assets/textures/edge_dressing/` for crumbs,
fibers, hardware, worn-floor hints, and subtle material patterning, and from
`assets/textures/grip_patches/` for readable surface decals.

### Generated Giant Landmarks

- Kitchen: cereal box, mug, watermelon, fork, toaster, and milk carton.
- Workshop: basketball, toolbox, paint can, watermelon, hammer, and wrench.
- Office: keyboard, monitor, paper stack, pen, stapler, and mouse.
- These original top-down sprites live in `assets/textures/giant_props/`.
  One world unit represents one millimetre; a prop keeps its size in every role.
  The manifest is measured against trimmed alpha bounds, not the padded canvas.
  A tablespoon is 180 units long, a nail 40, and a keyboard 440. Tight spaces
  receive a different suitable object rather than a squeezed or shrunken prop.

### Ambient Ground Dressing

- Place two to four broad anchors in otherwise empty room sectors, using cloth,
  paper, cardboard, or desk-pad silhouettes rather than uniform scatter.
- Kitchen uses a checked tablecloth patch, striped dish towel, yellow cleaning
  rag, and red oven mitt.
- Workshop uses a stained drop cloth, red shop rag, cardboard scrap, and
  sandpaper sheet.
- Office uses a dark desk pad, envelope stack, sticky notes, and notepad page.
- These pieces remain lower contrast than hero landmarks, do not collide, and
  cannot become a substitute for readable track edges.

### Generated Course Boundaries

- Preserve controlled negative space: each generated lap has five short
  both-sided rail moments, two one-sided runs, and one open accent sector marked
  only by a flat worn-floor hint. Each side receives accents in at least four
  of eight sectors, with at least eleven occupied edge/sector pairs overall.
- Partial rail sprites are the physical boundary wherever they appear; their
  colliders fit inside their visible footprints. Kitchen mixes several forks,
  spoons, rulers, craft sticks, chopsticks, butter knives, and cork rails;
  Workshop mixes paint stirrer, dowel,
  clamp, and ruler rails; Office mixes pencil, ruler, pen, and book-spine rails.
  Nails and erasers replace long rails where necessary. Sponge, tape, and
  sticky-note corner accents remain rare. Neighboring rail footprints do not overlap.
- Bare floor between those assets is intentionally open and drivable. Never add
  a continuous outer collider, invisible corridor edge, or visual bevel that
  implies one.
- The only continuous generated rim belongs to the raised island object. Room
  perimeter walls remain visible furniture edges with dark void beyond them.
- Checkpoint paint and banners stay across the nominal corridor. Small themed
  colliding posts mark those corridor ends, while the invisible sensor extends
  from the raised island or room wall to the opposite real boundary.
- Keep corner accents larger and rarer than straight sections. Avoid even
  spacing, mirrored walls, or enough repeated pieces to read as a stadium rail.

### Vehicle And Effects

- `rustbug_hero.png`
- Vehicle shadows are baked consistently into the generated car sprites; the
  obsolete standalone Rustbug shadow is not used by the scene.
- `vfx_drift_dust.png`
- `vfx_boost_flame_trail.png`
- `vfx_impact_flash.png`
- `vfx_skid_mark.png`

### HUD

- Rounded, restrained lap/timer plate with a cream surface and dark outline.
- Cartoon boost tube using orange/yellow fill.
- No MMO card chrome. Race position, lap, timer, and boost remain dominant.
- Debug telemetry stays dev-only and visually separate from the race HUD.

### Championship Shell

- The left column carries hierarchy, copy, and controller-safe actions.
- The right illustration stage shows Rae, rivals, room routes, or the currently
  focused machine without requiring external source art.
- Vehicle selection exposes all four silhouettes and progression locks at once;
  focus updates the hero machine and its speed, grip, mass, and drift profile.
- Driver portraits use crisp deterministic pixel features, individual hair,
  clothing, accessories, and accent palettes for instant recognition.
- Screen transitions remain a short slide and fade and are disabled by reduced
  motion.

## Motion Thesis

Use only effects that communicate handling:

1. Short warm dust puffs and faint temporary skid marks during hard drifts.
2. A compact orange/yellow boost wisp with a few sparks.
3. A very brief impact flash and small vehicle squash.
4. A subtle one-to-two-percent camera pulse on boost or hard impact.
5. One or two ambient motions, such as a droplet loop or fruit wobble.

Effects never obscure the car, racing line, checkpoint, or nearby hazards.

## Acceptance Test

At 1280x720, a player must immediately identify the car, road, next route,
start/finish, mug chicane, sponge shortcut, and outer counter drop. The slice
must feel like one illustrated world rather than unrelated SVG assets placed
on gray geometry. Before a race, the player must also see the protagonist,
rival, selected car, locked roster, and relevant room without reading body copy.
