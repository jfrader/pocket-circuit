# Steam Store Copy Draft

This draft describes the complete offline Phase 1 game only. It makes no online,
multiplayer, live-service, or future-content promise.

## Short description

Race tiny machines across giant kitchen, workshop, and office circuits in a
complete offline arcade championship. Master nine brisk events, outdrive three
rivals, and unlock four tuned handling builds before sunrise.

## About this game

The Grand Household Circuit begins after dark. Rookie Rae Sparks has one repaired
Rustbug, one night, and one chance to prove that the household's biggest race
belongs to every driver—not only the reigning champion.

Pocket Circuit is a top-down arcade racer built around immediate handling and
miniature spectacle. Thread between oversized mugs, tools, papers, spills, and
moving hazards in two-to-five-minute races. Earn points without a lives system,
unlock side-grade vehicles, and replay completed events with any machine you
have earned.

Three acts build from kitchen qualifier to workshop league and office final.
Short event cards and rival exchanges keep the story moving while the racing
stays in control. The whole championship, settings, unlocks, and replays work
offline with no account required.

## Features

- A complete nine-event single-player championship across three room themes.
- Four handling identities: balanced Rustbug, grip-focused Pinbolt, heavy
  Scrapjaw, and drift-focused Flicker.
- Forward and reverse circuits, rival duels, environmental hazards, recovery,
  drifting, and boost.
- Three difficulty presets that change racing pressure without locking content.
- Persistent local progress, event replay, volume controls, reduced camera
  shake, and reduced motion.
- Original stylized top-down art direction and soundtrack, with licensed CC0
  toy-racing sound effects.
- Designed for keyboard and controller play with no network connection needed.

## Controls and platforms

Target platforms are Windows x86_64, Linux x86_64, and Steam Deck via the native
Linux build. Keyboard and Xbox-compatible controller mappings are included;
PlayStation-style controllers are a required QA target. Final Steam Deck
compatibility status must match Valve's review result rather than this draft.

## Media checklist

- [x] Seven release-build screenshots cover the title, championship map,
  pre-race briefing, vehicle selection, and live Kitchen, Workshop, and Office
  races.
- [x] Screenshots show final HUD and real gameplay with no debug overlay, editor,
  placeholder art, unsupported feature, or unreadable small text.
- [x] All required Steam capsule formats share the ink/amber/cream miniature
  circuit identity and remain legible at their smallest required size.
- [x] Library assets, app icon, community icon, and hero/header treatments use
  approved original source art and current Steamworks dimensions.
- [x] A concise gameplay-first trailer opens with racing, shows all three themes
  and four vehicles, includes real UI/audio, and ends on the offline
  championship promise without online claims.
- [x] Trailer music, fonts, logos, and every visible asset have documented rights
  before upload.

The repository media packet is in `media/steam/`. `MANIFEST.md` records exact
dimensions, production rights, encoding, regeneration commands, and the build
hashes used for capture. Steamworks policy and dimensions must still be checked
once more immediately before owner upload because Valve can revise requirements.

## Languages

- Interface: English.
- Full audio: no spoken dialogue.
- Subtitles: all story and rival dialogue is presented as English on-screen text.

Do not select additional Steam language support until the corresponding in-game
copy has been translated and tested.

## System requirements draft

### Windows minimum

- 64-bit Windows 10 or later.
- Dual-core 2.0 GHz processor.
- 4 GB RAM.
- Vulkan 1.0-compatible graphics hardware.
- 500 MB available storage.
- Keyboard; controller supported but not required.

### Linux minimum

- 64-bit Linux distribution with glibc 2.31 or later.
- Dual-core 2.0 GHz processor.
- 4 GB RAM.
- Vulkan 1.0-compatible graphics hardware and current Mesa/vendor drivers.
- 500 MB available storage.
- Keyboard; controller supported but not required.

These are conservative store-page drafts, not owner-approved claims. Confirm
them on clean low-end target systems and revise from measured results before
Steamworks submission.

## Support and data-use draft

- Support site: `https://gurisitos.games`
- Support email: `hola@gurisitos.games`
- Pocket Circuit requires no account or network connection and contains no
  advertising, analytics, telemetry, live AI, voice chat, or user-generated
  content upload.
- The game stores championship progress and settings locally. Steam Cloud may
  synchronize those files when the publisher enables it and the Steam client is
  online.

Publish equivalent wording on the studio privacy/support page before entering a
privacy-policy URL in Steamworks.

## Content survey draft

Pocket Circuit depicts fictional toy-scale racing and non-realistic vehicle
collisions without injury, gore, weapons, gambling, drugs, sexual content, or
strong language. Review the exact final build during Steam's content survey.
Use the pre-generated AI-assisted-content wording in `ASSET_PROVENANCE.md`; the
game has no live generative-AI features.

## Suggested launch price — owner approval required

**Proposal only: USD $9.99 base price, with owner-reviewed regional pricing.**
This is not approved, configured, or enacted by repository work. The owner must
approve the price and any launch discount in Steamworks after reviewing scope,
market fit, taxes, regional recommendations, and Valve's pricing rules.
