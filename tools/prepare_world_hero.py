"""Prepare selected original source artwork as normalized Godot sprites."""

from collections import deque
from colorsys import rgb_to_hsv
from pathlib import Path

from PIL import Image, ImageFilter, ImageStat

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/textures"
SELECTION = {
    "kitchen_hero/hero_kitchen_mug.png": {"source": "assets/source/kitchen_hero/mug.jpg", "mode": "hue"},
    "kitchen_hero/hero_kitchen_plate_stack.png": {"source": "assets/source/kitchen_hero/plate_stack.jpg", "mode": "hue"},
    "kitchen_hero/hero_kitchen_tea_board.png": {"source": "assets/source/kitchen_hero/tea_board_topdown.jpg", "mode": "hue"},
    "workshop_hero/hero_workshop_toolbox.png": {"source": "assets/source/workshop_hero/parts_tin.jpg", "mode": "hue"},
    "workshop_hero/hero_workshop_wrench.png": {"source": "assets/textures/imagine/workshop_toolbox_top.jpg", "mode": "flood", "crop": (840, 309, 1007, 840), "holes": [(907, 749)], "solid_center": False},
    "workshop_hero/hero_workshop_paint_can.png": {"source": "assets/textures/imagine/workshop_paint_can.png", "mode": "alpha"},
    "office_hero/hero_office_keyboard.png": {"source": "assets/textures/imagine/office_keyboard_top.jpg", "mode": "flood", "crop": (48, 302, 980, 864)},
    "office_hero/hero_office_keycap.png": {"source": "assets/textures/imagine/office_keycap.png", "mode": "alpha"},
    "office_hero/hero_office_notebook.png": {"source": "assets/source/office_hero/notebook.jpg", "mode": "flood"},
}


def matte(image: Image.Image, key: list[float], mode: str, holes: list[tuple[int, int]]) -> Image.Image:
    key_hue, key_saturation, _ = rgb_to_hsv(*(value / 255 for value in key))
    alpha = Image.new("L", image.size)
    mask = []
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue = pixels[x, y]
            hue, saturation, _ = rgb_to_hsv(red / 255, green / 255, blue / 255)
            distance = min(abs(hue - key_hue), 1 - abs(hue - key_hue))
            is_key = distance < 0.065 and saturation > max(0.35, key_saturation * 0.6)
            if mode == "flood":
                is_key = distance < 0.085 and saturation > 0.45 and max(abs(value - background) for value, background in zip((red, green, blue), key)) < 52
            mask.append(0 if is_key else 255)
    if mode == "flood":
        width, height = image.size
        removed = bytearray(width * height)
        for x, y in holes:
            if not (0 <= x < width and 0 <= y < height) or mask[y * width + x] != 0:
                raise ValueError("The configured hole seed is not chroma background")
        seeds = [(x, 0) for x in range(width)] + [(x, height - 1) for x in range(width)]
        seeds += [(0, y) for y in range(height)] + [(width - 1, y) for y in range(height)] + holes
        pending = deque()
        for x, y in seeds:
            if 0 <= x < width and 0 <= y < height and mask[y * width + x] == 0:
                pending.append((x, y))
        while pending:
            x, y = pending.popleft()
            index = y * width + x
            if removed[index] or mask[index] != 0:
                continue
            removed[index] = 1
            for nx, ny in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]:
                if 0 <= nx < width and 0 <= ny < height:
                    pending.append((nx, ny))
        mask = [0 if value else 255 for value in removed]
    alpha.putdata(mask)
    return alpha.filter(ImageFilter.MinFilter(3))


def prepare(spec: dict, destination: Path) -> None:
    source = ROOT / spec["source"]
    original = Image.open(source).convert("RGBA")
    key = ImageStat.Stat(original.convert("RGB").crop((0, 0, 32, 32))).mean
    crop = spec.get("crop", (0, 0, original.width, original.height))
    original = original.crop(crop)
    image = original.convert("RGB")
    if spec["mode"] == "alpha":
        alpha = original.getchannel("A")
    else:
        holes = [(x - crop[0], y - crop[1]) for x, y in spec.get("holes", [])]
        alpha = matte(image, key, spec["mode"], holes)
    rgba = image.convert("RGBA")
    rgba.putalpha(alpha)
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError(f"No foreground found in {source.name}")
    sprite = rgba.crop(bounds)
    sprite.thumbnail((448, 448), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (512, 512))
    canvas.alpha_composite(sprite, ((512 - sprite.width) // 2, (512 - sprite.height) // 2))
    if spec.get("solid_center", True) and canvas.getpixel((256, 256))[3] < 240:
        raise ValueError(f"Keying removed the solid interior of {source.name}")
    canvas.save(destination)


def main() -> None:
    for destination, spec in SELECTION.items():
        (OUTPUT / destination).parent.mkdir(parents=True, exist_ok=True)
        prepare(spec, OUTPUT / destination)
        print(f"PREPARED {destination}")


if __name__ == "__main__":
    main()
