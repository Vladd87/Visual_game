"""Pack downloaded CC0 surface textures into the app's 3-map layout.

Each surface becomes three JPEGs (1024², rock colour/normal atlases 2048²)
in app/assets/textures/surfaces/:
  <name>_col.jpg   albedo, sRGB
  <name>_nrm.jpg   tangent-space normal, OpenGL convention (+Y up), linear
  <name>_arh.jpg   R = ambient occlusion, G = roughness, B = height, linear

Sources (all CC0, logged in ASSETS.md):
  Poly Haven 'arm' maps are AO/rough/metal; metal is replaced with height.
  ambientCG ships separate AO, Roughness and Displacement maps.

Usage: python3 -I tools/bake/pack_surface_textures.py <src_root> <out_dir>
"""
import os
import sys

import numpy as np
from PIL import Image

SIZE = 1024


def load(path, mode='RGB', size=SIZE):
    im = Image.open(path).convert(mode)
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im).astype(np.float32) / 255.0


def renorm(n):
    v = n * 2 - 1
    v /= np.maximum(np.linalg.norm(v, axis=2, keepdims=True), 1e-6)
    return (v + 1) / 2


def save(arr, path):
    Image.fromarray(np.clip(np.round(arr * 255), 0, 255).astype(np.uint8), 'RGB').save(path, quality=92)


def pack(out_dir, name, col, nrm, ao, rough, height):
    save(load(col), os.path.join(out_dir, f'{name}_col.jpg'))
    save(renorm(load(nrm)), os.path.join(out_dir, f'{name}_nrm.jpg'))
    arh = np.stack([load(ao, 'L'), load(rough, 'L'), load(height, 'L')], axis=2)
    save(arh, os.path.join(out_dir, f'{name}_arh.jpg'))
    print('packed', name)


def main(src, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    acg = lambda a, m: os.path.join(src, 'acg', a, f'{a}_1K-JPG_{m}.jpg')
    for a, name in [('Moss001', 'moss'), ('Ground037', 'forest_ground')]:
        pack(out_dir, name, acg(a, 'Color'), acg(a, 'NormalGL'), acg(a, 'AmbientOcclusion'), acg(a, 'Roughness'), acg(a, 'Displacement'))
    t = lambda f: os.path.join(src, 'dl', 'tex', f)
    # Poly Haven arm: R = AO, G = roughness. Split them out via temporary channel images.
    arm = Image.open(t('brown_mud_02_arm_1k.jpg')).convert('RGB')
    tmp = os.path.join(out_dir, '_tmp')
    os.makedirs(tmp, exist_ok=True)
    arm.getchannel(0).save(os.path.join(tmp, 'ao.png'))
    arm.getchannel(1).save(os.path.join(tmp, 'rough.png'))
    pack(out_dir, 'mud', t('brown_mud_02_diff_1k.jpg'), t('brown_mud_02_nor_gl_1k.jpg'),
         os.path.join(tmp, 'ao.png'), os.path.join(tmp, 'rough.png'), t('brown_mud_02_disp_1k.jpg'))
    # Rock scan atlases: colour and normal stay 2k (six or seven rocks share
    # each atlas, and the lantern lights their sides up close); AO/rough/height
    # go to 1k. Set 01 has no height map, so B = 0.5 there.
    for s in ['rock_moss_set_01', 'rock_moss_set_02']:
        d = os.path.join(src, 'dl', s, 'textures')
        save(load(os.path.join(d, f'{s}_diff_2k.jpg'), size=2048), os.path.join(out_dir, f'{s}_col.jpg'))
        save(renorm(load(os.path.join(d, f'{s}_nor_gl_2k.jpg'), size=2048)), os.path.join(out_dir, f'{s}_nrm.jpg'))
        rough = load(os.path.join(d, f'{s}_rough_2k.jpg'), 'L')
        ao = load(os.path.join(d, f'{s}_ao_2k.jpg'), 'L')
        hp = os.path.join(d, f'{s}_disp_2k.jpg')
        height = load(hp, 'L') if os.path.exists(hp) else np.full_like(rough, 0.5)
        arh = np.stack([ao, rough, height], axis=2)
        save(arh, os.path.join(out_dir, f'{s}_arh.jpg'))
        print('packed', s)
    for f in os.listdir(tmp):
        os.remove(os.path.join(tmp, f))
    os.rmdir(tmp)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
