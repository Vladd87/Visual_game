import 'dart:math' as math;
import 'dart:typed_data';

import '../sim/course.dart';
import '../sim/vec2.dart';

/// CPU-side mesh arrays (positions, normals, vertex colours, indices).
class MeshArrays {
  MeshArrays(this.positions, this.normals, this.colors, this.indices);
  final Float32List positions;
  final Float32List normals;
  final Float32List colors;
  final List<int> indices;
}

/// Height of the ground (stream bed and banks) at sim point [p], in metres.
///
/// Water surface is y = 0. Inside the stream the bed slopes from a shallow
/// margin to ~13 cm in the middle; outside, the bank rises over ~12 cm then
/// undulates up to its crest.
double groundHeight(Course c, V2 p) {
  final clear = c.clearance(p);
  if (clear >= 0) {
    final depth = 0.025 + 0.105 * smoothstep(0.0, 0.28, clear);
    // A little bed relief so the water depth is not uniform.
    final relief = 0.012 * math.sin(p.x * 11.0 + p.y * 3.7) * math.sin(p.y * 5.3 - p.x * 2.1);
    return -depth + relief;
  }
  final out = -clear;
  final lip = smoothstep(0.0, 0.13, out); // the wet lip up to the bank top
  final crest = 0.09 + 0.07 * (0.5 + 0.5 * math.sin(p.y * 0.9 + p.x * 1.7)) +
      0.04 * math.sin(p.x * 4.1 - p.y * 2.3);
  final roll = smoothstep(0.1, 1.2, out) * (0.05 * math.sin(p.y * 1.7 + p.x * 3.1));
  return -0.025 + (crest + 0.025) * lip + roll;
}

/// Ground chunk covering stream distance [d0, d1] and [halfSpan] metres either
/// side of the centreline. Vertex colours carry the greybox palette.
MeshArrays buildGroundChunk(Course c, double d0, double d1,
    {double halfSpan = 2.6, double step = 0.05}) {
  final rows = ((d1 - d0) / step).ceil() + 1;
  final cols = (halfSpan * 2 / step).ceil() + 1;
  final pos = Float32List(rows * cols * 3);
  final col = Float32List(rows * cols * 4);
  final heights = Float64List(rows * cols);
  final xs = Float64List(rows * cols);
  final ds = Float64List(rows * cols);
  for (var i = 0; i < rows; i++) {
    final d = math.min(d0 + i * step, d1);
    // Follow the centreline, but widen around the pool so it is fully covered.
    final cx = c.centerX(d);
    for (var j = 0; j < cols; j++) {
      final x = cx - halfSpan + j * step;
      final p = V2(x, d);
      final h = groundHeight(c, p);
      final k = i * cols + j;
      heights[k] = h;
      xs[k] = x;
      ds[k] = d;
      pos[k * 3] = x;
      pos[k * 3 + 1] = h;
      pos[k * 3 + 2] = -d;
      // Greybox palette: muddy bed, dark wet lip, mossy bank, drier crest.
      final clear = c.clearance(p);
      double r, g, b;
      if (clear >= 0) {
        r = 0.16; g = 0.13; b = 0.095;
      } else {
        final t = smoothstep(0.0, 0.18, -clear);
        final dry = smoothstep(0.25, 1.4, -clear);
        r = lerpD(0.07, lerpD(0.11, 0.17, dry), t);
        g = lerpD(0.07, lerpD(0.15, 0.17, dry), t);
        b = lerpD(0.055, lerpD(0.06, 0.1, dry), t);
      }
      col[k * 4] = r;
      col[k * 4 + 1] = g;
      col[k * 4 + 2] = b;
      col[k * 4 + 3] = 1;
    }
  }
  final nrm = Float32List(rows * cols * 3);
  for (var i = 0; i < rows; i++) {
    for (var j = 0; j < cols; j++) {
      final k = i * cols + j;
      final int kl = i * cols + math.max<int>(0, j - 1), kr = i * cols + math.min<int>(cols - 1, j + 1);
      final int ku = math.max<int>(0, i - 1) * cols + j, kd = math.min<int>(rows - 1, i + 1) * cols + j;
      final dhx = (heights[kr] - heights[kl]) / math.max(1e-6, xs[kr] - xs[kl]);
      final dhd = (heights[kd] - heights[ku]) / math.max(1e-6, ds[kd] - ds[ku]);
      // World: x → X, d → -Z. Normal of y = h(x, z) with dh/dz = -dh/dd.
      var nx = -dhx, ny = 1.0, nz = dhd;
      final l = math.sqrt(nx * nx + ny * ny + nz * nz);
      nrm[k * 3] = nx / l;
      nrm[k * 3 + 1] = ny / l;
      nrm[k * 3 + 2] = nz / l;
    }
  }
  final idx = <int>[];
  for (var i = 0; i < rows - 1; i++) {
    for (var j = 0; j < cols - 1; j++) {
      final a = i * cols + j, b = a + 1, cc = a + cols, d = cc + 1;
      // Rows run toward -Z, so this order faces +Y (mirror of PlaneGeometry's).
      idx..add(a)..add(b)..add(cc);
      idx..add(b)..add(d)..add(cc);
    }
  }
  return MeshArrays(pos, nrm, col, idx);
}

/// Flat water surface (y = 0) covering the channel (plus a margin under the
/// banks) and the pool, for stream distance [d0, d1].
MeshArrays buildWaterChunk(Course c, double d0, double d1, {double step = 0.08}) {
  final rows = ((d1 - d0) / step).ceil() + 1;
  const cols = 24;
  final pos = Float32List(rows * cols * 3);
  final nrm = Float32List(rows * cols * 3);
  final col = Float32List(rows * cols * 4);
  for (var i = 0; i < rows; i++) {
    final d = math.min(d0 + i * step, d1);
    final cx = c.centerX(d);
    var hw = d <= c.length + 0.3 ? c.halfWidth(d) + 0.22 : 0.0;
    final dp = d - c.poolCenter.y;
    if (dp.abs() < c.poolRadius + 0.3) {
      hw = math.max(hw, math.sqrt(math.max(0, (c.poolRadius + 0.3) * (c.poolRadius + 0.3) - dp * dp)) + (c.poolCenter.x - cx).abs());
    }
    for (var j = 0; j < cols; j++) {
      final x = cx - hw + 2 * hw * j / (cols - 1);
      final k = i * cols + j;
      pos[k * 3] = x;
      pos[k * 3 + 1] = 0;
      pos[k * 3 + 2] = -d;
      nrm[k * 3 + 1] = 1;
      col[k * 4] = 1;
      col[k * 4 + 1] = 1;
      col[k * 4 + 2] = 1;
      col[k * 4 + 3] = 1;
    }
  }
  final idx = <int>[];
  for (var i = 0; i < rows - 1; i++) {
    for (var j = 0; j < cols - 1; j++) {
      final a = i * cols + j, b = a + 1, cc = a + cols, d = cc + 1;
      idx..add(a)..add(b)..add(cc);
      idx..add(b)..add(d)..add(cc);
    }
  }
  return MeshArrays(pos, nrm, col, idx);
}
