import 'dart:math' as math;

import '../sim/course.dart';
import '../sim/rng.dart';
import '../sim/vec2.dart';
import 'rock_profiles.g.dart';

export 'rock_profiles.g.dart' show kRockTypeHeights;

/// How one rock is shown: which scan, its transform, and the gravel mound
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
    required this.shore,
  });

  final Rock rock;
  final int type;
  final double yaw;
  final double sx, sz, sy; // scale applied to the unit-footprint scan
  final double baseY; // world y of the scan's base
  final double mound; // top of the gravel mound under it (-inf: none)
  final bool shore; // render-only shore stone (not in the sim)

  double get reach => math.max(sx, sz);
  double get height => kRockTypeHeights[type] * sy;
  double get topY => baseY + height;

  /// Horizontal distance (metres, approximate) from [p] to the scan's
  /// surface at world height [y]: negative inside the rock, null when [y] is
  /// outside the rock's height range.
  double? surfaceGap(V2 p, double y) {
    final f = (y - baseY) / height;
    if (f < 0 || f > 1) return null;
    final dx = p.x - rock.pos.x, wz = -(p.y - rock.pos.y);
    final c = math.cos(yaw), s = math.sin(yaw);
    final lx = (c * dx - s * wz) / sx;
    final lz = (s * dx + c * wz) / sz;
    final e = math.sqrt(lx * lx + lz * lz);
    final rho = profileRadius(type, f, math.atan2(lz, lx));
    return (e - rho) * (sx + sz) * 0.5;
  }
}

/// Radial extent of scan [type]'s unit footprint at height fraction [f]
/// (0 = base, 1 = top) toward azimuth [az] (atan2(z, x), native axes).
double profileRadius(int type, double f, double az) {
  final prof = kRockProfiles[type];
  const nl = kRockProfileLevels, ns = kRockProfileSectors;
  final lf = f.clamp(0.0, 1.0) * (nl - 1);
  final l0 = lf.floor().clamp(0, nl - 2);
  final tl = lf - l0;
  final sf = (az + math.pi) / (2 * math.pi) * ns - 0.5;
  final s0 = sf.floor();
  final ts = sf - s0;
  double at(int l, int s) => prof[l * ns + ((s % ns) + ns) % ns];
  final a = lerpD(at(l0, s0), at(l0, s0 + 1), ts);
  final b = lerpD(at(l0 + 1, s0), at(l0 + 1, s0 + 1), ts);
  return lerpD(a, b, tl);
}

double _meanRadius(int type, double f) {
  var sum = 0.0;
  for (var i = 0; i < kRockProfileSectors; i++) {
    sum += profileRadius(type, f, -math.pi + (i + 0.5) * 2 * math.pi / kRockProfileSectors);
  }
  return sum / kRockProfileSectors;
}

/// Ground height without rock mounds (supplied by terrain.dart).
typedef FlatGround = double Function(Course c, V2 p);

final Expando<List<RockPlacement>> _cache = Expando('rockPlacements');

/// Placements for every sim rock of [c] plus render-only shore stones,
/// sorted downstream (by pos.y).
List<RockPlacement> rockPlacements(Course c, FlatGround flat) => _cache[c] ??= () {
      final list = [
        for (final r in c.rocks) _place(c, r, flat, shore: false),
        for (final r in _shoreStones(c, flat)) _place(c, r, flat, shore: true),
      ];
      list.sort((a, b) => a.rock.pos.y.compareTo(b.rock.pos.y));
      return list;
    }();

/// Small stones along both margins that step down into the water (refs 03,
/// 07, 13). Render only: they sit on the bank lip, outside the sim's lane.
List<Rock> _shoreStones(Course c, FlatGround flat) {
  final r = Rng(c.seed * 31 + 17);
  final out = <Rock>[];
  for (final side in [-1.0, 1.0]) {
    var d = 0.3 + r.range(0, 0.4);
    while (d < c.length - 0.5) {
      // Clusters: a few stones close together, then a gap.
      final n = 1 + r.intBelow(4);
      for (var i = 0; i < n; i++) {
        final dd = d + r.range(-0.12, 0.12);
        final radius = r.range(0.022, 0.05 + 0.05 * r.next());
        final hw = c.halfWidth(dd);
        final lat = side * (hw + 0.025 + radius * 0.6 + r.range(0, 0.12));
        out.add(Rock(V2(c.centerX(dd) + lat, dd), radius, -1, emergent: true, seed: r.nextU32()));
      }
      d += r.range(0.25, 1.1);
    }
  }
  return out;
}

double _frac(int seed, int shift) => ((seed >> shift) & 0xff) / 255.0;

RockPlacement _place(Course c, Rock r, FlatGround flat, {required bool shore}) {
  final type = r.seed % kRockTypeHeights.length;
  final h = kRockTypeHeights[type];
  final yaw = _frac(r.seed, 8) * 2 * math.pi;
  final aniso = 0.85 + 0.3 * _frac(r.seed, 16);
  final ky = 0.85 + 0.3 * _frac(r.seed, 24);
  // Lowest bed under the footprint (banks slope).
  final bedCenter = flat(c, r.pos);
  var bed = bedCenter;
  for (var k = 0; k < 6; k++) {
    final a = k * math.pi / 3;
    bed = math.min(bed, flat(c, V2(r.pos.x + math.cos(a) * r.radius * 0.8, r.pos.y + math.sin(a) * r.radius * 0.8)));
  }
  // Scale so the scan's mean waterline width matches the sim radius (the
  // scans taper, so their full extent is wider than their waterline).
  var scale = r.radius;
  late double sy, base, top, hr, mound;
  for (var iter = 0; iter < 3; iter++) {
    sy = scale * ky;
    // Keep at least ~45 % of a boulder above the ground it sits on.
    top = math.max(r.height, bedCenter + 0.45 * h * sy);
    // A rock that cannot reach the bed with a quarter buried is stretched up
    // to 1.25x, then a gravel mound lifts the bed the rest of the way (rocks
    // resting on gravel bars, refs 08, 09). Emergent mounds stay underwater.
    hr = h * sy;
    final need = top - bed;
    if (hr * 0.75 < need) {
      final stretched = math.min(need / 0.75, hr * 1.25);
      sy *= stretched / hr;
      hr = stretched;
    }
    base = top - hr;
    mound = double.negativeInfinity;
    if (base + 0.25 * hr > bed) {
      mound = base + 0.25 * hr;
      final cap = r.emergent ? -0.012 : top - 0.01;
      if (mound > cap && bed < 0) {
        mound = math.max(cap, bed);
        base = mound - 0.25 * hr;
        top = base + hr;
      }
    }
    if (shore || top <= 0 || base >= 0) break;
    final rho = _meanRadius(type, (0 - base) / hr);
    final want = r.radius / rho.clamp(0.45, 1.0);
    final next = want.clamp(r.radius, r.radius * 1.5);
    if ((next - scale).abs() < 1e-4) break;
    scale = next;
  }
  return RockPlacement(
    rock: r,
    type: type,
    yaw: yaw,
    sx: scale * aniso,
    sz: scale / aniso,
    sy: sy,
    baseY: base,
    mound: mound,
    shore: shore,
  );
}

int _firstAtOrAfter(List<RockPlacement> placements, double y) {
  var lo = 0, hi = placements.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (placements[mid].rock.pos.y < y) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Placements whose centre lies in stream distance [d0, d1].
Iterable<RockPlacement> placementsNear(List<RockPlacement> placements, double d0, double d1) sync* {
  for (var i = _firstAtOrAfter(placements, d0); i < placements.length; i++) {
    if (placements[i].rock.pos.y > d1) break;
    yield placements[i];
  }
}

/// Raises [h] (flat ground at [p]) by the gravel mounds of nearby rocks.
double applyMounds(List<RockPlacement> placements, V2 p, double h) {
  for (final pl in placementsNear(placements, p.y - 0.6, p.y + 0.6)) {
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
/// the dark crease where a stone meets the bed or bank, following the scan's
/// own outline at that height.
double rockContact(List<RockPlacement> placements, V2 p, double h) {
  var occ = 0.0;
  for (final pl in placementsNear(placements, p.y - 0.4, p.y + 0.4)) {
    final gap = pl.surfaceGap(p, h);
    if (gap == null) continue;
    final reach = math.min(0.06, pl.reach * 0.45);
    occ = math.max(occ, smoothstep(reach, -0.01, gap));
  }
  return occ;
}
