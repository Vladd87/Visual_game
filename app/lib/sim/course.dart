import 'dart:math' as math;

import 'rng.dart';
import 'vec2.dart';

/// Gameplay character of one stretch of the stream.
class SectionSpec {
  const SectionSpec({
    required this.name,
    required this.length,
    required this.flow,
    required this.halfWidth,
    required this.rain,
    required this.fog,
    required this.rockDensity,
    required this.eddies,
    required this.fireflyGroups,
    required this.leafRate,
  });

  final String name;
  final double length; // metres of stream
  final double flow; // surface current, m/s
  final double halfWidth; // metres
  final double rain; // 0..1
  final double fog; // 0..1
  final double rockDensity; // emergent rocks per metre
  final int eddies;
  final int fireflyGroups;
  final double leafRate; // falling leaves per second while the lantern is here
}

/// The six sections from PLAN.md §2, in stream order.
const List<SectionSpec> kSections = [
  SectionSpec(name: 'calm reach', length: 6, flow: 0.15, halfWidth: 0.42, rain: 0.15, fog: 0.35, rockDensity: 0.5, eddies: 0, fireflyGroups: 2, leafRate: 0.0),
  SectionSpec(name: 'rock garden', length: 8, flow: 0.24, halfWidth: 0.38, rain: 0.2, fog: 0.3, rockDensity: 2.2, eddies: 2, fireflyGroups: 2, leafRate: 0.05),
  SectionSpec(name: 'fern tunnel', length: 7, flow: 0.19, halfWidth: 0.32, rain: 0.3, fog: 0.4, rockDensity: 0.9, eddies: 1, fireflyGroups: 2, leafRate: 0.55),
  SectionSpec(name: 'rain meadow', length: 8, flow: 0.2, halfWidth: 0.45, rain: 0.9, fog: 0.45, rockDensity: 0.8, eddies: 1, fireflyGroups: 4, leafRate: 0.1),
  SectionSpec(name: 'misty narrows', length: 7, flow: 0.27, halfWidth: 0.26, rain: 0.5, fog: 0.85, rockDensity: 1.4, eddies: 4, fireflyGroups: 2, leafRate: 0.15),
  SectionSpec(name: 'pool approach', length: 4, flow: 0.13, halfWidth: 0.4, rain: 0.25, fog: 0.5, rockDensity: 0.4, eddies: 0, fireflyGroups: 1, leafRate: 0.0),
];

class Section {
  Section(this.spec, this.startD, this.endD);
  final SectionSpec spec;
  final double startD;
  final double endD;
}

class Rock {
  Rock(this.pos, this.radius, this.height, {required this.emergent, required this.seed});
  final V2 pos;
  final double radius;
  final double height; // top above water (emergent) or below (submerged, negative)
  final bool emergent; // emergent rocks collide; submerged only shape the flow
  final int seed; // visual variation
}

class Eddy {
  Eddy(this.pos, this.radius, this.strength);
  final V2 pos;
  final double radius;
  final double strength; // tangential speed at radius, m/s; sign = spin
}

class FireflySpawn {
  FireflySpawn(this.home, this.height, this.phase);
  final V2 home;
  final double height; // above water, metres
  final double phase;
}

/// Seeded stream course: centreline, width, sections, obstacles and pickups.
class Course {
  Course._(this.seed, this.sections, this.length, this.poolRadius, this._phase1, this._phase2) {
    poolCenter = V2(centerX(length), length + poolRadius * 0.85);
  }

  final int seed;
  final List<Section> sections;
  final double length; // where the channel meets the pool
  late final V2 poolCenter;
  final double poolRadius;
  final double _phase1;
  final double _phase2;

  final List<Rock> rocks = [];
  final List<Eddy> eddies = [];
  final List<FireflySpawn> fireflies = [];

  /// Total extent of the playable world along the stream.
  double get endD => poolCenter.y + poolRadius;

  static const double startD = 0.0;
  static const double lanternRadius = 0.045;

  factory Course.generate(int seed) {
    final rng = Rng(seed);
    final sections = <Section>[];
    var d = 0.0;
    for (final s in kSections) {
      sections.add(Section(s, d, d + s.length));
      d += s.length;
    }
    final course = Course._(seed, sections, d, 1.35, rng.range(0, math.pi * 2), rng.range(0, math.pi * 2));
    course._populate(rng.fork(1));
    return course;
  }

  // --- geometry -------------------------------------------------------------

  /// Raw meander, before easing into the pool.
  double _meander(double d) =>
      0.38 * math.sin(2 * math.pi * d / 9.0 + _phase1) +
      0.16 * math.sin(2 * math.pi * d / 4.7 + _phase2) +
      0.05 * math.sin(2 * math.pi * d / 2.1 + _phase1 * 1.7);

  /// Centreline x at distance [d]: eases in from a straight start, meanders,
  /// then straightens over the last 4 m into the pool.
  double centerX(double d) {
    final m = _meander(d) * smoothstep(0, 3, d);
    final tail = smoothstep(length - 4, length, d);
    final settle = _meander(length - 4);
    return m * (1 - tail) + settle * tail;
  }

  /// Slope dx/dd of the centreline.
  double centerSlope(double d) => (centerX(d + 0.01) - centerX(d - 0.01)) / 0.02;

  /// Unit tangent (downstream) of the centreline.
  V2 tangent(double d) => V2(centerSlope(d), 1).normalized();

  Section sectionAt(double d) {
    for (final s in sections) {
      if (d < s.endD) return s;
    }
    return sections.last;
  }

  /// Smoothly blended section parameter (1.5 m transitions).
  double param(double d, double Function(SectionSpec s) f) {
    final s = sectionAt(d);
    final idx = sections.indexOf(s);
    var v = f(s.spec);
    if (idx > 0) {
      final prev = f(sections[idx - 1].spec);
      v = lerpD(prev, v, smoothstep(s.startD - 0.75, s.startD + 0.75, d));
    }
    if (idx < sections.length - 1) {
      final next = f(sections[idx + 1].spec);
      v = lerpD(v, next, smoothstep(s.endD - 0.75, s.endD + 0.75, d));
    }
    return v;
  }

  /// Channel half-width at [d] (the pool is handled separately).
  double halfWidth(double d) =>
      param(d, (s) => s.halfWidth) *
      (1 + 0.12 * math.sin(2 * math.pi * d / 3.3 + _phase2 * 0.7));

  double flowSpeed(double d) {
    final base = param(d, (s) => s.flow);
    // Current dies away inside the pool.
    final intoPool = smoothstep(length - 0.5, length + poolRadius * 0.6, d);
    return base * (1 - 0.9 * intoPool);
  }

  bool inPool(V2 p) => (p - poolCenter).length < poolRadius;

  /// Signed clearance from [p] to the nearest bank (positive = inside water).
  double clearance(V2 p) {
    final inChannel = p.y <= length + 0.2
        ? halfWidth(p.y) - (p.x - centerX(p.y)).abs()
        : -1.0;
    final inPoolC = poolRadius - (p - poolCenter).length;
    var c = math.max(inChannel, inPoolC);
    if (p.y < startD - 0.5) c = math.min(c, p.y - (startD - 0.5) + 1.0);
    return c;
  }

  /// Outward bank normal near [p] (pointing from water into the bank).
  V2 bankNormal(V2 p) {
    const e = 0.005;
    final gx = clearance(V2(p.x + e, p.y)) - clearance(V2(p.x - e, p.y));
    final gy = clearance(V2(p.x, p.y + e)) - clearance(V2(p.x, p.y - e));
    return (-V2(gx, gy)).normalized();
  }

  // --- population -----------------------------------------------------------

  void _populate(Rng rng) {
    for (final sec in sections) {
      final spec = sec.spec;
      final r = rng.fork(sec.startD.round() + 7);
      // Emergent rocks: Poisson-ish spacing along the section.
      var d = sec.startD + (sec == sections.first ? 2.5 : 0.3);
      while (true) {
        d += -math.log(1 - r.next() * 0.999) / math.max(spec.rockDensity, 0.05);
        if (d > sec.endD - 0.2) break;
        final hw = halfWidth(d);
        final radius = r.range(0.05, 0.11 + 0.12 * r.next());
        var lat = r.range(-1, 1) * (hw - radius * 0.3);
        // No pockets: a rock either meets the bank or leaves a passable gap.
        const need = Course.lanternRadius * 2 + 0.06;
        final leftGap = (lat - radius) + hw;
        final rightGap = hw - (lat + radius);
        if (leftGap > 0 && leftGap < need) lat = -hw + radius * 0.5;
        if (rightGap > 0 && rightGap < need) lat = hw - radius * 0.5;
        final pos = V2(centerX(d) + lat, d);
        if (_lanePassable(pos, radius) && _noPocket(pos, radius)) {
          rocks.add(Rock(pos, radius, r.range(0.02, 0.07) + radius * 0.4, emergent: true, seed: r.nextU32()));
        }
      }
      // Submerged rocks shape the surface and the flow but never collide.
      final submerged = (spec.length * (1.0 + spec.rockDensity)).round();
      for (var i = 0; i < submerged; i++) {
        final dd = r.range(sec.startD, sec.endD);
        final hw = halfWidth(dd);
        rocks.add(Rock(V2(centerX(dd) + r.range(-0.9, 0.9) * hw, dd), r.range(0.04, 0.12),
            -r.range(0.01, 0.05), emergent: false, seed: r.nextU32()));
      }
      // Bank boulders, half in the water at the edges.
      final boulders = (spec.length * 0.9).round();
      for (var i = 0; i < boulders; i++) {
        final dd = r.range(sec.startD, sec.endD);
        final side = r.chance(0.5) ? -1.0 : 1.0;
        final radius = r.range(0.08, 0.22);
        var out = r.range(0.1, 0.6);
        var pos = V2(centerX(dd) + side * (halfWidth(dd) + radius * out), dd);
        // Push the boulder further into the bank until the lane stays open.
        while (!(_lanePassable(pos, radius) && _noPocket(pos, radius)) && out < 1.2) {
          out += 0.1;
          pos = V2(centerX(dd) + side * (halfWidth(dd) + radius * out), dd);
        }
        if (_lanePassable(pos, radius) && _noPocket(pos, radius)) {
          rocks.add(Rock(pos, radius, r.range(0.04, 0.12) + radius * 0.5, emergent: true, seed: r.nextU32()));
        }
      }
      // Eddies: some behind big rocks, the rest free in the channel.
      for (var i = 0; i < spec.eddies; i++) {
        final dd = r.range(sec.startD + 0.4, sec.endD - 0.4);
        final hw = halfWidth(dd);
        final pos = V2(centerX(dd) + r.range(-0.6, 0.6) * hw, dd);
        final radius = r.range(0.12, 0.2) * (hw / 0.35).clamp(0.7, 1.3);
        eddies.add(Eddy(pos, radius, (r.chance(0.5) ? 1 : -1) * r.range(0.12, 0.22)));
      }
      // Firefly groups, placed off the lazy drift line so they must be steered to.
      for (var g = 0; g < spec.fireflyGroups; g++) {
        final dd = sec.startD + (g + 0.5) / spec.fireflyGroups * spec.length + r.range(-0.6, 0.6);
        final hw = halfWidth(dd);
        final side = r.chance(0.5) ? -1.0 : 1.0;
        final center = V2(centerX(dd) + side * r.range(0.25, 0.75) * hw, dd);
        final n = 3 + r.intBelow(4);
        for (var k = 0; k < n; k++) {
          final off = V2(r.range(-0.12, 0.12), r.range(-0.25, 0.25));
          var home = center + off;
          // Keep fireflies over water.
          if (clearance(home) < 0.05) home = V2(centerX(home.y) + (home.x - centerX(home.y)) * 0.6, home.y);
          fireflies.add(FireflySpawn(home, r.range(0.035, 0.16), r.range(0, math.pi * 2)));
        }
      }
    }
    // A few fireflies wait over the pool for the finale.
    final pr = rng.fork(99);
    for (var i = 0; i < 6; i++) {
      final a = pr.range(0, math.pi * 2);
      final rad = pr.range(0.2, 0.9) * poolRadius;
      fireflies.add(FireflySpawn(poolCenter + V2(math.cos(a), math.sin(a)) * rad, pr.range(0.1, 0.35), pr.range(0, 6)));
    }
    rocks.sort((a, b) => a.pos.y.compareTo(b.pos.y));
  }

  /// True if adding a rock at [pos] still leaves a lane wide enough for the lantern.
  bool _lanePassable(V2 pos, double radius) {
    const need = Course.lanternRadius * 2 + 0.12;
    final cx = centerX(pos.y);
    final hw = halfWidth(pos.y);
    // Collect blocked intervals across the channel near this d.
    final blocked = <List<double>>[
      [pos.x - radius, pos.x + radius]
    ];
    for (final r in rocks) {
      if (!r.emergent) continue;
      if ((r.pos.y - pos.y).abs() < r.radius + radius + need) {
        blocked.add([r.pos.x - r.radius, r.pos.x + r.radius]);
      }
    }
    blocked.sort((a, b) => a[0].compareTo(b[0]));
    var cursor = cx - hw;
    for (final b in blocked) {
      if (b[0] - cursor >= need) return true;
      cursor = math.max(cursor, b[1]);
    }
    return (cx + hw) - cursor >= need;
  }

  /// False if a rock at [pos] would leave a gap to another emergent rock that
  /// is open but narrower than the lantern: a pocket it could wedge into.
  bool _noPocket(V2 pos, double radius) {
    const need = Course.lanternRadius * 2 + 0.06;
    for (final r in rocks) {
      if (!r.emergent) continue;
      if ((r.pos.y - pos.y).abs() > r.radius + radius + need) continue;
      final gap = (r.pos - pos).length - r.radius - radius;
      if (gap > 0 && gap < need) return false;
    }
    return true;
  }

  /// Emergent rocks whose distance range overlaps [d0, d1].
  Iterable<Rock> rocksNear(double d0, double d1) sync* {
    // rocks are sorted by y; binary search the start.
    var lo = 0, hi = rocks.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (rocks[mid].pos.y < d0 - 0.4) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo; i < rocks.length && rocks[i].pos.y <= d1 + 0.4; i++) {
      yield rocks[i];
    }
  }
}
