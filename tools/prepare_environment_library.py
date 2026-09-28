"""Prepare the complete approved-source library and its physical asset contract."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from prepare_environment_pilot import extract_sprite
from prepare_track_art import save_png

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'data/world_prop_art.json'
TEXTURES = ROOT / 'assets/textures'
SOURCES = ROOT / 'assets/source'
GRAINS = {
    'kitchen': {
        'floor': ['world_materials/kitchen_counter.png','world_materials/kitchen_sage_tile.png','world_materials/kitchen_ceramic.png','world_materials/kitchen_stone.png','kitchen/counter_surface.png','kitchen/counter_surface_bright.png','kitchen/track_surface.png'],
        'island': ['world_materials/kitchen_board.png','kitchen/counter_edge.png'],
    },
    'workshop': {
        'floor': ['world_materials/workshop_bench.png','world_materials/workshop_plywood.png','world_materials/workshop_oiled.png','world_materials/workshop_paint.png','imagine/floor_wood.png','imagine/track_wood.png'],
        'island': ['world_materials/workshop_mat.png','imagine/workshop_edge_bright.png','edge_dressing/wood_grain_faint.png'],
    },
    'office': {
        'floor': ['world_materials/office_desk.png','world_materials/office_laminate.png','world_materials/office_walnut.png','world_materials/office_deskmat.png','imagine/floor_pad.png','imagine/track_pad.png'],
        'island': ['world_materials/office_pad.png','imagine/office_edge_bright.png','edge_dressing/desk_pad_grid.png'],
    },
}
PHYSICAL_ALPHA_THRESHOLD = 21  # First8-bit alpha above the runtime0.08 threshold.


def source_image(entry):
    source = entry['source']
    if 'prepared' in source:
        return Image.open(TEXTURES/source['prepared']).convert('RGBA')
    image = Image.open(SOURCES/source['path']).convert('RGB')
    columns = source['columns']
    cell = source['cell']
    width, height = image.width // columns, image.height // columns
    crop = source.get('crop', [cell % columns * width, cell // columns * height,
                               (cell % columns + 1) * width, (cell // columns + 1) * height])
    return extract_sprite(image.crop(crop), entry.get('matte_cleanup_pixels', 2))


def utility_image(kind):
    image = Image.new('RGBA', (256, 256))
    draw = ImageDraw.Draw(image)
    if kind == 'shadow_circle': draw.ellipse((30, 65, 226, 191), fill=(255, 255, 255, 200))
    elif kind == 'shadow_rect': draw.rounded_rectangle((25, 55, 231, 201), radius=24, fill=(255, 255, 255, 200))
    elif kind == 'shadow_strip': draw.rounded_rectangle((12, 105, 244, 150), radius=15, fill=(255, 255, 255, 180))
    elif kind == 'skid': draw.line((20, 128, 236, 128), fill=(62, 55, 46, 70), width=5)
    elif kind == 'checker':
        for row in range(2):
            for column in range(8):
                draw.rectangle((column*32,row*128,(column+1)*32,(row+1)*128), fill='#eee6ce' if (row+column)%2 else '#252527')
    return image.filter(ImageFilter.GaussianBlur(8)) if kind.startswith('shadow') else image


def install_plan(path):
    entries = json.loads(Path(path).read_text())['assets']
    for entry in entries:
        entry['outputs'] = [p.removesuffix('.jpg')+'.png' if p.endswith('.jpg') else p for p in entry['outputs']]
    for theme, roles in GRAINS.items():
        for role, outputs in roles.items():
            entries.append({'id':f'{theme}_{role}_grain','themes':[theme], 'style':'overhead_gouache_v1','perspective':'orthographic_overhead', 'kind':'material', 'roles':['surface'], 'length_mm':700, 'zones':['floor','island'], 'visual_weight':0,'detail_tier':'quiet','scale_tier':'surface','collision':'flat','shadow':'none','max_repeats':1,'clearance_mm':0,'scenery':False,'source':{'prepared':f'environment_pilot/{theme}_{role}.png','generator':'HouseholdSurfaceMaterials'},'outputs':outputs})
    utilities={'shadow_circle':'edge_dressing/shadow_soft_circle.png','shadow_rect':'edge_dressing/shadow_soft_rect.png','shadow_strip':'edge_dressing/shadow_strip.png','skid':'kitchen/skid_mark.png','checker':'kitchen/start_finish.png'}
    for kind, output in utilities.items():
        entries.append({'id':kind,'themes':['kitchen','workshop','office'],'style':'overhead_gouache_v1','perspective':'orthographic_overhead','kind':'utility','roles':['utility'],'length_mm':64,'zones':['overlay'],'visual_weight':0,'detail_tier':'quiet','scale_tier':'utility','collision':'flat','shadow':'none','max_repeats':1,'clearance_mm':0,'scenery':False,'source':{'generator':kind},'outputs':[output]})
    seen = set()
    for entry in entries:
        if entry['id'] in seen:
            entry['id'] += '_'+hashlib.sha256(entry['outputs'][0].encode()).hexdigest()[:6]
        seen.add(entry['id'])
    return entries


def prepare(entries):
    outputs = set()
    for entry in entries:
        if entry.get('kind') == 'utility': image = utility_image(entry['source']['generator'])
        else: image = source_image(entry)
        alpha = np.asarray(image.getchannel('A'))
        y, x = np.where(alpha >= (1 if entry.get('kind') == 'utility' else PHYSICAL_ALPHA_THRESHOLD))
        if not len(x): raise ValueError(f"Empty sprite: {entry['id']}")
        visible_width, visible_height = int(x.max()-x.min()+1), int(y.max()-y.min()+1)
        ratio = float(entry['length_mm']) / max(visible_width, visible_height)
        entry['dimensions_mm'] = [round(visible_width*ratio,4), round(visible_height*ratio,4)]
        entry['width_mm'] = round(min(entry['dimensions_mm']),4)
        entry['content_bounds_px'] = [int(x.min()),int(y.min()),visible_width,visible_height]
        mean = np.asarray(image.convert('RGB'))[alpha >= 128].mean(axis=0) if entry.get('kind') != 'utility' else np.array([64,55,45])
        entry['average_color'] = '#'+''.join(f'{round(float(channel)):02x}' for channel in mean)
        entry['scenery'] = entry.get('scenery', True) and entry.get('kind') not in ['material','utility']
        for output in entry['outputs']:
            if output in outputs: raise ValueError(f'Duplicate asset output {output}')
            save_png(image, TEXTURES/output)
            outputs.add(output)
    temporary = MANIFEST.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(entries,indent=2)+'\n')
    temporary.replace(MANIFEST)
    print(f"ENVIRONMENT_LIBRARY_PREPARED assets={len(entries)} outputs={len(outputs)} contract=overhead_gouache_v1")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--install-plan')
    args = parser.parse_args()
    prepare(install_plan(args.install_plan) if args.install_plan else json.loads(MANIFEST.read_text()))
