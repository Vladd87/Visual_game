import 'dart:math' as math;
import 'dart:typed_data';

import '../sim/course.dart';
import '../sim/flow_field.dart';
import '../sim/vec2.dart';
import 'rock_layout.dart';

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
double groundHeight(Course c, V2 p) =>
    applyMounds(rockPlacements(c, flatGroundHeight), p, flatGroundHeight(c, p));

/// Shoreline wander (metres) so the water's edge is not a clean spline: the
/// render's banks move up to ~5 cm in or out of the sim's channel edge.
double shoreNoise(V2 p) =>
    0.024 * math.sin(p.y * 7.3 + p.x * 1.1) +
    0.014 * math.sin(p.y * 17.9 - p.x * 3.3 + 1.7) +
    0.007 * math.sin(p.y * 41.0 + p.x * 5.0 + 0.4);

/// Ground height before rock mounds.
double flatGroundHeight(Course c, V2 p) {
  final clear = c.clearance(p) + shoreNoise(p);
  if (clear >= 0) {
    // Shallow margins over a deep, dark centre (~28 cm): refs 08, 09, 11.
    final depth = 0.02 + 0.26 * smoothstep(0.0, 0.34, clear);
    // A little bed relief so the water depth is not uniform.
    final relief = 0.012 * math.sin(p.x * 11.0 + p.y * 3.7) * math.sin(p.y * 5.3 - p.x * 2.1);
    return -depth + relief;
  }
  final out = -clear;
  final lip = smoothstep(0.0, 0.22, out); // the wet lip up to the bank top
  final crest = 0.09 + 0.07 * (0.5 + 0.5 * math.sin(p.y * 0.9 + p.x * 1.7)) +
      0.04 * math.sin(p.x * 4.1 - p.y * 2.3);
  final roll = smoothstep(0.1, 1.2, out) * (0.05 * math.sin(p.y * 1.7 + p.x * 3.1));
  // Past the lip the bank never sags back toward the waterline.
  return math.max(-0.025 + (crest + 0.025) * lip + roll, -0.025 + 0.085 * lip);
}

/// Ground chunk covering stream distance [d0, d1] and [halfSpan] metres either
/// side of the centreline. Vertex colours carry shader data (see ground.fmat).
MeshArrays buildGroundChunk(Course c, double d0, double d1,
    {double halfSpan = 2.8, double step = 0.04}) {
  final rows = ((d1 - d0) / step).ceil() + 1;
  final cols = (halfSpan * 2 / step).ceil() + 1;
  final pos = Float32List(rows * cols * 3);
  final col = Float32List(rows * cols * 4);
  final heights = Float64List(rows * cols);
  final xs = Float64List(rows * cols);
  final ds = Float64List(rows * cols);
  final placements = rockPlacements(c, flatGroundHeight);
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
      // Data for ground.fmat: r = rock mound weight, g = distance out of the
      // channel, b = contact occlusion beside rocks.
      final flat = flatGroundHeight(c, p);
      col[k * 4] = clamp01((h - flat) / 0.03);
      col[k * 4 + 1] = clamp01(-c.clearance(p) / 1.5);
      col[k * 4 + 2] = rockContact(placements, p, h);
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

/// Water surface (y = 0) covering the channel (plus a margin under the banks)
/// and the pool, for stream distance [d0, d1].
///
/// Vertex colours carry what the water shader needs (see water.fmat):
/// rg = surface flow (sim axes, v * 2 + 0.5), b = foam potential,
/// a = turbulence near rocks.
MeshArrays buildWaterChunk(Course c, FlowField flow, double d0, double d1, {double step = 0.03}) {
  final rows = ((d1 - d0) / step).ceil() + 1;
  const cols = 56;
  final pos = Float32List(rows * cols * 3);
  final nrm = Float32List(rows * cols * 3);
  final col = Float32List(rows * cols * 4);
  for (var i = 0; i < rows; i++) {
    final d = math.min(d0 + i * step, d1);
    final cx = c.centerX(d);
    var lo = cx - (c.halfWidth(d) + 0.22), hi = cx + (c.halfWidth(d) + 0.22);
    if (d > c.length + 0.3) {
      lo = hi = cx;
    }
    final dp = d - c.poolCenter.y;
    final pr = c.poolRadius + 0.3;
    if (dp.abs() < pr) {
      final half = math.sqrt(math.max(0, pr * pr - dp * dp));
      lo = math.min(lo, c.poolCenter.x - half);
      hi = math.max(hi, c.poolCenter.x + half);
    }
    final rocks = c.rocksNear(d - 0.6, d + 0.25).where((r) => r.emergent).toList();
    final speed0 = c.flowSpeed(d);
    for (var j = 0; j < cols; j++) {
      final x = lo + (hi - lo) * j / (cols - 1);
      final k = i * cols + j;
      final p = V2(x, d);
      pos[k * 3] = x;
      pos[k * 3 + 1] = 0;
      pos[k * 3 + 2] = -d;
      nrm[k * 3 + 1] = 1;
      final v = flow.velocityAt(p, 0);
      // Foam: fronts and flanks of emergent rocks, their wakes, and bank lines,
      // stronger where the current is fast.
      var foam = 0.0, turb = 0.0;
      for (final r in rocks) {
        final rel = p - r.pos;
        final dist = rel.length;
        final gap = dist - r.radius;
        if (gap < 0.3) {
          final n = dist > 1e-6 ? rel / dist : const V2(0, -1);
          // Upstream cushion: water piles against the front face (refs 04, 13).
          final front = clamp01(-n.y * 1.25);
          foam = math.max(foam, math.exp(-math.max(gap, 0) / 0.05) * front * 0.75);
          // Thin collar where the water wraps the stone sides.
          foam = math.max(foam, math.exp(-math.max(gap, 0) / 0.01) * 0.18);
          turb = math.max(turb, math.exp(-math.max(gap, 0) / 0.08));
        }
        // Wake: foam streaks shed from both flanks, drifting downstream and
        // slowly converging and spreading (refs 04, 13).
        final len = r.radius * 12;
        if (rel.y > -r.radius * 0.3 && rel.y < len) {
          final k = clamp01(rel.y / len);
          final fade = math.pow(1 - k, 1.6).toDouble();
          final lineX = r.radius * (0.95 - 0.35 * k);
          final width = 0.012 + 0.03 * k;
          final edge = (rel.x.abs() - lineX).abs();
          foam = math.max(foam, math.exp(-edge / width) * fade * 0.85);
          if (rel.x.abs() < r.radius * 1.3) turb = math.max(turb, fade * 0.8);
        }
      }
      final clear = c.clearance(p);
      if (clear > -0.05) foam = math.max(foam, math.exp(-math.max(clear, 0) / 0.01) * 0.22);
      final fast = clamp01(speed0 / 0.22);
      foam *= 0.3 + 0.9 * fast;
      col[k * 4] = (v.x * 2 + 0.5).clamp(0.0, 1.0);
      col[k * 4 + 1] = (v.y * 2 + 0.5).clamp(0.0, 1.0);
      col[k * 4 + 2] = clamp01(foam);
      col[k * 4 + 3] = clamp01(turb);
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
