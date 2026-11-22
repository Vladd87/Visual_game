import 'dart:math' as math;

import '../sim/course.dart';
import '../sim/vec2.dart';

/// Height / horizontal half-extent of each baked rock scan, in the order of
/// assets/rocks/rocks.bin (printed by tools/bake/bake_rocks.py).
const List<double> kRockTypeHeights = [
  0.873, 0.775, 1.043, 1.657, 0.804, 0.918, // rock_moss_set_01
  0.878, 0.746, 0.930, 1.201, 0.696, 1.335, 0.875, // rock_moss_set_02
];

/// How one sim rock is shown: which scan, its transform, and the gravel mound
/// the bed gets under it so it never floats.
class RockPlacement {
  RockPlacement({
    required this.rock,
    required this.type,
    required this.yaw,
    required this.sx,
    required this.sz,
    required this.sy,
    required this.baseY,
    required this.mound,
  });

  final Rock rock;
  final int type;
  final double yaw;
  final double sx, sz, sy; // scale applied to the unit-footprint scan
  final double baseY; // world y of the scan's base
  final double mound; // top of the gravel mound under it (-inf: none)

  double get reach => math.max(sx, sz);
  double get topY => baseY + kRockTypeHeights[type] * sy;
}

/// Ground height without rock mounds (supplied by terrain.dart).
typedef FlatGround = double Function(Course c, V2 p);

final Expando<List<RockPlacement>> _cache = Expando('rockPlacements');

/// Placements for every rock of [c], in the same (downstream-sorted) order.
List<RockPlacement> rockPlacements(Course c, FlatGround flat) =>
    _cache[c] ??= [for (final r in c.rocks) _place(c, r, flat)];

double _frac(int seed, int shift) => ((seed >> shift) & 0xff) / 255.0;

RockPlacement _place(Course c, Rock r, FlatGround flat) {
  final type = r.seed % kRockTypeHeights.length;
  final h = kRockTypeHeights[type];
  final yaw = _frac(r.seed, 8) * 2 * math.pi;
  final aniso = 0.85 + 0.3 * _frac(r.seed, 16);
  final sx = r.radius * aniso, sz = r.radius / aniso;
  var sy = r.radius * (0.85 + 0.3 * _frac(r.seed, 24));
  // Lowest bed under the footprint (banks slope).
  var bed = flat(c, r.pos);
  for (var k = 0; k < 6; k++) {
    final a = k * math.pi / 3;
    bed = math.min(bed, flat(c, V2(r.pos.x + math.cos(a) * r.radius * 0.8, r.pos.y + math.sin(a) * r.radius * 0.8)));
  }
  // Keep at least ~45 % of a bank boulder above its bank.
  var top = math.max(r.height, flat(c, r.pos) + 0.45 * h * sy);
  // A rock that cannot reach the bed with a quarter buried is stretched up to
  // 1.5x, then a gravel mound lifts the bed the rest of the way (rocks resting
  // on gravel bars, refs 08, 09). Emergent mounds stay under the water.
  var hr = h * sy;
  final need = top - bed;
  if (hr * 0.75 < need) {
    final stretched = math.min(need / 0.75, hr * 1.5);
    sy *= stretched / hr;
    hr = stretched;
  }
  var base = top - hr;
  var mound = double.negativeInfinity;
  if (base + 0.25 * hr > bed) {
    mound = base + 0.25 * hr;
    final cap = r.emergent ? -0.012 : top - 0.01;
    if (mound > cap && bed < 0) {
      mound = math.max(cap, bed);
      base = mound - 0.25 * hr;
      top = base + hr;
    }
  }
  return RockPlacement(rock: r, type: type, yaw: yaw, sx: sx, sz: sz, sy: sy, baseY: base, mound: mound);
}

/// Raises [h] (flat ground at [p]) by the gravel mounds of nearby rocks.
double applyMounds(List<RockPlacement> placements, V2 p, double h) {
  // placements follow c.rocks, sorted by pos.y: binary search the window.
  var lo = 0, hi = placements.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (placements[mid].rock.pos.y < p.y - 0.6) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  for (var i = lo; i < placements.length; i++) {
    final pl = placements[i];
    if (pl.rock.pos.y > p.y + 0.6) break;
    if (pl.mound <= h) continue;
    final dx = p.x - pl.rock.pos.x, dy = p.y - pl.rock.pos.y;
    final dist = math.sqrt(dx * dx + dy * dy);
    final r = pl.reach;
    if (dist > r * 2.4) continue;
    final w = smoothstep(r * 2.4, r * 0.8, dist);
    h = math.max(h, lerpD(h, pl.mound, w));
  }
  return h;
}

/// Contact occlusion (0..1) on the ground at [p] (height [h]) beside rocks:
/// the dark crease where a stone meets the bed or bank.
double rockContact(List<RockPlacement> placements, V2 p, double h) {
  var lo = 0, hi = placements.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (placements[mid].rock.pos.y < p.y - 0.4) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  var occ = 0.0;
  for (var i = lo; i < placements.length; i++) {
    final pl = placements[i];
    if (pl.rock.pos.y > p.y + 0.4) break;
    if (h < pl.baseY || h > pl.topY) continue;
    final dx = p.x - pl.rock.pos.x, dy = p.y - pl.rock.pos.y;
    // Ellipse distance in the rock's own frame (scan x/z scaled by sx/sz).
    // World z = -sim y, and the instance yaw turns about +Y.
    final wx = dx, wz = -dy;
    final c = math.cos(pl.yaw), s = math.sin(pl.yaw);
    final lx = (c * wx - s * wz) / pl.sx;
    final lz = (s * wx + c * wz) / pl.sz;
    final e = math.sqrt(lx * lx + lz * lz);
    occ = math.max(occ, smoothstep(1.45, 0.9, e));
  }
  return occ;
}
