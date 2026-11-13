# Pocket Circuit

Tiny racing. Big stakes.

A premium offline top-down arcade racer where tiny vehicles compete across
oversized kitchens, workshops, offices and a basement. PLAY starts or resumes
the Run: choose a route, race for points and cars, manage wear and haul, and
reach the Basement finale. The secondary Grand Household Circuit spans nine
events, three rival acts and four unlockable handling archetypes.
The implementation, setting, characters, vehicles, and content are
original; see the design spec IP note (§109).

**Engine:** Godot 4.7.2 (GDScript) · **Version:** 1.0.0 · **Status:** Phase 1
release candidate; manual controller and clean-machine Windows/Linux/Deck
acceptance remains required for the exact candidate hash.
**Presentation:** top-down **2D** sprites (Node2D / CanvasLayer). The original
spec (§7) describes a 3D camera — the project renders as **2D**; where spec
and 2D conflict, 2D wins and the spec's *feel* (readable at speed, follow
camera, miniature scale) is the guide.

## Download

Windows tester builds are published on the [Releases](../../releases) page.
Unpack the zip and run `pocket-circuit.exe`.

## Design spec

Full 135-section pre-production spec: [`docs/game-design-spec.md`](docs/game-design-spec.md)
(imported from the original working doc).

The golden rule (§127): vehicle feel → camera → track readability → local race
rules → networking → authoritative server → persistence → basic progression →
matchmaking → content. **Do not reverse this order.** A beautiful MMO garage
attached to mediocre racing is a dead project.

## Phase 1 — Offline Run and Championship

Phase 1 is a self-contained offline game:

- The primary Run: branching tabletop stops, six-car races, optional rival
  duels, mandatory act rivals and an authored three-lap Basement finale.
- Run points, parts vans, benches, errands, lockups, per-car wear, tow recovery
  and one-use nitro. Races resolve once per night, with no retries.
- Won-car offers, haul chase sprints, impound, ransom and banking. Only secured
  won cars join the collection after the night; unbanked haul can be lost.
- A secondary nine-event championship across Kitchen, Workshop and Office,
  with four-car fields, rival duels, four handling archetypes, persistent points,
  unlocks, event replay and a three-act story ending.
- Quick Race, Quick Strip and Circuit Discovery.
- Reverse circuits, surface zones, permanent obstacles, the Basement boiler
  leak, checkpoints, recovery, finish order and DNF grace.
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
  notices and production provenance live in `THIRD_PARTY_NOTICES.md`,
  `ASSET_PROVENANCE.md`, and adjacent license files.
- **Steam media:** upload-ready capsules, packaged-build screenshots, trailer,
  source art, hashes, and regeneration commands live under `media/steam/`.
- **Changelog:** end-user-visible changes recorded in `CHANGELOG.md` (plain
  markdown; no changelog lib in this repo yet).

## Related

- [Pocket Circuit project (Linear)](https://linear.app/gurisitosgames/project/pocket-circuit-78cd5b0a6db2)
- Gurisitos Games studio: [gurisitos.games](https://gurisitos.games)

## License

MIT — see [`LICENSE`](LICENSE). Third-party components and asset provenance are
recorded in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and
[`ASSET_PROVENANCE.md`](ASSET_PROVENANCE.md).
