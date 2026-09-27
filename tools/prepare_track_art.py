"""Build transparent track sprites and repeating materials from the reviewed Imagine sheets."""
import json
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/source/track-art'
TEXTURES = ROOT / 'assets/textures'
CANVAS = 512
CONTENT = 448
PIXEL_CONTENT = 96
SPRITE_COLORS = 12
MATERIALS = [
    'kitchen_board', 'kitchen_ceramic', 'kitchen_counter', 'kitchen_sage_tile',
    'kitchen_stone', 'office_desk', 'office_deskmat', 'office_laminate',
    'office_pad', 'office_walnut', 'workshop_bench', 'workshop_mat',
    'workshop_oiled', 'workshop_paint', 'workshop_plywood',
]
DECALS = [
    ['grip_patches/soapy_spill.png', 'kitchen/wet_spill.png', 'kitchen/spill_decal.png'],
    ['grip_patches/oil_slick_small.png', 'imagine/oil_stain.png'],
    ['grip_patches/kitchen_flour_dust.png'],
    ['grip_patches/kitchen_syrup_smear.png'],
    ['grip_patches/sawdust_patch.png', 'imagine/sawdust_patch.png', 'edge_dressing/sawdust_bit.png'],
    ['grip_patches/coffee_ring.png', 'imagine/stain_ring.png'],
    ['grip_patches/paper_scatter.png', 'imagine/paper_sheet.png'],
    ['grip_patches/workshop_metal_filings.png'],
    ['grip_patches/workshop_paint_smear.png'],
    ['grip_patches/office_eraser_dust.png'],
    ['grip_patches/office_ink_blot.png'],
    ['imagine/crumb_cluster.png', 'kitchen/crumb_cluster_01.png', 'kitchen/crumb_cluster_02.png', 'kitchen/cereal_scatter.png', 'edge_dressing/crumb_micro_01.png', 'edge_dressing/crumb_micro_02.png'],
    ['kitchen/water_droplet_01.png', 'kitchen/water_droplet_02.png', 'edge_dressing/droplet_micro.png'],
    ['kitchen/wood_scratch.png', 'edge_dressing/wood_grain_faint.png'],
    ['edge_dressing/fiber_strand.png'],
    ['edge_dressing/worn_floor_hint.png'],
]


def cell(image: Image.Image, index: int, columns: int = 4) -> Image.Image:
    x, y = index % columns, index // columns
    return image.crop((x * image.width // columns, y * image.height // columns,
                       (x + 1) * image.width // columns, (y + 1) * image.height // columns))


def transparent_sprite(image: Image.Image, clean_fragments: bool = True) -> Image.Image:
    rgb = np.asarray(image.convert('RGB'), dtype=np.float32)
    hsv = np.asarray(image.convert('HSV'))
    r, g, b = rgb.transpose(2, 0, 1)
    # Remove the keyed field (including enclosed holes) rather than treating
    # only the border as background. Cream/steel and red enamel stay intact.
    key = (hsv[:, :, 0] > 211) & (hsv[:, :, 0] < 250) & (r > g * 1.13) & (b > g * 0.92)
    alpha = np.where(key, 0, 255).astype(np.uint8)
    if clean_fragments:
        labels, _ = ndimage.label(alpha)
        areas = np.bincount(labels.ravel())
        areas[0] = 0
        alpha[areas[labels] < max(12, areas.max() * 0.04)] = 0
    rgba = np.dstack((rgb.astype(np.uint8), alpha))
    result = Image.fromarray(rgba)
    bounds = result.getbbox()
    if bounds is None:
        raise ValueError('Empty keyed sprite')
    result = result.crop(bounds)
    low_scale = PIXEL_CONTENT / max(result.size)
    low_size = (max(1, round(result.width * low_scale)), max(1, round(result.height * low_scale)))
    result = result.resize(low_size, Image.Resampling.LANCZOS)
    alpha = result.getchannel('A').point(lambda value: 255 if value >= 128 else 0)
    colors = result.convert('RGB').quantize(colors=SPRITE_COLORS, method=Image.Quantize.MEDIANCUT).convert('RGBA')
    colors.putalpha(alpha)
    pixel_scale = max(1, CONTENT // max(colors.size))
    result = colors.resize((colors.width * pixel_scale, colors.height * pixel_scale), Image.Resampling.NEAREST)
    canvas = Image.new('RGBA', (CANVAS, CANVAS))
    canvas.alpha_composite(result, ((CANVAS-result.width)//2, (CANVAS-result.height)//2))
    return canvas


def repeating_material(image: Image.Image) -> Image.Image:
    # Mirrored quadrants give exact wrap continuity without a blurred seam or
    # baking light direction into an albedo tile.
    inset = max(2, round(min(image.size) * 0.035))
    image = image.crop((inset, inset, image.width-inset, image.height-inset))
    image = image.convert('RGB').resize((64, 64), Image.Resampling.LANCZOS)
    image = image.quantize(colors=SPRITE_COLORS, method=Image.Quantize.MEDIANCUT).convert('RGB')
    image = image.resize((256, 256), Image.Resampling.NEAREST)
    result = Image.new('RGB', (512, 512))
    result.paste(image, (0, 0))
    result.paste(ImageOps.mirror(image), (256, 0))
    result.paste(ImageOps.flip(image), (0, 256))
    result.paste(ImageOps.flip(ImageOps.mirror(image)), (256, 256))
    return result


def apply_finish(image: Image.Image, finish: str) -> Image.Image:
    if finish != 'matte_metal':
        return image
    pixels = np.asarray(image.convert('RGBA')).copy()
    rgb = pixels[:, :, :3]
    opaque = pixels[:, :, 3] > 0
    neutral = (rgb.max(axis=2) - rgb.min(axis=2) < 42) & opaque
    luminance = rgb.mean(axis=2)
    shades = np.asarray(((42, 48, 51), (82, 90, 94), (122, 132, 136), (160, 169, 172)), dtype=np.uint8)
    shade_index = np.digitize(luminance, (64, 112, 166))
    rgb[neutral] = shades[shade_index[neutral]]
    return Image.fromarray(pixels)


def save_png(image: Image.Image, path: Path) -> None:
    buffer = BytesIO()
    image.save(buffer, format='PNG')
    content = buffer.getvalue()
    if path.exists() and path.read_bytes() == content:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


def main() -> None:
    definitions = json.loads((ROOT / 'data/world_prop_art.json').read_text())
    sheets = {entry['sheet']: Image.open(SOURCE / entry['sheet']) for entry in definitions}
    count = 0
    for entry in definitions:
        sprite = transparent_sprite(cell(sheets[entry['sheet']], entry['cell'], entry.get('columns', 4)))
        sprite = apply_finish(sprite, entry.get('finish', ''))
        for output in entry['outputs']:
            path = TEXTURES / output
            save_png(sprite, path)
            count += 1
    materials = Image.open(SOURCE / 'materials-kit.jpg')
    for index, name in enumerate(MATERIALS):
        save_png(repeating_material(cell(materials, index)), TEXTURES / 'world_materials' / f'{name}.png')
    decals = Image.open(SOURCE / 'surface-details.png')
    for index, outputs in enumerate(DECALS):
        sprite = transparent_sprite(cell(decals, index), clean_fragments=False)
        for output in outputs:
            save_png(sprite, TEXTURES / output)
            count += 1
    print(f'Prepared {count} track sprites/decals and {len(MATERIALS)} seamless materials')


if __name__ == '__main__':
    main()
