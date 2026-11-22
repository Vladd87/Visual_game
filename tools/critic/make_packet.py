"""Assemble a blind critic packet for one capture round (PLAN.md §5).

The packet is a standalone folder with only images, so the critic never sees
code or the builder's reasoning:

  <packet>/captures/{inner,cover}/shotN.jpg   the round's captures
  <packet>/references/refNN.jpg               real reference photos (renamed; A/B photos held out)
  <packet>/device/...                         captures/device/ if present
  <packet>/ab/pairK_A.jpg, pairK_B.jpg        blind pairs: one capture, one photo

Every image is re-encoded the same way (JPEG q90, no metadata, long side
capped) so file format cannot give the answer away. The A/B answer key is
written OUTSIDE the packet.

Usage: python3 -I make_packet.py <round_dir> <references_dir> <device_dir> <packet_dir> <key_file> [pairs] [seed]
"""
import json
import os
import random
import sys

from PIL import Image


def clean(im):
    """Fresh pixel copy: no EXIF, ICC, JPEG comment or other source metadata."""
    im = im.convert('RGB')
    return Image.frombytes('RGB', im.size, im.tobytes())


def save(src, dst, max_side=1600):
    im = Image.open(src).convert('RGB')
    im.thumbnail((max_side, max_side), Image.LANCZOS)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    clean(im).save(dst, 'JPEG', quality=90)


def center_crop_to(src, aspect, max_side):
    im = Image.open(src).convert('RGB')
    w, h = im.size
    if w / h > aspect:
        nw = int(h * aspect)
        im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    else:
        nh = int(w / aspect)
        im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    im.thumbnail((max_side, max_side), Image.LANCZOS)
    return im


def main():
    round_dir, refs_dir, device_dir, packet, key_file = sys.argv[1:6]
    pairs = int(sys.argv[6]) if len(sys.argv) > 6 else 4
    seed = int(sys.argv[7]) if len(sys.argv) > 7 else 1
    rnd = random.Random(seed)
    caps = []
    for aspect in ('inner', 'cover'):
        d = os.path.join(round_dir, aspect)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.endswith('.png'):
                src = os.path.join(d, f)
                save(src, os.path.join(packet, 'captures', aspect, f.replace('.png', '.jpg')))
                caps.append(src)
    refs = sorted(f for f in os.listdir(refs_dir) if f.startswith('ref') and f.endswith('.jpg'))
    # Hold out the A/B photos: they must NOT also appear in references/, or the
    # critic can identify the real half by matching (round-1 finding).
    ref_pick = rnd.sample(refs, min(pairs, len(refs)))
    shown = [f for f in refs if f not in ref_pick]
    for i, f in enumerate(shown, 1):
        save(os.path.join(refs_dir, f), os.path.join(packet, 'references', f'ref{i:02d}.jpg'))
    if os.path.isdir(device_dir):
        for root, _, files in os.walk(device_dir):
            for f in files:
                if f.lower().endswith(('.png', '.jpg', '.jpeg')):
                    rel = os.path.relpath(os.path.join(root, f), device_dir)
                    save(os.path.join(root, f), os.path.join(packet, 'device', os.path.splitext(rel)[0] + '.jpg'))
                elif f.lower().endswith(('.csv', '.txt')):
                    os.makedirs(os.path.join(packet, 'device'), exist_ok=True)
                    with open(os.path.join(root, f), 'rb') as a, open(os.path.join(packet, 'device', f), 'wb') as b:
                        b.write(a.read())
    # Blind pairs: same crop aspect and size for both images in a pair.
    key = []
    cap_pick = rnd.sample(caps, min(pairs, len(caps)))
    os.makedirs(os.path.join(packet, 'ab'), exist_ok=True)
    for k, (c, r) in enumerate(zip(cap_pick, ref_pick), 1):
        aspect = 0.75 if rnd.random() < 0.5 else 1.0
        ci = center_crop_to(c, aspect, 900)
        ri = center_crop_to(os.path.join(refs_dir, r), aspect, 900).resize(ci.size, Image.LANCZOS)
        real_is_a = rnd.random() < 0.5
        a, b = (ri, ci) if real_is_a else (ci, ri)
        clean(a).save(os.path.join(packet, 'ab', f'pair{k}_A.jpg'), 'JPEG', quality=90)
        clean(b).save(os.path.join(packet, 'ab', f'pair{k}_B.jpg'), 'JPEG', quality=90)
        key.append({'pair': k, 'real': 'A' if real_is_a else 'B',
                    'capture': os.path.relpath(c, round_dir), 'reference': r})
    with open(key_file, 'w') as f:
        json.dump(key, f, indent=2)
    print(f'packet: {len(caps)} captures, {len(refs)} references, {len(key)} A/B pairs -> {packet}')


if __name__ == '__main__':
    main()
