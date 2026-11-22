"""Bake LANTERN's procedural water textures (tileable, CC0 by construction).

  water_normal.png : RG = surface normal XY (0.5 = flat), B = height (foam breakup),
                     A = second independent height (rain-cell noise, used later).
  caustics.png     : light focused by refraction through a rippled surface onto a
                     bed below (photon splat), normalised so mean = 0.25 (x4 in shader).

Usage: python3 -I tools/bake/bake_water_textures.py app/assets/textures
"""
import os
import sys

import numpy as np
from PIL import Image

N = 512


def grad_noise(period, seed, n, ss=1):
    r = np.random.default_rng(seed)
    ang = r.random((period, period)) * 2 * np.pi
    gxl, gyl = np.cos(ang), np.sin(ang)
    m = n * ss
    x = (np.arange(m) + 0.5) * period / m
    i0 = np.floor(x).astype(int)
    f = x - i0
    u = f * f * f * (f * (f * 6 - 15) + 10)
    i1 = (i0 + 1) % period
    i0 = i0 % period
    fy, fx = f[:, None], f[None, :]

    def dg(iy, ix, dy, dx):
        return gxl[np.ix_(iy, ix)] * dx + gyl[np.ix_(iy, ix)] * dy

    n00, n01 = dg(i0, i0, fy, fx), dg(i0, i1, fy, fx - 1)
    n10, n11 = dg(i1, i0, fy - 1, fx), dg(i1, i1, fy - 1, fx - 1)
    uy, ux = u[:, None], u[None, :]
    return (n00 * (1 - ux) + n01 * ux) * (1 - uy) + (n10 * (1 - ux) + n11 * ux) * uy


def height(octs, n, ss=1, seed0=200):
    h = 0
    for k, (p, a) in enumerate(octs):
        h = h + a * grad_noise(p, seed0 + k, n, ss)
    return h


def normals(h, scale, n):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * n
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * n
    nx, ny = -gx * scale, -gy * scale
    l = np.sqrt(nx * nx + ny * ny + 1)
    return nx / l, ny / l, 1 / l


def norm01(a):
    return (a - a.min()) / (a.max() - a.min())


def main(out):
    os.makedirs(out, exist_ok=True)
    # Surface normal map.
    # No octaves finer than 1/32 tile: they alias at game distance (~2-3 mm per pixel).
    hs = height([(4, 1.0), (8, 0.5), (16, 0.22), (32, 0.06)], N)
    nx, ny, _ = normals(hs, 0.05 * 512 / N, N)
    h2 = height([(8, 1.0), (16, 0.5), (32, 0.25)], N, seed0=900)
    img = np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, norm01(hs), norm01(h2)], -1)
    Image.fromarray(np.round(img * 255).astype(np.uint8), 'RGBA').save(os.path.join(out, 'water_normal.png'))

    # Caustics: refract vertical light through a smoother surface, splat on a bed.
    ss, depth, scale = 2, 0.25, 0.08
    n = N * ss
    hc = height([(3, 1.0), (6, 0.45), (12, 0.18)], N, ss=ss, seed0=500)
    cx, cy, cz = normals(hc, scale, n)
    eta = 1 / 1.33
    k = 1 - eta * eta * (1 - cz * cz)
    a = eta * cz - np.sqrt(k)
    tx, ty, tz = a * cx, a * cy, -eta + a * cz
    yy, xx = np.mgrid[0:n, 0:n]
    px = (xx + tx / -tz * depth * n) / ss
    py = (yy + ty / -tz * depth * n) / ss
    acc = np.zeros((N, N))
    x0, y0 = np.floor(px).astype(int), np.floor(py).astype(int)
    fx, fy = px - x0, py - y0
    for dx, dy, w in [(0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)]:
        np.add.at(acc, ((y0 + dy) % N, (x0 + dx) % N), w)
    for _ in range(2):
        acc = (acc * 4 + np.roll(acc, 1, 0) + np.roll(acc, -1, 0) + np.roll(acc, 1, 1) + np.roll(acc, -1, 1)) / 8
    c = acc / acc.mean() * 0.25  # mean 0.25 -> 8-bit range covers 0..4x
    Image.fromarray(np.round(np.clip(c, 0, 1) * 255).astype(np.uint8), 'L').save(os.path.join(out, 'caustics.png'))
    print('baked', out, 'caustic p99', np.percentile(c * 4, 99).round(2))


if __name__ == '__main__':
    main(sys.argv[1])
