"""Shared image utilities and compatibility entry point for the painted library."""
import json
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]


def repeating_material(image: Image.Image) -> Image.Image:
    inset = max(2, round(min(image.size) * 0.035))
    image = image.crop((inset, inset, image.width-inset, image.height-inset))
    image = image.convert('RGB').resize((256, 256), Image.Resampling.LANCZOS)
    result = Image.new('RGB', (512, 512))
    result.paste(image, (0, 0))
    result.paste(ImageOps.mirror(image), (256, 0))
    result.paste(ImageOps.flip(image), (0, 256))
    result.paste(ImageOps.flip(ImageOps.mirror(image)), (256, 256))
    return result


def save_png(image: Image.Image, path: Path) -> None:
    buffer = BytesIO()
    image.save(buffer, format='PNG')
    content = buffer.getvalue()
    if path.exists() and path.read_bytes() == content:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


def main() -> None:
    from prepare_environment_library import prepare

    definitions = json.loads((ROOT / 'data/world_prop_art.json').read_text())
    prepare(definitions)


if __name__ == '__main__':
    main()
