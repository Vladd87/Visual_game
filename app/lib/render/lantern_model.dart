import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// M7: a floating paper lantern (toro nagashi, ref02) in place of the
/// glowing cube critics flagged in every panel: four paper panels on a
/// wooden tray, open at the top.
class LanternModel {
  /// Half-width of the paper at the tray and at the rim (m), the tray's top
  /// and the paper's height. ref02's lantern is taller than wide and opens
  /// a little toward the rim.
  static const double halfBottom = 0.032, halfTop = 0.034, trayTop = 0.012, height = 0.085;

  /// The four paper panels. UV x = panel index + across (0-1), y = up (0-1),
  /// as lantern.fmat expects.
  static MeshGeometry paperPanels() {
    final pos = <double>[], nrm = <double>[], uv = <double>[];
    final idx = <int>[];
    // Corners counter-clockwise seen from above, native axes (y up).
    const corners = [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]];
    for (var k = 0; k < 4; k++) {
      final a = corners[k], b = corners[(k + 1) % 4];
      final nx = (a[1] + b[1]) == 0 ? (a[0] + b[0]) / 2 : 0.0;
      final nz = (a[0] + b[0]) == 0 ? (a[1] + b[1]) / 2 : 0.0;
      final base = pos.length ~/ 3;
      for (final (c, t) in [(a, 0.0), (b, 1.0)]) {
        for (final (y, half, v) in [(trayTop, halfBottom, 0.0), (trayTop + height, halfTop, 1.0)]) {
          pos.addAll([c[0] * half, y, c[1] * half]);
          nrm.addAll([nx, 0.12, nz]);
          uv.addAll([k + t, v]);
        }
      }
      // base: a-bottom, a-top, b-bottom, b-top
      idx.addAll([base, base + 2, base + 3, base, base + 3, base + 1]);
    }
    return MeshGeometry.fromArrays(
      positions: Float32List.fromList(pos),
      normals: Float32List.fromList(nrm),
      texCoords: Float32List.fromList(uv),
      indices: idx,
    );
  }

  /// The wooden tray the paper stands in, as (centre, size); its lower part
  /// sits in the water. ref02 shows no other frame: the paper corners are
  /// folded (lantern.fmat darkens them a little).
  static (vm.Vector3, vm.Vector3) tray() =>
      (vm.Vector3(0, trayTop / 2, 0), vm.Vector3(halfBottom * 2 + 0.005, trayTop, halfBottom * 2 + 0.005));

  /// The tray floor inside the paper, lit by the candle: a quad just above
  /// the tray top.
  static MeshGeometry floor() {
    const h = halfBottom - 0.0005, y = trayTop + 0.0005;
    return MeshGeometry.fromArrays(
      positions: Float32List.fromList([-h, y, -h, h, y, -h, h, y, h, -h, y, h]),
      normals: Float32List.fromList([0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0]),
      texCoords: Float32List.fromList([0, 0, 1, 0, 1, 1, 0, 1]),
      indices: const [0, 2, 1, 0, 3, 2],
    );
  }

  /// A candle flame: a soft teardrop, brightest in a small core.
  static Texture2D flameTexture() {
    const w = 32, h = 64;
    final px = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final fx = (x + 0.5) / w * 2 - 1;
        final fy = (y + 0.5) / h; // 0 at the top of the texture
        // Narrow at the tip (top), round at the base.
        final width = 0.25 + 0.75 * math.sqrt(math.max(0.0, fy));
        final d = (fx / width) * (fx / width) + math.pow((fy - 0.7) / 0.55, 2);
        final v = (math.exp(-d * 3.0) * (1 - fy * 0.2)).clamp(0.0, 1.0);
        final o = (y * w + x) * 4;
        final b = (255 * v).round();
        px[o] = b;
        px[o + 1] = b;
        px[o + 2] = b;
        px[o + 3] = b;
      }
    }
    return Texture2D.fromPixels(px, w, h, content: TextureContent.color);
  }
}
