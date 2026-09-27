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


def extract_sprite(image: Image.Image) -> Image.Image:
    rgb = np.asarray(image.convert("RGB"))
    hsv = np.asarray(image.convert("HSV"))
    # The newly generated backgrounds vary in brightness, but not magenta hue.
    keyed = (hsv[:, :, 0] > 210) & (hsv[:, :, 0] < 250) & (hsv[:, :, 1] > 115)
    opaque = ~keyed
    labels, _ = ndimage.label(opaque)
    areas = np.bincount(labels.ravel())
    areas[0] = 0
    opaque &= areas[labels] > max(8, areas.max() * 0.005)
    interior = ndimage.binary_erosion(opaque, iterations=2)
    if not interior.any():
        raise ValueError("No foreground in pilot crop")
    # Bleed real paint into the antialiasing band, never chroma-key pink.
    _, nearest = ndimage.distance_transform_edt(~interior, return_indices=True)
    clean = rgb[nearest[0], nearest[1]]
    alpha = Image.fromarray((opaque * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.45))
    result = Image.fromarray(clean).convert("RGBA")
    result.putalpha(alpha)
    result = result.crop(alpha.getbbox())
    result.thumbnail((CONTENT_SIZE, CONTENT_SIZE), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE))
    canvas.alpha_composite(result, ((CANVAS_SIZE - result.width) // 2, (CANVAS_SIZE - result.height) // 2))
    return canvas


def main() -> None:
    manifest = json.loads(MANIFEST.read_text())
    for theme, definition in manifest["themes"].items():
        for asset in definition["assets"].values():
            with Image.open(SOURCE / asset["source"]) as source:
                sprite = extract_sprite(source.crop(asset["crop"]))
            save_png(sprite, DESTINATION / f"{theme}_{asset['name']}.png")
        with Image.open(SOURCE / definition["floor_source"]) as source:
            # Reuse the seamless-wrap utility only; painted mode retains source colors.
            material = repeating_material(source, style="painted")
        save_png(material, DESTINATION / f"{theme}_floor.png")
    print("ENVIRONMENT_PILOT_ART PASS: 12 fresh sprites, 3 floor materials")


if __name__ == "__main__":
    main()
