"""Bake a small, blurred equirect sky texture from the dusk HDRI for the water's
own sky reflection (water.fmat samples it by reflection direction).

Encoding: RGB = sqrt(radiance / SCALE). SCALE is printed; copy it into
GameScene.loadAssets (sky_scale) so the shader recovers radiance as
sample^2 * SCALE.

Usage: python3 -I tools/bake/bake_sky.py <in.hdr> <out_dir>
"""
import os
import sys

import numpy as np
from PIL import Image


def read_hdr(path):
    """Minimal Radiance RGBE reader (new-style RLE and flat scanlines)."""
    with open(path, 'rb') as f:
        data = f.read()
    pos = 0
    while True:
        end = data.index(b'\n', pos)
        line = data[pos:end]
        pos = end + 1
        if line.startswith(b'-Y') or line.startswith(b'+Y'):
            parts = line.split()
            h, w = int(parts[1]), int(parts[3])
            break
    out = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        if data[pos] == 2 and data[pos + 1] == 2 and (data[pos + 2] << 8 | data[pos + 3]) == w:
            pos += 4
            for c in range(4):
                x = 0
                while x < w:
                    n = data[pos]
                    pos += 1
                    if n > 128:
                        n -= 128
                        out[y, x:x + n, c] = data[pos]
                        pos += 1
                    else:
                        out[y, x:x + n, c] = np.frombuffer(data, np.uint8, n, pos)
                        pos += n
                    x += n
        else:
            out[y] = np.frombuffer(data, np.uint8, w * 4, pos).reshape(w, 4)
            pos += w * 4
    e = out[..., 3].astype(np.int32)
    scale = np.where(e > 0, np.ldexp(1.0, e - 136), 0.0)
    return out[..., :3].astype(np.float64) * scale[..., None]


def main(src, out_dir):
    rgb = read_hdr(src)
    h, w, _ = rgb.shape
    # Downsample to 128x64 with area averaging, then a small blur for glossy water.
    small = rgb.reshape(64, h // 64, 128, w // 128, 3).mean(axis=(1, 3))
    for _ in range(2):
        small = (small * 2 + np.roll(small, 1, 1) + np.roll(small, -1, 1)) / 4
        small[1:-1] = (small[1:-1] * 2 + small[:-2] + small[2:]) / 4
    scale = float(np.percentile(small, 99.5))
    enc = np.sqrt(np.clip(small / scale, 0, 1))
    os.makedirs(out_dir, exist_ok=True)
    Image.fromarray(np.round(enc * 255).astype(np.uint8), 'RGB').save(os.path.join(out_dir, 'sky_dusk.png'))
    print('sky scale', scale, 'mean radiance', small.mean(axis=(0, 1)))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
