# Steam Media Source

The SVG files in this directory are deterministic source outputs from
`tools/generate_steam_art.py`. Regenerate the complete capsule and trailer-card
set from the repository root with:

```bash
python3 tools/generate_steam_art.py
```

The key art uses only original geometric illustration, Pocket Circuit's project
palette, and the game name. Rasterized text uses DejaVu Sans, a permissively
licensed Bitstream Vera derivative installed on the production host. The font
file itself is not redistributed.
