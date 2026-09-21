# Pocket Circuit — Agent Notes

## Project

- **Pocket Circuit**: a top-down **2D** arcade racer. Tiny vehicles race
  through oversized everyday environments (kitchen counters, workshops,
  offices); 2–5 min races feed a persistent garage/progression system.
- **Engine:** Godot 4.7.2 (GDScript), editor at `/usr/bin/godot`. Server-side
  services (Phase 3+) live under `server/` and may be a different language.
- **2D, not 3D:** presentation is Node2D sprites / CanvasLayer. The design
  spec §7 camera and §9 physics describe 3D concepts — implement their
  *feel* in 2D (top-down follow camera, speed-aware zoom, arcade physics on
  a 2D physics body). Where spec says 3D and reality is 2D, 2D wins.
- **Source of truth for game design:** `docs/game-design-spec.md` — the full
  135-section pre-production spec. Read the relevant section before touching a
  system (driving model §9, camera §7, tracks §11, surfaces §10, networking
  §68–75, repo structure §60, autoloads §61).
- **First Godot project** — do not assume prior repo conventions; follow this
  file and the spec.

## Golden rule

Spec §127 order, never reversed: vehicle feel → camera → track readability →
local race rules → networking → authoritative server → persistence → basic
progression → matchmaking → more content. Phase 0 proves driving is fun before
any MMO scaffolding. §124: testers voluntarily replay laps with no rewards.

## Run / verify

| Command | Purpose |
|---|---|
| `godot --path . --editor` | Open project in the editor (needed for MCP) |
| `godot --path .` | Run the main scene |
| `godot --path . --headless --script <test.gd>` | Run a GDScript test |
| `godot --path . --headless --server` | Dedicated race server (Phase 2+) |

**Session closeout:** after finishing a work or QA session, hand the game to the
operator — never launch it yourself. Print the exact command and let Fran run
it, e.g. `godot --path ~/Workspace/Worktrees/pocket-circuit-GURI-1036` (run the
main scene, not `--editor`). A plain game run does not dirty the working tree;
still verify `git status` is clean first.

Godot version pin: **4.7.2**. Do not change it without a Linear decision and
matching export templates. Verify scripts with `validate_script` and check
`get_errors` after scene changes.

## Branches and CI

- Feature branches PR into `dev`; `pr-smoke` runs cheap pure-Python release-tool
  checks (seconds).
- The full release gate runs only on pushes to `dev` and `main`.
- `main` is the shipping branch; it only receives promotions from `dev`.
- Commit style is unchanged.

## Godot conventions

- Use the **Godot MCP** (`godot-dev` skill): never hand-edit `.tscn` as text;
  create scenes/scripts with the scene tools, attach scripts with
  `attach_script`, and run/stop scenes through `run_scene` / `stop_scene`.
  Stop the running scene before editing code.
- `addons/godot_mcp/` is the agent's editor bridge — **local dev tool,
  gitignored**, do not commit. Copy it in fresh via `cp -r` from
  `~/Workspace/platformer/game/addons/godot_mcp/` if missing. Enable it only
  while using MCP and remove its entry from `[editor_plugins]` in
  `project.godot` before committing so clean clones do not warn about a missing
  local plugin.
- **Runtime MCP tools** (screenshot, send_input, query_runtime_node) need the
  `MCPRuntime` autoload. It is NOT committed (it points at the gitignored
  addon). At the start of a session that needs runtime tools, register it via
  the MCP `godot_setup_autoload` (name `MCPRuntime`,
  `res://addons/godot_mcp/runtime/mcp_runtime.gd`), then **revert the
  `[autoload] MCPRuntime` block from `project.godot` before committing**.
- Keep scripts small and single-purpose. Vehicle scene structure per spec §62
  (VehicleController / VehiclePhysics / VehicleStats / …). Do not write a
  4,000-line `car.gd`.
- Game data is data-driven (Resources during dev, spec §63) — no brittle
  scene paths in gameplay code.
- Layered architecture per spec §59: Presentation → Gameplay → Network →
  Domain/Shared Rules → Persistence.
- Debug overlay is dev-only and must never ship (GURI-120).

## Editor coordination

- Only one worker drives the Godot editor connection at a time because the
  editor has a single MCP socket. Sequence scene, asset, and test work rather
  than running concurrent editor mutations.
- Do not reduce scope, quality, asset count, or verification to fit one work
  session. Use exact briefs, targeted reads, reusable context docs, batched
  tool calls, and stable handoffs until the task is complete.

## Asset workflow

Original project assets are committed under `assets/` and imported through the
Godot MCP.

1. Open the repo in the Godot editor first so MCP is connected.
2. Start from a per-asset brief quoting the spec (art direction §55,
   environment props §12, vehicles §55.3), the target path under `assets/`,
   and the render path. Use the Godot MCP for SVG-to-PNG rendering,
   Sprite2D/TextureRect placement, and any procedural source scripts.
3. Style is **stylized top-down 2D sprites, toy-like, clear silhouettes,
   saturated-but-controlled palette** (§55). No photorealism. Original
   fictional vehicles — no copyrighted car/track/character designs (§109).
4. Verify each asset renders in-editor (`get_errors`, scene tools) before
   committing. Keep project assets in `assets/<category>/`; previews go to
   `/tmp/opencode/screenshots/`, never the repo.

## Linear workflow

- Track project work in Linear, project **Pocket Circuit**:
  https://linear.app/gurisitosgames/project/pocket-circuit-78cd5b0a6db2
- Phase milestones map to spec §114: Phase 0 handling prototype → Phase 1
  local race → Phase 2 network race → Phase 3 persistent garage → Phase 4
  matchmaking → Phase 5 progression → Phase 6 social/MMO → Phase 7 scale.
- New ideas are Linear issues in Backlog. Pick up issues, move `In Progress`,
  comment progress, move `Done` with a closing comment once merged into the
  shipping branch.
- Phase 0 epic: **GURI-113** (children GURI-114…GURI-121). Feature-branch work
  on a tracked issue uses a worktree `pocket-circuit-GURI-N` beside this
  checkout.
- Read the `linear-workflow` skill before creating or updating any issue.

## Changelog

- End-user-visible changes go in root `CHANGELOG.md` (plain markdown; no
  changelog lib in this repo). Internal scaffolding, refactors, tests, and
  agent workflow changes get no entry.
- Read the `changelog` skill for what qualifies.

## Related

- Skills: `godot-dev`, `repo-onboarding`, `linear-workflow`, `github`,
  `changelog`, `frontend-design` (visual direction).
- Design spec: `docs/game-design-spec.md`.

## Agent hygiene: never leave tracked changes uncommitted

Commit early and often in small logical units; never leave tracked edits uncommitted at the end of a task or session handoff.
- When approaching the session step limit or any interruption risk, commit green-but-uncommitted work immediately with a clear message.
- Before reporting a task complete, the worktree must be clean: `git status --porcelain` empty (only explicitly-scoped untracked scratch allowed, noted in the report).
- Any change made after the final commit (debug removal, formatting, test tweak) is a new commit — never a silent dirty tree.
- At session start in an existing worktree, check `git status` first; commit or explicitly report pre-existing dirt before editing further.
