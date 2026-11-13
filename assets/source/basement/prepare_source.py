"""Trace the authorized beige-matte sheet into keyed source crops; retain its paint."""
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from prepare_track_art import repeating_material, save_png
from prepare_environment_pilot import extract_sprite

HERE = Path(__file__).resolve().parent
sheet = Image.open(HERE / 'basement_props_sheet.jpg').convert('RGB')
rgb = np.asarray(sheet).astype(float)
red, green, blue = rgb[:,:,0], rgb[:,:,1], rgb[:,:,2]
# Sheet-space silhouette outlines exclude cell dividers, lettering and cast shadows.
outlines = {
    'boiler': [(70,216),(78,176),(103,142),(139,124),(178,121),(211,140),(236,178),(247,225),(239,270),(212,307),(174,321),(130,310),(91,283),(74,249)],
    'pipes': [(299,215),(314,180),(353,148),(403,131),(449,129),(486,136),(485,152),(451,160),(435,185),(449,183),(467,199),(480,231),(475,267),(453,296),(418,312),(381,312),(344,298),(315,270)],
    'boxes': [(546,238),(589,209),(591,173),(599,163),(599,129),(627,112),(682,135),(682,178),(695,195),(695,211),(736,235),(727,290),(694,314),(640,300),(609,309),(550,281)],
    'puddle': [(1012,206),(1030,190),(1056,182),(1078,156),(1114,151),(1142,161),(1150,188),(1197,192),(1220,212),(1225,239),(1210,261),(1176,264),(1175,289),(1156,305),(1121,299),(1098,281),(1067,291),(1047,275),(1049,249),(1021,237)],
    'bulb': [(370,401),(390,385),(410,386),(426,402),(430,427),(418,451),(414,465),(447,466),(449,478),(418,478),(399,490),(434,502),(453,505),(466,497),(482,506),(493,520),(489,536),(488,569),(469,595),(439,611),(404,617),(368,610),(342,591),(328,565),(325,537),(335,512),(354,494),(382,484),(385,473),(382,455),(371,440),(367,420)],
    'oil_stain': [(539,471),(571,458),(583,444),(615,443),(635,425),(662,429),(679,422),(698,436),(706,449),(733,454),(744,469),(727,483),(738,497),(743,516),(725,531),(696,531),(682,547),(652,559),(624,550),(612,536),(589,533),(572,516),(571,493),(546,487)],
}
for name, points in outlines.items():
    paint_source = sheet
    mask = Image.new('L', sheet.size)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    if name in ('pipes', 'bulb', 'puddle', 'oil_stain'):
        # The beige matte is low-chroma warm gray; remove it inside coils too.
        matte = (red > 110) & (red-green > 5) & (red-green < 24) & (green-blue > 3) & (green-blue < 24)
        if name == 'bulb':
            rows = np.arange(sheet.height)[:, None]
            matte |= (rows > 480) & (red > 135) & (red-green > 5) & (red-green < 45) & (green-blue > 5) & (green-blue < 40)
        mask = Image.fromarray(np.where(matte, 0, np.asarray(mask)).astype(np.uint8))
    if name in ('boxes', 'pipes'):
        # These cells carry a violet cast shadow, not part of their silhouette.
        violet = (blue > green+8) & (blue > red*0.75)
        silhouette = np.asarray(mask) > 0
        edge_distance = ndimage.distance_transform_edt(silhouette)
        silhouette &= ~(violet & (edge_distance <= 3))
        # Despill shadowed interior paint without punching holes through solid objects.
        clean = silhouette & ~violet
        _, nearest = ndimage.distance_transform_edt(~clean, return_indices=True)
        paint = np.asarray(sheet).copy()
        paint[violet & silhouette] = paint[nearest[0], nearest[1]][violet & silhouette]
        paint_source = Image.fromarray(paint)
        mask = Image.fromarray((silhouette*255).astype(np.uint8))
    bounds = mask.getbbox()
    bounds = (bounds[0]-5, bounds[1]-5, bounds[2]+5, bounds[3]+5)
    keyed = Image.new('RGB', sheet.size, '#ff00ff')
    keyed.paste(paint_source, mask=mask)
    crop = keyed.crop(bounds)
    save_png(crop, HERE / f'{name}_keyed.png')
    if name in ('puddle', 'oil_stain'):
        sprite = extract_sprite(crop)
        alpha = np.asarray(sprite.getchannel('A')).astype(float)/255
        distance = ndimage.distance_transform_edt(alpha > 0.5)
        # Remove the opaque bevel, then dissolve into the floor over six pixels.
        coverage = np.clip((distance-2)/6, 0, 1)
        coverage = coverage*coverage*(3-2*coverage)
        interior = distance >= 8
        _, nearest = ndimage.distance_transform_edt(~interior, return_indices=True)
        paint = np.asarray(sprite.convert('RGB'))
        softened = paint[nearest[0], nearest[1]].astype(float)
        # Keep restrained interior reflections; perimeter highlights cannot form a rim.
        mix = np.clip((distance-4)/8, 0, 1)[:,:,None]
        paint = softened*(1-mix)+paint*mix
        flat = Image.fromarray(paint.astype(np.uint8)).convert('RGBA')
        flat.putalpha(Image.fromarray((alpha*coverage*0.84*255).astype(np.uint8)))
        save_png(flat, ROOT / f'assets/textures/ground_dressing/basement_{name}.png')

# A web has no solid silhouette: retain only bright fine strands above its local matte.
web = sheet.crop((48,365,276,629))
gray = np.asarray(ImageOps.grayscale(web)).astype(float)
background = np.asarray(ImageOps.grayscale(web).filter(ImageFilter.GaussianBlur(3))).astype(float)
alpha = np.clip((gray-background-6)*9, 0, 220).astype(np.uint8)
web_rgba = web.convert('RGBA')
web_rgba.putalpha(Image.fromarray(alpha))
web_rgba.thumbnail((480,480), Image.Resampling.LANCZOS)
canvas = Image.new('RGBA',(512,512))
canvas.alpha_composite(web_rgba,((512-web_rgba.width)//2,(512-web_rgba.height)//2))
save_png(canvas, ROOT / 'assets/textures/ground_dressing/basement_cobweb.png')

# The sheet's empty concrete margin supplies actual painted texture, not invented art.
concrete = ImageOps.autocontrast(ImageOps.grayscale(sheet.crop((600,640,680,720))))
concrete = ImageOps.colorize(concrete, '#303735', '#a6aba2')
save_png(repeating_material(concrete), ROOT / 'assets/textures/world_materials/basement_concrete.png')
