"""Bake Poly Haven plant models (glTF) into one compact binary for the app.

Each source is read as either:
  - variants: every mesh node is its own plant (fern_02 holds four ferns laid
    out on a 1 m grid; the grid offset is dropped and each is centred), or
  - clump:    all mesh nodes form one plant (shrub_sorrel_01 is a patch of
    sprigs; their offsets are kept and the patch is centred).

Positions stay in metres (the scatter scales them), x/z centred on the
bounding-box centre, y from the base. Axes are converted to flutter_scene's
native ones the way its glTF importer does (see bake_rocks.py).

Output, little-endian:
  magic 'LPL1', u32 plantCount
  per plant: u32 kind (index of the source), u32 vertexCount, u32 indexCount,
             f32 radius (horizontal half-extent), f32 height,
             f32 positions[3n], f32 normals[3n], f32 uvs[2n],
             u16 indices[m] (padded to 4 bytes)

Textures: <name>_col.png = base colour (RGB) with the alpha mask in A, at
the requested size.

Usage: python3 -I tools/bake/bake_plants.py <out.bin> <tex_dir> <size> \
         variants:<dir> clump:<dir> ...
  each dir holds one Poly Haven glTF (1k) with its .bin and textures/ incl.
  the <name>_alpha_1k.png mask.
"""
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

# Sources whose flowers are cut out of the alpha mask.
FLOWERLESS = {'shrub_sorrel_01'}

COMPONENT = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def read_accessor(g, buf, idx):
    a = g['accessors'][idx]
    v = g['bufferViews'][a['bufferView']]
    dt = COMPONENT[a['componentType']]
    n = NCOMP[a['type']]
    off = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = v.get('byteStride', 0)
    item = np.dtype(dt).itemsize * n
    if stride and stride != item:
        raw = np.frombuffer(buf, np.uint8, a['count'] * stride, off).reshape(a['count'], stride)[:, :item]
        arr = np.frombuffer(raw.tobytes(), dt).reshape(a['count'], n)
    else:
        arr = np.frombuffer(buf, dt, a['count'] * n, off).reshape(a['count'], n)
    return arr.astype(np.float64 if dt == np.float32 else np.int64)


def node_matrix(n):
    m = np.eye(3)
    if 'rotation' in n:
        x, y, z, w = n['rotation']
        m = np.array([
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ])
    if 'scale' in n:
        m = m @ np.diag(n['scale'])
    return m


def read_nodes(src_dir):
    gltf = [f for f in os.listdir(src_dir) if f.endswith('.gltf')][0]
    g = json.load(open(os.path.join(src_dir, gltf)))
    buf = open(os.path.join(src_dir, g['buffers'][0]['uri']), 'rb').read()
    parts = []
    for n in g['nodes']:
        if 'mesh' not in n:
            continue
        m = node_matrix(n)
        t = np.array(n.get('translation', [0, 0, 0]))
        for prim in g['meshes'][n['mesh']]['primitives']:
            at = prim['attributes']
            pos = read_accessor(g, buf, at['POSITION']) @ m.T
            nrm = read_accessor(g, buf, at['NORMAL']) @ m.T
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
            uv = read_accessor(g, buf, at['TEXCOORD_0'])
            idx = read_accessor(g, buf, prim['indices']).reshape(-1, 3)
            parts.append((n.get('name', ''), pos, t, nrm, uv, idx))
    name = os.path.splitext(gltf)[0].rsplit('_', 1)[0]
    return name, parts


def finish(pos, nrm, uv, idx):
    # glTF -> flutter_scene native: negate z, swap winding (see bake_rocks.py).
    pos = pos * [1, 1, -1]
    nrm = nrm * [1, 1, -1]
    idx = idx[:, [0, 2, 1]]
    lo, hi = pos.min(0), pos.max(0)
    c = (lo + hi) / 2
    p = pos.copy()
    p[:, 0] -= c[0]
    p[:, 2] -= c[2]
    p[:, 1] -= lo[1]
    radius = max(hi[0] - lo[0], hi[2] - lo[2]) / 2
    return p, nrm, uv, idx, radius, hi[1] - lo[1]


def bake(kind, mode, src_dir):
    name, parts = read_nodes(src_dir)
    out = []
    if mode == 'variants':
        for pname, pos, _t, nrm, uv, idx in parts:
            p, n, u, i, r, h = finish(pos, nrm, uv, idx)
            out.append((kind, p, n, u, i, r, h))
            print(f'  {pname}: {len(p)} verts, {len(i)} tris, r {r:.3f} m, h {h:.3f} m')
    else:
        allp, alln, allu, alli, base = [], [], [], [], 0
        for _pname, pos, t, nrm, uv, idx in parts:
            allp.append(pos + t)
            alln.append(nrm)
            allu.append(uv)
            alli.append(idx + base)
            base += len(pos)
        p, n, u, i, r, h = finish(np.concatenate(allp), np.concatenate(alln), np.concatenate(allu), np.concatenate(alli))
        out.append((kind, p, n, u, i, r, h))
        print(f'  clump: {len(p)} verts, {len(i)} tris, r {r:.3f} m, h {h:.3f} m')
    return name, out


def pack_texture(src_dir, name, tex_dir, size):
    t = os.path.join(src_dir, 'textures')
    col = Image.open(os.path.join(t, f'{name}_diff_1k.jpg')).convert('RGB')
    alpha = Image.open(os.path.join(t, f'{name}_alpha_1k.png')).convert('L')
    if name in FLOWERLESS:
        # Remove flowers: pink/lilac petals (red and blue above green) are
        # cut out through the mask. At dusk they read as identical bright
        # dots sprinkled evenly (critics, rounds 22-23).
        c = np.asarray(col).astype(np.int32)
        a8 = np.asarray(alpha).copy()
        r, g, b = c[..., 0], c[..., 1], c[..., 2]
        petal = (r > g + 12) & (b > g + 4)
        a8[petal] = 0
        alpha = Image.fromarray(a8)
        print(f'  {name}: removed {int(petal.sum())} flower texels')
    rgba = Image.merge('RGBA', (*col.split(), alpha))
    if size != rgba.size[0]:
        rgba = rgba.resize((size, size), Image.LANCZOS)
    out = os.path.join(tex_dir, f'{name}_col.png')
    rgba.save(out, optimize=True)
    print('wrote', out, os.path.getsize(out), 'bytes')


def main(out_path, tex_dir, size, specs):
    os.makedirs(tex_dir, exist_ok=True)
    plants = []
    for kind, spec in enumerate(specs):
        mode, d = spec.split(':', 1)
        print(d)
        name, out = bake(kind, mode, d)
        plants += out
        pack_texture(d, name, tex_dir, size)
    with open(out_path, 'wb') as f:
        f.write(b'LPL1' + struct.pack('<I', len(plants)))
        for kind, p, n, u, i, r, h in plants:
            assert len(p) < 65536
            f.write(struct.pack('<IIIff', kind, len(p), i.size, r, h))
            for a in (p, n, u):
                f.write(a.astype('<f4').tobytes())
            ib = i.astype('<u2').tobytes()
            f.write(ib + b'\0' * (-len(ib) % 4))
    print('wrote', out_path, os.path.getsize(out_path), 'bytes,', len(plants), 'plants')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4:])
