import 'package:flutter_test/flutter_test.dart';
import 'package:lantern/sim/autopilot.dart';
import 'package:lantern/sim/course.dart';
import 'package:lantern/sim/entities.dart';
import 'package:lantern/sim/rng.dart';
import 'package:lantern/sim/vec2.dart';
import 'package:lantern/sim/world.dart';

void main() {
  test('rng is deterministic and well spread', () {
    final a = Rng(42), b = Rng(42);
    final xs = [for (var i = 0; i < 1000; i++) a.next()];
    final ys = [for (var i = 0; i < 1000; i++) b.next()];
    expect(xs, ys);
    final mean = xs.reduce((p, q) => p + q) / xs.length;
    expect(mean, closeTo(0.5, 0.05));
    expect(xs.every((x) => x >= 0 && x < 1), isTrue);
    expect(Rng.imul(0xFFFFFFFF, 0xFFFFFFFF), 1);
    expect(Rng.imul(123456789, 987654321), (123456789 * 987654321) % 4294967296);
  });

  test('course is valid: stream is navigable and pool exists', () {
    for (final seed in [1, 7, 2026, 99999]) {
      final c = Course.generate(seed);
      expect(c.length, greaterThan(35));
      expect(c.fireflies.length, greaterThan(30));
      // Every 5 cm along the channel there is a lane wide enough for the lantern.
      for (var d = 0.5; d < c.length; d += 0.05) {
        final cx = c.centerX(d);
        final hw = c.halfWidth(d);
        expect(hw, greaterThan(0.2));
        var free = 0.0, best = 0.0;
        for (var x = cx - hw; x <= cx + hw; x += 0.005) {
          final blocked = c.rocks.any((r) => r.emergent && (V2(x, d) - r.pos).length < r.radius + Course.lanternRadius);
          free = blocked ? 0 : free + 0.005;
          if (free > best) best = free;
        }
        expect(best, greaterThan(0.09), reason: 'seed $seed blocked at d=$d');
      }
      expect(c.clearance(c.poolCenter), closeTo(c.poolRadius, 1e-6));
    }
  });

  test('same seed and inputs give the same run', () {
    World run() {
      final w = World(2026);
      final ap = Autopilot();
      for (var i = 0; i < 120 * 40; i++) {
        w.step(ap.input(w));
      }
      return w;
    }

    final a = run(), b = run();
    expect(a.lantern.pos.x, b.lantern.pos.x);
    expect(a.lantern.pos.y, b.lantern.pos.y);
    expect(a.flame, b.flame);
    expect(a.collected, b.collected);
    expect(a.leaves.length, b.leaves.length);
  });

  test('lantern never ends up inside a rock or a bank', () {
    final w = World(7);
    final ap = Autopilot(skill: 0.4);
    for (var i = 0; i < 120 * 120 && w.phase == RunPhase.running; i++) {
      w.step(ap.input(w));
      final p = w.lantern.pos;
      expect(w.course.clearance(p), greaterThan(LanternBody.radius - 0.01));
      for (final r in w.course.rocksNear(p.y - 0.4, p.y + 0.4)) {
        if (!r.emergent) continue;
        expect((p - r.pos).length, greaterThan(r.radius + LanternBody.radius - 0.01));
      }
    }
  });

  test('flame decays to zero in about 4.5 minutes without help', () {
    final w = World(3);
    // Freeze the lantern at the start: only decay acts on the flame.
    var t = 0.0;
    while (w.phase == RunPhase.running && t < 400) {
      w.lantern.pos = V2(w.course.centerX(0.6), 0.6);
      w.lantern.vel = V2.zero;
      w.step(V2.zero);
      t += Tuning.fixedDt;
    }
    expect(w.phase, RunPhase.lost);
    expect(t, inInclusiveRange(200, 300)); // 270 s nominal, rain shortens it a little
  });

  test('collecting a firefly raises the flame and emits an event', () {
    final w = World(11);
    w.flame = 0.5;
    final f = w.fireflies.first;
    w.lantern.pos = f.positionAt(w.time + 1 / 120);
    w.step(V2.zero);
    // At least one: since M11 the bigger lantern can reach a second firefly
    // of the same group in the same step.
    expect(w.collected, greaterThanOrEqualTo(1));
    expect(w.flame, greaterThan(0.55));
    expect(w.drainEvents().whereType<FireflyEvent>(), isNotEmpty);
  });

  test('an attentive run reaches the pool in 3 to 5 minutes', () {
    for (final seed in [2026, 31337]) {
      final w = World(seed);
      final ap = Autopilot();
      while (w.phase == RunPhase.running && w.time < 420) {
        w.step(ap.input(w));
      }
      expect(w.phase, RunPhase.won, reason: 'seed $seed flame=${w.flame} d=${w.lantern.pos.y} t=${w.time}');
      expect(w.time, inInclusiveRange(150, 330), reason: 'seed $seed took ${w.time}s');
      expect(w.collected, greaterThan(8));
    }
  });
}
