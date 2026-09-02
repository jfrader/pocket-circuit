#!/usr/bin/env python3
"""Generate the original Pocket Circuit Steam capsule set from SVG source."""

from __future__ import annotations

import html
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MEDIA_ROOT = ROOT / "media" / "steam"
SOURCE_ROOT = MEDIA_ROOT / "source"
CAPSULE_ROOT = MEDIA_ROOT / "capsules"
TRAILER_ROOT = MEDIA_ROOT / "trailer"

INK = "#111827"
NIGHT = "#19243B"
PAPER = "#F4E8D0"
CREAM = "#FFF8E8"
AMBER = "#F4BF3A"
CORAL = "#E96B4C"
BLUE = "#55A8C9"
MUTED = "#7D8799"


def defs() -> str:
    return f"""
    <defs>
      <linearGradient id="night" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="{INK}"/>
        <stop offset="0.56" stop-color="{NIGHT}"/>
        <stop offset="1" stop-color="#273855"/>
      </linearGradient>
      <linearGradient id="titleFade" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" stop-color="{INK}" stop-opacity="0.98"/>
        <stop offset="0.68" stop-color="{INK}" stop-opacity="0.72"/>
        <stop offset="1" stop-color="{INK}" stop-opacity="0"/>
      </linearGradient>
      <linearGradient id="titleFadeVertical" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#FFFFFF"/>
        <stop offset="0.68" stop-color="#FFFFFF"/>
        <stop offset="1" stop-color="#000000"/>
      </linearGradient>
      <mask id="titleMask"><rect width="100%" height="100%" fill="url(#titleFadeVertical)"/></mask>
      <radialGradient id="sun" cx="50%" cy="50%" r="50%">
        <stop offset="0" stop-color="#FFE7A0" stop-opacity="0.95"/>
        <stop offset="0.55" stop-color="{AMBER}" stop-opacity="0.55"/>
        <stop offset="1" stop-color="{AMBER}" stop-opacity="0"/>
      </radialGradient>
      <filter id="shadow" x="-60%" y="-60%" width="220%" height="220%">
        <feGaussianBlur in="SourceAlpha" stdDeviation="10"/>
        <feOffset dx="0" dy="12" result="offsetblur"/>
        <feComponentTransfer><feFuncA type="linear" slope="0.45"/></feComponentTransfer>
        <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
      </filter>
      <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
        <path d="M 40 0 L 0 0 0 40" fill="none" stroke="#FFFFFF" stroke-opacity="0.035" stroke-width="2"/>
      </pattern>
    </defs>
    """


def logo(x: float, y: float, size: float, horizontal: bool = False, dark: bool = False) -> str:
    fill = INK if dark else CREAM
    accent = CORAL if dark else AMBER
    if horizontal:
        return f"""
        <g transform="translate({x:.1f} {y:.1f})">
          <rect x="0" y="{-size * 0.72:.1f}" width="{size * 0.18:.1f}" height="{size * 0.18:.1f}" rx="{size * 0.035:.1f}" fill="{accent}" transform="rotate(45 {size * 0.09:.1f} {-size * 0.63:.1f})"/>
          <text x="{size * 0.27:.1f}" y="0" fill="{fill}" stroke="{INK}" stroke-width="{size * 0.035:.1f}" paint-order="stroke" font-family="DejaVu Sans, sans-serif" font-size="{size:.1f}" font-weight="900" letter-spacing="{size * 0.018:.1f}">POCKET / CIRCUIT</text>
        </g>
        """
    return f"""
    <g transform="translate({x:.1f} {y:.1f})">
      <rect x="0" y="{-size * 0.77:.1f}" width="{size * 0.2:.1f}" height="{size * 0.2:.1f}" rx="{size * 0.04:.1f}" fill="{accent}" transform="rotate(45 {size * 0.1:.1f} {-size * 0.67:.1f})"/>
      <text x="{size * 0.3:.1f}" y="0" fill="{fill}" stroke="{INK}" stroke-width="{size * 0.035:.1f}" paint-order="stroke" font-family="DejaVu Sans, sans-serif" font-size="{size:.1f}" font-weight="900" letter-spacing="{size * 0.025:.1f}">POCKET</text>
      <text x="0" y="{size * 0.94:.1f}" fill="{accent}" stroke="{INK}" stroke-width="{size * 0.035:.1f}" paint-order="stroke" font-family="DejaVu Sans, sans-serif" font-size="{size:.1f}" font-weight="900" letter-spacing="{size * 0.018:.1f}">CIRCUIT</text>
    </g>
    """


def car(x: float, y: float, scale: float, angle: float) -> str:
    width = 130 * scale
    height = 220 * scale
    return f"""
    <g transform="translate({x:.1f} {y:.1f}) rotate({angle:.1f})" filter="url(#shadow)">
      <g opacity="0.5" stroke="{CREAM}" stroke-width="{8 * scale:.1f}" stroke-linecap="round">
        <path d="M {-width * 0.28:.1f} {height * 0.62:.1f} L {-width * 0.48:.1f} {height * 1.2:.1f}"/>
        <path d="M {width * 0.28:.1f} {height * 0.62:.1f} L {width * 0.48:.1f} {height * 1.2:.1f}"/>
      </g>
      <rect x="{-width * 0.62:.1f}" y="{-height * 0.34:.1f}" width="{width * 0.24:.1f}" height="{height * 0.42:.1f}" rx="{width * 0.1:.1f}" fill="#11151F"/>
      <rect x="{width * 0.38:.1f}" y="{-height * 0.34:.1f}" width="{width * 0.24:.1f}" height="{height * 0.42:.1f}" rx="{width * 0.1:.1f}" fill="#11151F"/>
      <rect x="{-width * 0.62:.1f}" y="{height * 0.13:.1f}" width="{width * 0.24:.1f}" height="{height * 0.42:.1f}" rx="{width * 0.1:.1f}" fill="#11151F"/>
      <rect x="{width * 0.38:.1f}" y="{height * 0.13:.1f}" width="{width * 0.24:.1f}" height="{height * 0.42:.1f}" rx="{width * 0.1:.1f}" fill="#11151F"/>
      <path d="M {-width * 0.42:.1f} {height * 0.46:.1f} Q {-width * 0.5:.1f} 0 {-width * 0.25:.1f} {-height * 0.48:.1f} Q 0 {-height * 0.7:.1f} {width * 0.25:.1f} {-height * 0.48:.1f} Q {width * 0.5:.1f} 0 {width * 0.42:.1f} {height * 0.46:.1f} Q 0 {height * 0.65:.1f} {-width * 0.42:.1f} {height * 0.46:.1f} Z" fill="{CORAL}" stroke="{CREAM}" stroke-width="{7 * scale:.1f}"/>
      <path d="M {-width * 0.27:.1f} {-height * 0.22:.1f} Q 0 {-height * 0.42:.1f} {width * 0.27:.1f} {-height * 0.22:.1f} L {width * 0.2:.1f} {height * 0.08:.1f} L {-width * 0.2:.1f} {height * 0.08:.1f} Z" fill="{BLUE}" stroke="{INK}" stroke-width="{5 * scale:.1f}"/>
      <rect x="{-width * 0.055:.1f}" y="{-height * 0.56:.1f}" width="{width * 0.11:.1f}" height="{height * 1.05:.1f}" rx="{width * 0.05:.1f}" fill="{AMBER}"/>
      <circle cx="{-width * 0.24:.1f}" cy="{-height * 0.48:.1f}" r="{width * 0.08:.1f}" fill="{CREAM}"/>
      <circle cx="{width * 0.24:.1f}" cy="{-height * 0.48:.1f}" r="{width * 0.08:.1f}" fill="{CREAM}"/>
    </g>
    """


def room_objects(width: int, height: int, vertical: bool) -> str:
    unit = min(width, height)
    mug_x = width * (0.76 if not vertical else 0.72)
    mug_y = height * (0.2 if not vertical else 0.33)
    radius = unit * (0.13 if not vertical else 0.16)
    return f"""
    <g opacity="0.95">
      <circle cx="{mug_x:.1f}" cy="{mug_y:.1f}" r="{radius:.1f}" fill="#E8DFCF" stroke="{BLUE}" stroke-width="{unit * 0.018:.1f}"/>
      <circle cx="{mug_x:.1f}" cy="{mug_y:.1f}" r="{radius * 0.7:.1f}" fill="#27344A"/>
      <path d="M {mug_x + radius * 0.76:.1f} {mug_y - radius * 0.45:.1f} Q {mug_x + radius * 1.65:.1f} {mug_y:.1f} {mug_x + radius * 0.76:.1f} {mug_y + radius * 0.45:.1f}" fill="none" stroke="#E8DFCF" stroke-width="{unit * 0.05:.1f}" stroke-linecap="round"/>
      <g transform="translate({width * 0.76:.1f} {height * 0.75:.1f}) rotate(-9)">
        <rect x="{-unit * 0.24:.1f}" y="{-unit * 0.095:.1f}" width="{unit * 0.48:.1f}" height="{unit * 0.19:.1f}" rx="{unit * 0.018:.1f}" fill="#D9DDE4" stroke="#7A8595" stroke-width="{unit * 0.012:.1f}"/>
        <g fill="#5D687A">
          <rect x="{-unit * 0.19:.1f}" y="{-unit * 0.055:.1f}" width="{unit * 0.065:.1f}" height="{unit * 0.05:.1f}" rx="4"/>
          <rect x="{-unit * 0.095:.1f}" y="{-unit * 0.055:.1f}" width="{unit * 0.065:.1f}" height="{unit * 0.05:.1f}" rx="4"/>
          <rect x="0" y="{-unit * 0.055:.1f}" width="{unit * 0.065:.1f}" height="{unit * 0.05:.1f}" rx="4"/>
          <rect x="{unit * 0.095:.1f}" y="{-unit * 0.055:.1f}" width="{unit * 0.065:.1f}" height="{unit * 0.05:.1f}" rx="4"/>
        </g>
      </g>
      <g transform="translate({width * 0.13:.1f} {height * 0.78:.1f}) rotate(16)">
        <rect x="{-unit * 0.21:.1f}" y="{-unit * 0.05:.1f}" width="{unit * 0.42:.1f}" height="{unit * 0.1:.1f}" rx="{unit * 0.015:.1f}" fill="{AMBER}"/>
        <g stroke="{INK}" stroke-width="{unit * 0.008:.1f}">
          <path d="M {-unit * 0.16:.1f} {-unit * 0.05:.1f} V {unit * 0.01:.1f}"/>
          <path d="M {-unit * 0.08:.1f} {-unit * 0.05:.1f} V {unit * 0.02:.1f}"/>
          <path d="M 0 {-unit * 0.05:.1f} V {unit * 0.01:.1f}"/>
          <path d="M {unit * 0.08:.1f} {-unit * 0.05:.1f} V {unit * 0.02:.1f}"/>
        </g>
      </g>
    </g>
    """


def scene(width: int, height: int, *, vertical: bool = False, show_logo: bool = True, tagline: str = "TINY RACING. BIG STAKES.") -> str:
    unit = min(width, height)
    if vertical:
        track_path = f"M {width * 0.18:.1f} {height * 1.12:.1f} C {width * 0.05:.1f} {height * 0.78:.1f}, {width * 0.82:.1f} {height * 0.72:.1f}, {width * 0.62:.1f} {height * 0.42:.1f} S {width * 0.36:.1f} {height * 0.02:.1f}, {width * 0.78:.1f} {-height * 0.1:.1f}"
        car_x, car_y, car_scale, angle = width * 0.42, height * 0.58, unit / 720, -28
        brand = logo(width * 0.08, height * 0.14, unit * 0.1, False) if show_logo else ""
        tag_y = height * 0.92
    else:
        track_path = f"M {-width * 0.08:.1f} {height * 0.72:.1f} C {width * 0.16:.1f} {height * 0.38:.1f}, {width * 0.42:.1f} {height * 0.93:.1f}, {width * 0.61:.1f} {height * 0.58:.1f} S {width * 0.8:.1f} {height * 0.16:.1f}, {width * 1.08:.1f} {height * 0.34:.1f}"
        car_x, car_y, car_scale, angle = width * 0.53, height * 0.67, unit / 650, -63
        brand = logo(width * 0.055, height * 0.19, unit * 0.11, True) if show_logo else ""
        tag_y = height * 0.9
    tagline_text = html.escape(tagline)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
    {defs()}
    <rect width="{width}" height="{height}" fill="url(#night)"/>
    <rect width="{width}" height="{height}" fill="url(#grid)"/>
    <circle cx="{width * 0.84:.1f}" cy="{height * 0.02:.1f}" r="{unit * 0.55:.1f}" fill="url(#sun)"/>
    <path d="{track_path}" fill="none" stroke="#0B1220" stroke-width="{unit * 0.32:.1f}" stroke-linecap="round"/>
    <path d="{track_path}" fill="none" stroke="{PAPER}" stroke-width="{unit * 0.25:.1f}" stroke-linecap="round"/>
    <path d="{track_path}" fill="none" stroke="{CORAL}" stroke-width="{unit * 0.018:.1f}" stroke-dasharray="{unit * 0.055:.1f} {unit * 0.045:.1f}" stroke-linecap="round"/>
    {room_objects(width, height, vertical)}
    {car(car_x, car_y, car_scale, angle)}
    <rect x="0" y="0" width="{width * (0.86 if vertical else 0.74):.1f}" height="{height * (0.34 if vertical else 0.36):.1f}" fill="url(#titleFade)" mask="url(#titleMask)"/>
    {brand}
    <text x="{width * (0.08 if vertical else 0.06):.1f}" y="{tag_y:.1f}" fill="{CREAM}" font-family="DejaVu Sans, sans-serif" font-size="{unit * 0.038:.1f}" font-weight="700" letter-spacing="{unit * 0.008:.1f}">{tagline_text}</text>
    <rect x="0" y="0" width="{width}" height="{height}" fill="none" stroke="{AMBER}" stroke-width="{max(4, unit * 0.012):.1f}"/>
    </svg>"""


def transparent_logo(width: int, height: int) -> str:
    size = min(width * 0.14, height * 0.23)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
    {defs()}
    <g filter="url(#shadow)">{logo(width * 0.18, height * 0.38, size, False)}</g>
    </svg>"""


def community_icon(size: int) -> str:
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">
    {defs()}
    <rect width="{size}" height="{size}" rx="{size * 0.18:.1f}" fill="url(#night)"/>
    <path d="M {-size * 0.1:.1f} {size * 0.78:.1f} C {size * 0.22:.1f} {size * 0.35:.1f}, {size * 0.55:.1f} {size * 0.9:.1f}, {size * 1.1:.1f} {size * 0.28:.1f}" fill="none" stroke="{PAPER}" stroke-width="{size * 0.22:.1f}" stroke-linecap="round"/>
    {car(size * 0.53, size * 0.57, size / 720, -52)}
    <text x="{size * 0.1:.1f}" y="{size * 0.24:.1f}" fill="{CREAM}" font-family="DejaVu Sans, sans-serif" font-size="{size * 0.19:.1f}" font-weight="900">P / C</text>
    <rect x="3" y="3" width="{size - 6}" height="{size - 6}" rx="{size * 0.16:.1f}" fill="none" stroke="{AMBER}" stroke-width="6"/>
    </svg>"""


def write_asset(relative_png: str, width: int, height: int, svg: str) -> None:
    png_path = MEDIA_ROOT / relative_png
    svg_path = SOURCE_ROOT / (Path(relative_png).stem + ".svg")
    png_path.parent.mkdir(parents=True, exist_ok=True)
    normalized_svg = "\n".join(line.rstrip() for line in svg.splitlines()) + "\n"
    svg_path.write_text(normalized_svg, encoding="utf-8")
    subprocess.run(
        ["magick", "-background", "none", str(svg_path), str(png_path)],
        check=True,
    )
    dimensions = subprocess.check_output(
        ["identify", "-format", "%wx%h", str(png_path)],
        text=True,
    )
    expected = f"{width}x{height}"
    if dimensions != expected:
        raise RuntimeError(f"{png_path} rendered at {dimensions}, expected {expected}")
    print(f"STEAM_ART {expected} {png_path.relative_to(ROOT)}")


def main() -> int:
    assets = [
        ("capsules/header_capsule.png", 920, 430, scene(920, 430)),
        ("capsules/small_capsule.png", 462, 174, scene(462, 174, tagline="")),
        ("capsules/main_capsule.png", 1232, 706, scene(1232, 706)),
        ("capsules/vertical_capsule.png", 748, 896, scene(748, 896, vertical=True)),
        ("capsules/library_capsule.png", 600, 900, scene(600, 900, vertical=True)),
        ("capsules/library_hero.png", 3840, 1240, scene(3840, 1240, show_logo=False, tagline="")),
        ("capsules/library_logo.png", 1280, 720, transparent_logo(1280, 720)),
        ("capsules/community_icon.png", 184, 184, community_icon(184)),
        ("capsules/page_background.png", 1438, 810, scene(1438, 810, show_logo=False, tagline="")),
        ("trailer/opening_card.png", 1920, 1080, scene(1920, 1080, tagline="TINY RACING. BIG STAKES.")),
        ("trailer/ending_card.png", 1920, 1080, scene(1920, 1080, tagline="NINE EVENTS / THREE ROOMS / ONE NIGHT")),
    ]
    for relative_png, width, height, svg in assets:
        write_asset(relative_png, width, height, svg)
    print("STEAM_ART PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
