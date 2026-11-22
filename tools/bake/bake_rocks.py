"""Bake Poly Haven rock scans (glTF) into one compact binary for the app.

Each rock node is decimated (fast-simplification, QEM) to a mobile budget, its
vertex attributes are carried over from the surviving original vertices, and
it is normalised to a unit footprint:

  - x/z centred on the bounding-box centre and scaled so the larger horizontal
    half-extent is 1.0 (the sim's rock radius scales it back up),
  - y measured from the base (0) to the top (height / half-extent),
  - converted to flutter_scene's native axes the way its glTF importer does.

Output, little-endian:
  magic 'LRK1', u32 rockCount
  per rock: u32 setIndex, u32 vertexCount, u32 indexCount, f32 height,
            f32 positions[3n], f32 normals[3n], f32 uvs[2n], f32 tangents[4n],
            u16 indices[m] (padded to 4 bytes)

Usage: python3 -I tools/bake/bake_rocks.py <out.bin> <target_tris> <set_dir>...
  each set_dir holds one Poly Haven glTF (2k) with its .bin.
"""
import json
import os
import struct
import sys

import numpy as np
import fast_simplification

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
    """Rotation/scale part only (translation is dropped: we re-centre)."""
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


def decimate(pos, nrm, uv, tan, idx, target):
    tris = len(idx)
    if tris <= target:
        return pos, nrm, uv, tan, idx
    reduction = 1.0 - target / tris
    pts, faces, collapses = fast_simplification.simplify(
        pos.astype(np.float32), idx.astype(np.int32), target_reduction=reduction, return_collapses=True)
    pts2, faces2, mapping = fast_simplification.replay_simplification(
        pos.astype(np.float32), idx.astype(np.int32), collapses)
    # mapping[i] = new index of original vertex i. Each new vertex takes the
    # attributes of the first original vertex mapped to it (the survivor).
    n_new = len(pts2)
    first = np.full(n_new, -1, np.int64)
    for i in range(len(mapping) - 1, -1, -1):
        first[mapping[i]] = i
    assert (first >= 0).all()
    return pts2.astype(np.float64), nrm[first], uv[first], tan[first], faces2.astype(np.int64)


def bake_set(set_dir, set_index, target):
    gltf = [f for f in os.listdir(set_dir) if f.endswith('.gltf')][0]
    g = json.load(open(os.path.join(set_dir, gltf)))
    buf = open(os.path.join(set_dir, g['buffers'][0]['uri']), 'rb').read()
    out = []
    for n in g['nodes']:
        if 'mesh' not in n:
            continue
        m = node_matrix(n)
        for prim in g['meshes'][n['mesh']]['primitives']:
            at = prim['attributes']
            pos = read_accessor(g, buf, at['POSITION']) @ m.T
            nrm = read_accessor(g, buf, at['NORMAL']) @ m.T
            nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
            uv = read_accessor(g, buf, at['TEXCOORD_0'])
            if 'TANGENT' in at:
                tan = read_accessor(g, buf, at['TANGENT'])
                tan[:, :3] = tan[:, :3] @ m.T
            else:
                tan = np.zeros((len(pos), 4))
            idx = read_accessor(g, buf, prim['indices']).reshape(-1, 3)
            pos, nrm, uv, tan, idx = decimate(pos, nrm, uv, tan, idx, target)
            # glTF -> flutter_scene native coordinates, exactly as the engine's
            # own importer does (coordinate_policy bakeNative): negate z of
            # positions, normals and tangents, negate tangent w, and swap
            # (a, b, c) -> (a, c, b) to keep counter-clockwise front faces.
            pos = pos * [1, 1, -1]
            nrm = nrm * [1, 1, -1]
            tan = tan * [1, 1, -1, -1]
            idx = idx[:, [0, 2, 1]]
            lo, hi = pos.min(0), pos.max(0)
            c = (lo + hi) / 2
            half = max(hi[0] - lo[0], hi[2] - lo[2]) / 2
            p = np.empty_like(pos)
            p[:, 0] = (pos[:, 0] - c[0]) / half
            p[:, 2] = (pos[:, 2] - c[2]) / half
            p[:, 1] = (pos[:, 1] - lo[1]) / half
            height = (hi[1] - lo[1]) / half
            out.append((set_index, p, nrm, uv, tan, idx, height, n.get('name', '')))
            print(f"  {n.get('name')}: {len(p)} verts, {len(idx)} tris, height/halfwidth {height:.2f}")
    return out


LEVELS, SECTORS = 9, 16


def footprint_profile(p, height):
    """Radial extent of the scan (unit footprint) at LEVELS heights and
    SECTORS azimuths (atan2(z, x) in native axes), for foam and contact."""
    prof = np.zeros((LEVELS, SECTORS))
    az = np.arctan2(p[:, 2], p[:, 0])
    sec = ((az + np.pi) / (2 * np.pi) * SECTORS).astype(int) % SECTORS
    rad = np.hypot(p[:, 0], p[:, 2])
    frac = p[:, 1] / height
    for li in range(LEVELS):
        f = li / (LEVELS - 1)
        m = np.abs(frac - f) < 0.09
        for si in range(SECTORS):
            sel = rad[m & (sec == si)]
            prof[li, si] = sel.max() if sel.size else np.nan
    # Fill empty sectors from neighbours, then any empty level from its neighbours.
    for li in range(LEVELS):
        row = prof[li]
        if np.isnan(row).all():
            continue
        idx = np.arange(SECTORS)
        ok = ~np.isnan(row)
        prof[li] = np.interp(idx, np.concatenate([idx[ok] - SECTORS, idx[ok], idx[ok] + SECTORS]),
                             np.tile(row[ok], 3))
    for li in range(LEVELS):
        if np.isnan(prof[li]).all():
            prof[li] = 0.05
    return prof


def write_dart(path, rocks):
    lines = ['// GENERATED by tools/bake/bake_rocks.py. Do not edit.',
             '// Per baked rock scan (order of assets/rocks/rocks.bin): height divided',
             '// by the horizontal half-extent, and the radial extent of the unit',
             f'// footprint at {LEVELS} heights (base to top) x {SECTORS} azimuths',
             '// (sector i covers atan2(z, x) in [-pi + i*2pi/16, ...), native axes).',
             '',
             'const List<double> kRockTypeHeights = [']
    lines += [f'  {r[6]:.4f}, // {r[7]}' for r in rocks]
    lines += ['];', '', f'const int kRockProfileLevels = {LEVELS};', f'const int kRockProfileSectors = {SECTORS};', '',
              'const List<List<double>> kRockProfiles = [']
    for r in rocks:
        prof = footprint_profile(r[1], r[6])
        lines.append('  [' + ', '.join(f'{v:.3f}' for v in prof.flatten()) + '],')
    lines += ['];', '']
    open(path, 'w').write('\n'.join(lines))
    print('wrote', path)


def main(out_path, target, set_dirs):
    rocks = []
    for i, d in enumerate(set_dirs):
        print(d)
        rocks += bake_set(d, i, target)
    with open(out_path, 'wb') as f:
        f.write(b'LRK1' + struct.pack('<I', len(rocks)))
        for s, p, nrm, uv, tan, idx, h, _ in rocks:
            assert len(p) < 65536
            f.write(struct.pack('<IIIf', s, len(p), idx.size, h))
            for a in (p, nrm, uv, tan):
                f.write(a.astype('<f4').tobytes())
            ib = idx.astype('<u2').tobytes()
            f.write(ib + b'\0' * (-len(ib) % 4))
    print('wrote', out_path, os.path.getsize(out_path), 'bytes,', len(rocks), 'rocks')
    write_dart(os.path.join(os.path.dirname(out_path), '..', '..', 'lib', 'render', 'rock_profiles.g.dart'), rocks)


if __name__ == '__main__':
    main(sys.argv[1], int(sys.argv[2]), sys.argv[3:])
