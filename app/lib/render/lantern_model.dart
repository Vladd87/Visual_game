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
  /// M11: 1.5 times the M7 size (9.6-10.2 cm wide, 12.75 cm of paper).
  /// Retail toro nagashi lanterns are about 15 cm across; at 6.6 cm the
  /// lantern was a toy next to real-size grass and pebbles, and its
  /// characters were too small to read from the camera.
  static const double scale = 1.5;
  static const double halfBottom = 0.032 * scale, halfTop = 0.034 * scale, trayTop = 0.012 * scale, height = 0.085 * scale;

  /// Height of the candle flame (and the light) above the lantern's base.
  static const double candleY = 0.035 * scale;

  /// The four paper panels. UV x = panel index + across (0-1), y = up (0-1),
  /// as lantern.fmat expects.
  /// M11: each panel is a grid, so the paper can bow outward a few
  /// millimetres between the corners, carry small wrinkles, and stand a
  /// little uneven at the rim: hand-folded paper, not a clean box (critics,
  /// every panel since M7: "a clean glowing box").
  static MeshGeometry paperPanels() {
    const nu = 8, nv = 10;
    final pos = <double>[], nrm = <double>[], uv = <double>[];
    final idx = <int>[];
    // Corners counter-clockwise seen from above, native axes (y up).
    const corners = [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]];
    // Each rim corner sits a little higher or lower (folded by hand).
    const rimLift = [0.0021, -0.0012, 0.0016, -0.0019];
    double h(int i, int j, int k) {
      final x = math.sin(i * 12.9898 + j * 78.233 + k * 37.719) * 43758.5453;
      return x - x.floorToDouble();
    }

    for (var k = 0; k < 4; k++) {
      final a = corners[k], b = corners[(k + 1) % 4];
      // Outward normal of this panel, in the horizontal plane.
      final nx = (a[1] + b[1]) == 0 ? (a[0] + b[0]) / 2 : 0.0;
      final nz = (a[0] + b[0]) == 0 ? (a[1] + b[1]) / 2 : 0.0;
      final base = pos.length ~/ 3;
      final grid = <List<double>>[];
      for (var i = 0; i <= nu; i++) {
        final t = i / nu;
        for (var j = 0; j <= nv; j++) {
          final v = j / nv;
          final half = halfBottom + (halfTop - halfBottom) * v;
          var x = (a[0] + (b[0] - a[0]) * t) * half;
          var z = (a[1] + (b[1] - a[1]) * t) * half;
          // Rim height: interpolate the two corners' lift along the top.
          final lift = (rimLift[k] * (1 - t) + rimLift[(k + 1) % 4] * t) * v;
          final y = trayTop + height * v + lift;
          // Bow: the paper bulges between the corners and the tray, most
          // near mid-height; a few small wrinkles on top. Corners and the
          // bottom edge stay put.
          final across = math.sin(math.pi * t);
          final upward = math.pow(math.sin(math.pi * (0.15 + 0.85 * v)), 0.8).toDouble();
          final interior = (i > 0 && i < nu && j > 0) ? 1.0 : 0.0;
          final wrinkle = (h(i, j, k) - 0.5) * 0.0016 * interior;
          final bow = 0.0045 * across * upward + wrinkle;
          x += nx * bow;
          z += nz * bow;
          grid.add([x, y, z]);
          uv.addAll([k + t, v]);
        }
      }
      // Normals from the grid (central differences), tilted a little up as
      // before so the dusk sky lights the outside faintly.
      for (var i = 0; i <= nu; i++) {
        for (var j = 0; j <= nv; j++) {
          final p0 = grid[(i > 0 ? i - 1 : i) * (nv + 1) + j], p1 = grid[(i < nu ? i + 1 : i) * (nv + 1) + j];
          final q0 = grid[i * (nv + 1) + (j > 0 ? j - 1 : j)], q1 = grid[i * (nv + 1) + (j < nv ? j + 1 : j)];
          final du = vm.Vector3(p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]);
          final dv = vm.Vector3(q1[0] - q0[0], q1[1] - q0[1], q1[2] - q0[2]);
          final n = dv.cross(du)..normalize();
          // Keep it facing outward.
          if (n.x * nx + n.z * nz < 0) n.negate();
          n.y += 0.12;
          n.normalize();
          final g = grid[i * (nv + 1) + j];
          pos.addAll(g);
          nrm.addAll([n.x, n.y, n.z]);
        }
      }
      for (var i = 0; i < nu; i++) {
        for (var j = 0; j < nv; j++) {
          final p00 = base + i * (nv + 1) + j, p10 = p00 + nv + 1;
          // Same winding as the M7 quads (a-bottom, b-bottom, b-top...).
          idx.addAll([p00, p10, p10 + 1, p00, p10 + 1, p00 + 1]);
        }
      }
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
