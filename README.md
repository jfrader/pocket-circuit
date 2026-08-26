# Pocket Circuit

Tiny racing. Big stakes.

A premium offline top-down arcade racer where tiny vehicles compete across
oversized kitchens, workshops, and offices. The complete Grand Household
Circuit spans nine brisk events, three rival acts, and four unlockable handling
archetypes. The implementation, setting, characters, vehicles, and content are
original; see the design spec IP note (§109).

**Engine:** Godot 4.7.2 (GDScript) · **Version:** 1.0.0 · **Status:** Phase 1
release candidate
**Presentation:** top-down **2D** sprites (Node2D / CanvasLayer). The original
spec (§7) describes a 3D camera — the project renders as **2D**; where spec
and 2D conflict, 2D wins and the spec's *feel* (readable at speed, follow
camera, miniature scale) is the guide.

## Design spec

Full 135-section pre-production spec: [`docs/game-design-spec.md`](docs/game-design-spec.md)
(imported from the original working doc).

The golden rule (§127): vehicle feel → camera → track readability → local race
rules → networking → authoritative server → persistence → basic progression →
matchmaking → content. **Do not reverse this order.** A beautiful MMO garage
attached to mediocre racing is a dead project.

## Phase 1 — Single-Player Championship (GURI-255)

Phase 1 is a self-contained offline game:

- Nine championship events across Kitchen, Workshop, and Office themes.
- Four vehicles with balanced, grip, heavy, and drift handling identities.
- Four-racer AI fields, rival duels, reverse races, surfaces, moving hazards,
  checkpoints, recovery, finish order, and DNF grace.
- A complete three-act story with persistent points, unlocks, event replay, and
  an ending.
- Keyboard and controller menus, pause/results flow, volume controls, reduced
  motion, reduced camera shake, and versioned local saves with backup recovery.
- Native Windows x86_64 and Linux x86_64 release exports for Steam and Steam
  Deck, with no account or network requirement.

Split-screen and LAN multiplayer are intentionally deferred to a later release.
See [`docs/phase-1-release.md`](docs/phase-1-release.md) for the exact shipped
rules and [`docs/release-qa.md`](docs/release-qa.md) for release gates.

## Project structure

Mirrors spec §60:

```
project.godot        Godot 4.7.2 project, App autoload, and input settings
addons/              editor plugins (godot_mcp = local dev tool, gitignored)
assets/              audio/, models/, materials/, textures/, ui/
data/                vehicles/, parts/, tracks/, factions/, progression/, localization/
scenes/              boot/, menu/, garage/, hub/, race/, vehicles/, tracks/, ui/
scripts/             autoload/, gameplay/, vehicle/, race/, network/, progression/, inventory/, ui/, utilities/
server/              race/ (dedicated race server, headless Godot), config/
tests/               unit + simulation tests
docs/                design spec + technical docs
```

## Run / verify

| Command | Purpose |
|---|---|
| `godot --path . --editor` | Open the project in the editor |
| `godot --path .` | Run the current main scene |
| `godot --path . --headless --script res://tests/...` | Run GDScript tests |
| `./tools/build_release.sh` | Test and export Windows/Linux release candidates |

Godot version pin: **4.7.2** (installed at `/usr/bin/godot`). Do not change the
engine version without a decision in Linear and matching export templates.

## Workflow

- **Work tracking:** Linear, project **Pocket Circuit** — see the repo
  `AGENTS.md` `## Linear workflow` section.
- **Assets:** original project art and audio live under `assets/`; shipped
  notices and provenance live in `THIRD_PARTY_NOTICES.md` and adjacent license
  files.
- **Changelog:** end-user-visible changes recorded in `CHANGELOG.md` (plain
  markdown; no changelog lib in this repo yet).

## Related

- [Pocket Circuit project (Linear)](https://linear.app/gurisitosgames/project/pocket-circuit-78cd5b0a6db2)
- Gurisitos Games studio: [gurisitos.games](https://gurisitos.games)
