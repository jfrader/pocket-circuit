"""Extract the fresh review pilot without restyling or quantizing its paint."""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

from prepare_track_art import repeating_material, save_png

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/environment-pilot"
DESTINATION = ROOT / "assets/textures/environment_pilot"
MANIFEST = Path(__file__).with_name("environment_pilot.json")
CONTENT_SIZE = 480
CANVAS_SIZE = 512


def extract_sprite(image: Image.Image, matte_cleanup_pixels: int = 2) -> Image.Image:
    rgb = np.asarray(image.convert("RGB"))
    hsv = np.asarray(image.convert("HSV"))
    # The newly generated backgrounds vary in brightness, but not magenta hue.
    keyed = (hsv[:, :, 0] > 210) & (hsv[:, :, 0] < 250) & (hsv[:, :, 1] > 115)
    opaque = ~keyed
    labels, _ = ndimage.label(opaque)
    areas = np.bincount(labels.ravel())
    areas[0] = 0
    opaque &= areas[labels] > max(8, areas.max() * 0.005)
    if matte_cleanup_pixels < 1:
        raise ValueError("Matte cleanup must keep a positive interior margin")
    interior = ndimage.binary_erosion(opaque, iterations=matte_cleanup_pixels)
    if not interior.any():
        raise ValueError("No foreground in pilot crop")
    # Bleed real paint into the antialiasing band, never chroma-key pink.
    _, nearest = ndimage.distance_transform_edt(~interior, return_indices=True)
    clean = rgb[nearest[0], nearest[1]]
    alpha = Image.fromarray((opaque * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.45))
    # Unmix residual key color in translucent painted edges, rather than retaining
    # pink pixels as opaque flour, paper or cloth texture.
    border = np.concatenate((rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1])).astype(float)
    background = np.median(border, axis=0)
    key_chroma = max(1.0, min(background[0], background[2]) - background[1])
    foreground = clean.astype(float)
    spill = np.maximum(0.0, np.minimum(foreground[:, :, 0], foreground[:, :, 2]) - foreground[:, :, 1]) / key_chroma
    key_hue = (hsv[:, :, 0] > 210) & (hsv[:, :, 0] < 250)
    coverage = 1.0 - np.clip(np.where(key_hue, spill, 0.0), 0.0, 0.95)
    foreground = (foreground - (1.0 - coverage[:, :, None]) * background) / coverage[:, :, None]
    clean = np.clip(foreground, 0, 255).astype(np.uint8)
    alpha = Image.fromarray((np.asarray(alpha).astype(float) * coverage).astype(np.uint8))
    result = Image.fromarray(clean).convert("RGBA")
    result.putalpha(alpha)
    result = result.crop(alpha.getbbox())
    result.thumbnail((CONTENT_SIZE, CONTENT_SIZE), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE))
    canvas.alpha_composite(result, ((CANVAS_SIZE - result.width) // 2, (CANVAS_SIZE - result.height) // 2))
    return canvas


def main() -> None:
    manifest = json.loads(MANIFEST.read_text())
    sprites = 0
    materials = 0
    for theme, definition in manifest["themes"].items():
        for asset in (definition["assets"] | definition.get("support_assets", {})).values():
            with Image.open(SOURCE / asset["source"]) as source:
                sprite = extract_sprite(source.crop(asset["crop"]), asset.get("matte_cleanup_pixels", 2))
            save_png(sprite, DESTINATION / f"{theme}_{asset['name']}.png")
            sprites += 1
        for role in ("floor", "island"):
            with Image.open(SOURCE / definition[f"{role}_source"]) as source:
                material = repeating_material(source)
            save_png(material, DESTINATION / f"{theme}_{role}.png")
            materials += 1
    print(f"ENVIRONMENT_PILOT_ART PASS: {sprites} fresh sprites, {materials} materials")


if __name__ == "__main__":
    main()
