import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show decodeImageFromList;
import 'package:flutter_scene/scene.dart';

/// Packs the CC0 surface photos into as few textures as possible.
///
/// Android GPUs only guarantee 16 fragment samplers, and flutter_scene's lit
/// pipeline already uses about ten of them (environment, BRDF LUT, shadows,
/// lights, AO, ...). One sampler per map per surface (11 on the ground in
/// M3) does not fit and the pipeline fails to build on the phone. So each
/// surface becomes two RGBA images:
///
///   T1 = albedo (sRGB) + roughness (alpha)
///   T2 = normal X, normal Y (OpenGL convention, z rebuilt in the shader),
///        ambient occlusion, height
///
/// and the three bank surfaces share one padded 2x2 atlas per image, so the
/// ground shader binds three textures in all (T1, T2 and a data texture).
class SurfaceAtlas {
  SurfaceAtlas(this.t1, this.t2);
  final Texture2D t1;
  final Texture2D t2;

  /// Layout constants mirrored in ground.fmat / rock.fmat (AtlasTap).
  static const int inner = 1024;
  static const int pad = 32;
  static const int tile = inner + 2 * pad; // 1088
  static const int size = tile * 2; // 2176

  /// Tile of each surface: (column, row).
  static const forestGround = (0, 0);
  static const moss = (1, 0);
  static const mud = (0, 1);
}

class _Rgba {
  _Rgba(this.px, this.w, this.h);
  final Uint8List px;
  final int w, h;
}

Future<_Rgba> _decode(String path) async {
  final bytes = await rootBundle.load(path);
  final ui.Image image = await decodeImageFromList(bytes.buffer.asUint8List());
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final out = _Rgba(data!.buffer.asUint8List(), image.width, image.height);
  image.dispose();
  return out;
}

/// Packs one surface (`<dir>/<name>_col/_nrm/_arh.jpg`) into T1 and T2 at
/// the colour map's resolution (a smaller AO/rough/height map is sampled
/// nearest-neighbour).
Future<(_Rgba, _Rgba)> _packSurface(String name) async {
  const dir = 'assets/textures/surfaces';
  final col = await _decode('$dir/${name}_col.jpg');
  final nrm = await _decode('$dir/${name}_nrm.jpg');
  final arh = await _decode('$dir/${name}_arh.jpg');
  final w = col.w, h = col.h;
  final t1 = Uint8List(w * h * 4), t2 = Uint8List(w * h * 4);
  final sx = arh.w / w, sy = arh.h / h;
  final nx = nrm.w / w, ny = nrm.h / h;
  for (var y = 0; y < h; y++) {
    final ay = (y * sy).floor(), ny0 = (y * ny).floor();
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      final a = (ay * arh.w + (x * sx).floor()) * 4;
      final n = (ny0 * nrm.w + (x * nx).floor()) * 4;
      t1[o] = col.px[o];
      t1[o + 1] = col.px[o + 1];
      t1[o + 2] = col.px[o + 2];
      t1[o + 3] = arh.px[a + 1]; // roughness
      t2[o] = nrm.px[n];
      t2[o + 1] = nrm.px[n + 1];
      t2[o + 2] = arh.px[a]; // AO
      t2[o + 3] = arh.px[a + 2]; // height
    }
  }
  return (_Rgba(t1, w, h), _Rgba(t2, w, h));
}

/// Copies [src] (inner x inner, tileable) into tile (tx, ty) of [atlas],
/// with [SurfaceAtlas.pad] texels of wrapped content on every side so
/// filtering and the first mip levels never bleed into a neighbour.
void _blit(Uint8List atlas, _Rgba src, int tx, int ty) {
  const t = SurfaceAtlas.tile, p = SurfaceAtlas.pad, n = SurfaceAtlas.inner, s = SurfaceAtlas.size;
  assert(src.w == n && src.h == n);
  for (var y = 0; y < t; y++) {
    final sy = (y - p) % n;
    final dstRow = ((ty * t + y) * s + tx * t) * 4;
    final srcRow = sy * n * 4;
    // left pad, body, right pad
    atlas.setRange(dstRow, dstRow + p * 4, src.px, srcRow + (n - p) * 4);
    atlas.setRange(dstRow + p * 4, dstRow + (p + n) * 4, src.px, srcRow);
    atlas.setRange(dstRow + (p + n) * 4, dstRow + t * 4, src.px, srcRow);
  }
}

const _sampling = TextureSampling(maxAnisotropy: 8, mipmaps: true);

/// The bank surfaces: forest ground, moss and mud in one padded atlas pair.
Future<SurfaceAtlas> buildSurfaceAtlas() async {
  const s = SurfaceAtlas.size;
  final a1 = Uint8List(s * s * 4), a2 = Uint8List(s * s * 4);
  final tiles = {
    'forest_ground': SurfaceAtlas.forestGround,
    'moss': SurfaceAtlas.moss,
    'mud': SurfaceAtlas.mud,
  };
  _Rgba? first1, first2;
  for (final e in tiles.entries) {
    final (t1, t2) = await _packSurface(e.key);
    _blit(a1, t1, e.value.$1, e.value.$2);
    _blit(a2, t2, e.value.$1, e.value.$2);
    first1 ??= t1;
    first2 ??= t2;
  }
  // The spare tile repeats the forest ground (never sampled, but keeps the
  // coarse mips sensible).
  _blit(a1, first1!, 1, 1);
  _blit(a2, first2!, 1, 1);
  return SurfaceAtlas(
    Texture2D.fromPixels(a1, s, s, content: TextureContent.color, sampling: _sampling),
    Texture2D.fromPixels(a2, s, s, content: TextureContent.data, sampling: _sampling),
  );
}

/// One scanned rock set's atlas (its own UVs) as T1 and T2.
Future<(Texture2D, Texture2D)> packRockSet(String name) async {
  final (t1, t2) = await _packSurface(name);
  return (
    Texture2D.fromPixels(t1.px, t1.w, t1.h, content: TextureContent.color, sampling: _sampling),
    Texture2D.fromPixels(t2.px, t2.w, t2.h, content: TextureContent.data, sampling: _sampling),
  );
}

/// Ground data texture: R = caustics, G = the noise from the water normal
/// map's alpha (both 512², tileable).
Future<Texture2D> buildGroundData() async {
  final c = await _decode('assets/textures/caustics.png');
  final w = await _decode('assets/textures/water_normal.png');
  assert(c.w == w.w && c.h == w.h);
  final out = Uint8List(c.w * c.h * 4);
  for (var i = 0; i < c.w * c.h; i++) {
    out[i * 4] = c.px[i * 4];
    out[i * 4 + 1] = w.px[i * 4 + 3];
    out[i * 4 + 3] = 255;
  }
  return Texture2D.fromPixels(out, c.w, c.h, content: TextureContent.data, sampling: _sampling);
}
