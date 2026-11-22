"""Bake the scene's blue-hour environment: a CC0 HDRI with a forest treeline.

The stream runs through woodland, so the bright, warm horizon glow of an
open-field HDRI must not light the banks from the side. Below a ragged
treeline (about 14-30 degrees of elevation, with gaps), the sky is replaced
by dark foliage lit faintly by the sky above it; the ground hemisphere
becomes dark leaf litter. What remains, the open sky overhead, is the cool
blue-hour ambient light (refs 05, 11).

Writes a flat-scanline Radiance .hdr (flutter_scene's decoder reads flat and
RLE scanlines) and prints the mean irradiance colours for the log.

Usage: python3 -I tools/bake/bake_env.py <in.hdr> <out.hdr>
"""
import importlib.util
import math
import os
import sys

import numpy as np

_spec = importlib.util.spec_from_file_location('bake_sky', os.path.join(os.path.dirname(__file__), 'bake_sky.py'))
_sky = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_sky)


def treeline(az):
    """Treeline elevation in degrees for azimuth array az (radians)."""
    e = 21.0 + 5.0 * np.sin(az * 2 + 0.7) + 3.0 * np.sin(az * 5 + 2.1) + 1.8 * np.sin(az * 11 + 0.3) + 1.0 * np.sin(az * 23 + 1.9)
    # Gaps where the stream corridor opens the view (lower treeline).
    gap = np.exp(-((np.angle(np.exp(1j * (az - 1.2)))) / 0.35) ** 2) + np.exp(-((np.angle(np.exp(1j * (az + 1.94)))) / 0.3) ** 2)
    return e - 9.0 * gap


def write_hdr(path, rgb):
    h, w, _ = rgb.shape
    v = rgb.max(axis=2)
    m, e = np.frexp(v)
    scale = np.where(v > 1e-32, m * 256.0 / np.maximum(v, 1e-32), 0.0)
    out = np.zeros((h, w, 4), np.uint8)
    for c in range(3):
        out[..., c] = np.clip(rgb[..., c] * scale, 0, 255).astype(np.uint8)
    out[..., 3] = np.where(v > 1e-32, e + 128, 0).astype(np.uint8)
    with open(path, 'wb') as f:
        f.write(b'#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n')
        f.write(f'-Y {h} +X {w}\n'.encode())
        f.write(out.tobytes())


def remove_points(rgb, k=7, ratio=3.0):
    """Replace isolated bright points (Venus, stars) with the local median:
    downsampled for the water's sky texture they become blocky glints."""
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722])
    pad = k // 2
    p = np.pad(lum, pad, mode='edge')
    win = np.lib.stride_tricks.sliding_window_view(p, (k, k))
    med = np.median(win, axis=(2, 3))
    hot = lum > ratio * np.maximum(med, 1e-6)
    out = rgb.copy()
    scale = np.where(hot, med / np.maximum(lum, 1e-6), 1.0)
    out *= scale[..., None]
    print('removed', int(hot.sum()), 'point pixels')
    return out


def main(src, dst):
    rgb = remove_points(_sky.read_hdr(src))
    h, w, _ = rgb.shape
    # Equirect convention used by the engine and water.fmat: u = atan(z, x),
    # v = 0.5 - asin(y)/pi. Rows: elevation from +90 (top) to -90 (bottom).
    el = (0.5 - (np.arange(h) + 0.5) / h) * 180.0
    az = ((np.arange(w) + 0.5) / w - 0.5) * 2 * math.pi
    tl = treeline(az)[None, :]
    elev = el[:, None]
    # Sky seen above the trees: the mean of the open sky at 30-60 degrees.
    band = rgb[int(h * (0.5 - 60 / 180)):int(h * (0.5 - 30 / 180))].reshape(-1, 3).mean(0)
    foliage = band * np.array([0.045, 0.055, 0.05])     # dark leaves lit by the sky above
    litter = band * np.array([0.03, 0.03, 0.03])
    t = np.clip((elev - tl) / 2.5 + 0.5, 0, 1)[..., None]  # soft 2.5 deg edge
    # Leaf texture in the canopy band, so reflections of the treeline break up.
    rng = np.random.default_rng(7)
    leaf = 0.6 + 0.8 * rng.random((h, w, 1))
    canopy = foliage * leaf
    below = np.where(elev[..., None] < 0, litter, canopy)
    out = rgb * t + below * (1 - t)
    write_hdr(dst, out.astype(np.float32))
    up = out[: h // 2]
    wgt = np.cos(np.radians(el[: h // 2]))[:, None, None] * np.sin(np.radians(np.maximum(el[: h // 2], 0)))[:, None, None]
    irr_up = (up * wgt).sum((0, 1)) / wgt.sum()
    print('open-sky band', band.round(3), 'cos-weighted upward radiance', irr_up.round(4),
          'b/r', round(float(irr_up[2] / irr_up[0]), 2))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
