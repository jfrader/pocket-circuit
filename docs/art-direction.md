# Pocket Circuit Art Direction

## Visual Thesis

A hand-illustrated Saturday-morning cartoon kitchen counter where chunky toy
cars race through oversized friendly objects under soft cel-shaded light,
with a readable dark track, strong inked silhouettes, warm materials, and
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
- Highlights come from the upper left and use warm cream rather than pure
  white. Shadows offset down and right with a warm dark-brown tint.
- Track edges are broad, rounded, and slightly hand-drawn rather than perfect
  vector radii. Track value contrast must remain clear at speed.
- The full inner island is solid and outlined by a continuous amber guardrail.
  Traversable shortcuts are explicit authored openings, never missing physics.
- Kitchen props are oversized, friendly, and readable from directly above.
  Details are broad shapes, not thin linework.
- Micro details such as crumbs, fibers, droplets, scratches, and wood grain use
  low contrast and never compete with the racing line.

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

## Asset Plan

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

### Vehicle And Effects

- `rustbug_hero.png`
- `rustbug_shadow.png`
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
