import 'dart:math' as math;

import 'course.dart';
import 'vec2.dart';

/// Surface current of the stream at any point, metres per second.
///
/// Built from: a downstream base flow along the centreline tangent with a
/// cross-stream speed profile (fast middle, slow edges), potential-flow style
/// deflection around rocks with a slow wake behind them, Rankine-vortex eddies,
/// and a low-amplitude time-varying wobble so the water never feels on rails.
class FlowField {
  FlowField(this.course);

  final Course course;

  V2 velocityAt(V2 p, double t) {
    final d = p.y;
    final cx = course.centerX(d);
    final hw = course.halfWidth(d);
    final speed0 = course.flowSpeed(d);
    final lateral = ((p.x - cx) / hw).clamp(-1.0, 1.0);
    final profile = 1.0 - 0.6 * lateral * lateral;
    final dir = course.tangent(d);
    var v = dir * (speed0 * profile);

    // Gentle unsteady wobble (two incommensurate low frequencies).
    final w1 = math.sin(d * 2.1 + t * 0.37) * math.cos(p.x * 3.3 - t * 0.23);
    final w2 = math.sin(d * 4.7 - t * 0.61 + p.x * 1.9);
    v = v + V2(w1 * 0.018 + w2 * 0.008, w2 * 0.012) * (speed0 / 0.2);

    // Rocks: deflect around the upstream face, slow wake downstream.
    for (final r in course.rocksNear(d - 0.6, d + 0.6)) {
      final rel = p - r.pos;
      final dist2 = rel.length2;
      final reach = r.radius * 3.2;
      if (dist2 > reach * reach || dist2 < 1e-8) continue;
      final dist = math.sqrt(dist2);
      final n = rel / dist;
      final rr = r.radius * r.radius / dist2;
      final strength = r.emergent ? 1.0 : 0.35;
      // Upstream half: push sideways around the rock.
      final upstream = (-n.y).clamp(0.0, 1.0);
      // Near the stagnation point (lantern dead upstream) break the symmetry
      // with a per-rock preferred side, so nothing balances on a rock forever.
      final pref = r.seed.isOdd ? 1.0 : -1.0;
      final sideSign = n.x.abs() < 0.35 ? lerpD(pref, n.x.sign, n.x.abs() / 0.35) : n.x.sign;
      final side = V2(sideSign, 0);
      v = v + side * (speed0 * rr * 0.9 * upstream * strength);
      // Normal component toward the rock is damped (water parts around it).
      final into = v.dot(-n);
      if (into > 0 && r.emergent) {
        v = v + n * (into * math.min(1.0, rr * 1.4));
      }
      // Wake: slower water just downstream of the rock.
      if (rel.y > 0 && rel.x.abs() < r.radius * 1.3) {
        final k = math.exp(-rel.y / (r.radius * 3.0)) * strength;
        v = v * (1 - 0.55 * k);
      }
    }

    // Eddies (Rankine vortex: solid core, 1/r outside), faded beyond 2.5 R.
    for (final e in course.eddies) {
      final rel = p - e.pos;
      if ((rel.y).abs() > e.radius * 3 || (rel.x).abs() > e.radius * 3) continue;
      final r = rel.length;
      if (r < 1e-6) continue;
      final tang = rel.perp / r; // counter-clockwise tangent
      double vt;
      if (r < e.radius) {
        vt = e.strength * r / e.radius;
      } else {
        vt = e.strength * e.radius / r;
      }
      vt *= 1 - smoothstep(e.radius * 1.8, e.radius * 3.0, r);
      v = v + tang * vt;
    }

    // Pool: slow residual swirl so the finale drifts instead of freezing.
    if (course.inPool(p)) {
      final rel = p - course.poolCenter;
      final r = rel.length;
      if (r > 1e-6) v = v + rel.perp / r * (0.025 * (r / course.poolRadius));
    }

    // Banks: kill the component that runs into the bank.
    final c = course.clearance(p);
    if (c < 0.08) {
      final nb = course.bankNormal(p);
      final into = v.dot(nb);
      if (into > 0) v = v - nb * (into * (1 - clamp01(c / 0.08)));
    }
    return v;
  }

  /// Scalar vorticity (curl) of the flow, used to spin the lantern.
  double curl(V2 p, double t) {
    const e = 0.02;
    final dvy = velocityAt(V2(p.x + e, p.y), t).y - velocityAt(V2(p.x - e, p.y), t).y;
    final dvx = velocityAt(V2(p.x, p.y + e), t).x - velocityAt(V2(p.x, p.y - e), t).x;
    return (dvy - dvx) / (2 * e);
  }
}
