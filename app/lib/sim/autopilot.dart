import 'dart:math' as math;

import 'course.dart';
import 'vec2.dart';
import 'world.dart';

/// A modest scripted player: steers toward the next fireflies ahead and away
/// from rocks and banks. Used by tests (a run must be completable) and by the
/// capture harness (deterministic shots of a run in progress).
class Autopilot {
  Autopilot({this.skill = 1.0});

  /// 0 = passive drift, 1 = attentive player.
  final double skill;

  V2 input(World w) {
    if (skill <= 0) return V2.zero;
    final l = w.lantern;
    var steer = V2.zero;

    // Seek: nearest uncollected firefly ahead within reach.
    double best = 1e9;
    V2? target;
    for (final f in w.fireflies) {
      if (f.collected) continue;
      final p = f.positionAt(w.time);
      final ahead = p.y - l.pos.y;
      if (ahead < -0.05 || ahead > 1.4) continue;
      final cost = (p - l.pos).length + ahead.abs() * 0.3;
      if (cost < best) {
        best = cost;
        target = p;
      }
    }
    if (target != null) {
      final to = target - l.pos;
      steer = steer + V2(to.x * 4.0, math.max(0.0, to.y) * 0.5).clampLength(1);
    } else {
      // Drift back toward the middle of the channel.
      final cx = w.course.centerX(l.pos.y + 0.3);
      steer = steer + V2((cx - l.pos.x) * 3.0, 0).clampLength(0.6);
    }

    // Avoid: rocks ahead in the path, and the banks.
    for (final r in w.course.rocksNear(l.pos.y - 0.1, l.pos.y + 0.6)) {
      if (!r.emergent) continue;
      final rel = l.pos - r.pos;
      final ahead = r.pos.y - l.pos.y;
      if (ahead < -0.05) continue;
      final clear = rel.length - r.radius - Course.lanternRadius;
      if (clear < 0.18) {
        final cx = w.course.centerX(r.pos.y);
        final away = rel.x.abs() < 0.02 ? ((cx - r.pos.x).abs() > 0.02 ? (cx - r.pos.x).sign : 1.0) : rel.x.sign;
        steer = steer + V2(away * (0.18 - clear) * 9.0, 0);
      }
    }
    final c = w.course.clearance(l.pos);
    if (c < 0.12) steer = steer - w.course.bankNormal(l.pos) * ((0.12 - c) * 8.0);

    // Always lean slightly downstream so the pilot never parks in an eddy.
    steer = V2(steer.x, math.max(steer.y, 0.15));
    return (steer * skill).clampLength(1);
  }
}
