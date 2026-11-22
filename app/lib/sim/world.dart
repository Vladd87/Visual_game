import 'dart:math' as math;

import 'course.dart';
import 'entities.dart';
import 'flow_field.dart';
import 'rng.dart';
import 'vec2.dart';

enum RunPhase { running, won, lost }

/// Something the presentation layer should react to (haptics, sound, flashes).
sealed class SimEvent {
  const SimEvent();
}

class CollisionEvent extends SimEvent {
  const CollisionEvent(this.strength, this.at);
  final double strength; // 0..1
  final V2 at;
}

class FireflyEvent extends SimEvent {
  const FireflyEvent(this.index);
  final int index;
}

class LeafSmotherEvent extends SimEvent {
  const LeafSmotherEvent();
}

class RunEndEvent extends SimEvent {
  const RunEndEvent(this.phase);
  final RunPhase phase;
}

/// Tunable gameplay constants (PLAN.md §2).
class Tuning {
  static const double fixedDt = 1 / 120;
  static const double waterDrag = 2.4; // 1/s, how hard the current carries the lantern
  static const double nudgeAccel = 0.55; // m/s^2 at full input
  static const double maxSpeed = 0.6;
  static const double flameDecayPerSec = 1 / 270; // goes out at ~4.5 min with no fireflies
  static const double rainDecayBoost = 0.45; // up to +45% decay in heavy rain
  static const double fireflyGain = 0.06;
  static const double pickupRadius = 0.075;
  static const double restitution = 0.25;
  static const double leafSmotherLoss = 0.03;
}

/// The whole deterministic simulation. Advance with [step] at [Tuning.fixedDt].
class World {
  World(this.seed)
      : course = Course.generate(seed),
        _rng = Rng(seed ^ 0x5EED) {
    flow = FlowField(course);
    lantern = LanternBody(V2(course.centerX(0.6), 0.6));
    previous = lantern.copy();
    fireflies = [for (final s in course.fireflies) Firefly(s)];
  }

  final int seed;
  final Course course;
  late final FlowField flow;
  final Rng _rng;
  late LanternBody lantern;
  late LanternBody previous; // state at the start of the last step, for render interpolation
  late final List<Firefly> fireflies;
  final List<Leaf> leaves = [];
  final List<SimEvent> events = [];

  double time = 0;
  double flame = 1.0;
  int collected = 0;
  RunPhase phase = RunPhase.running;
  double endedAt = 0;
  double _leafTimer = 0;
  double _lastHitTime = -10;

  Section get section => course.sectionAt(lantern.pos.y);
  double get rain => course.param(lantern.pos.y, (s) => s.rain);
  double get fog => course.param(lantern.pos.y, (s) => s.fog);

  /// Progress along the stream, 0..1 (1 = reached the pool).
  double get progress => (lantern.pos.y / course.length).clamp(0.0, 1.0);

  /// One fixed step. [input] is the player's nudge in sim axes, length <= 1.
  void step(V2 input) {
    const dt = Tuning.fixedDt;
    previous = lantern.copy();
    time += dt;
    final l = lantern;

    // --- forces ---
    final u = flow.velocityAt(l.pos, time);
    final drag = Tuning.waterDrag * (l.leafStuck > 0 ? 0.75 : 1.0);
    final control = phase == RunPhase.running ? input.clampLength(1) : V2.zero;
    final nudge = control * (Tuning.nudgeAccel * (l.leafStuck > 0 ? 0.6 : 1.0));
    var a = (u - l.vel) * drag + nudge;
    // A pinned lantern gets freed by a slosh of water toward open water,
    // the way real flotsam eventually works loose (no permanent traps).
    if (phase == RunPhase.running && !course.inPool(l.pos)) {
      if (l.vel.length < 0.02) {
        l.stillTime += dt;
      } else {
        l.stillTime = math.max(0, l.stillTime - dt * 2);
      }
      if (l.stillTime > 1.2 && l.slosh <= 0) {
        // Slosh sideways away from whatever is pinning the lantern.
        var side = 0.0;
        for (final r in course.rocksNear(l.pos.y - 0.1, l.pos.y + 0.4)) {
          if (!r.emergent || (r.pos - l.pos).length > r.radius + 0.12) continue;
          side += (l.pos.x - r.pos.x).abs() < 0.01 ? (r.seed.isOdd ? 1 : -1) : (l.pos.x - r.pos.x).sign;
        }
        if (course.clearance(l.pos) < 0.08) side -= course.bankNormal(l.pos).x.sign;
        if (side == 0) side = _rng.chance(0.5) ? 1 : -1;
        l.sloshDir = V2(side.sign, -0.25).normalized();
        l.slosh = 0.7;
        l.stillTime = 0;
      }
    }
    if (l.slosh > 0) {
      l.slosh -= dt;
      a = a + l.sloshDir * 0.9;
    }
    if (phase != RunPhase.running) a = a - l.vel * 0.8; // settle in the pool / after going out
    l.vel = (l.vel + a * dt).clampLength(Tuning.maxSpeed);
    l.pos = l.pos + l.vel * dt;

    // Spin follows the local vorticity, plus drag toward rest.
    final targetSpin = flow.curl(l.pos, time) * 0.5;
    l.angVel += (targetSpin - l.angVel) * 2.0 * dt;
    l.angle += l.angVel * dt;
    if (l.leafStuck > 0) l.leafStuck = math.max(0, l.leafStuck - dt);

    _collide(l);
    _updateFireflies(l);
    _updateLeaves(l, dt);
    _updateFlame(dt);
  }

  void _collide(LanternBody l) {
    const r = LanternBody.radius;
    // Rocks.
    for (final rock in course.rocksNear(l.pos.y - 0.4, l.pos.y + 0.4)) {
      if (!rock.emergent) continue;
      final rel = l.pos - rock.pos;
      final minDist = rock.radius + r;
      final d2 = rel.length2;
      if (d2 >= minDist * minDist) continue;
      final dist = math.sqrt(d2);
      final n = dist > 1e-6 ? rel / dist : const V2(1, 0);
      l.pos = rock.pos + n * minDist;
      _impact(l, n, l.pos - n * r);
    }
    // Banks (channel walls and pool rim).
    final c = course.clearance(l.pos);
    if (c < r) {
      final nb = course.bankNormal(l.pos); // points into the bank
      l.pos = l.pos - nb * (r - c);
      _impact(l, -nb, l.pos + nb * r);
    }
  }

  void _impact(LanternBody l, V2 n, V2 at) {
    final vn = l.vel.dot(n);
    if (vn >= 0) return;
    final impact = -vn;
    // Reflect the normal part, keep some tangential slide.
    final vt = l.vel - n * vn;
    l.vel = vt * 0.85 - n * (vn * Tuning.restitution);
    l.angVel += (vt.cross(n)) * 18;
    if (impact > 0.03 && time - _lastHitTime > 0.6 && phase == RunPhase.running) {
      _lastHitTime = time;
      final strength = clamp01((impact - 0.03) / 0.22);
      flame -= 0.03 + 0.12 * strength;
      events.add(CollisionEvent(strength, at));
    }
  }

  void _updateFireflies(LanternBody l) {
    if (phase != RunPhase.running) return;
    for (var i = 0; i < fireflies.length; i++) {
      final f = fireflies[i];
      if (f.collected) continue;
      final p = f.positionAt(time);
      if ((p - l.pos).length2 < Tuning.pickupRadius * Tuning.pickupRadius) {
        f.collected = true;
        f.collectedAt = time;
        collected++;
        flame = math.min(1.0, flame + Tuning.fireflyGain);
        events.add(FireflyEvent(i));
      }
    }
  }

  void _updateLeaves(LanternBody l, double dt) {
    // Spawn while the lantern is in a leafy section.
    final rate = course.param(l.pos.y, (s) => s.leafRate);
    if (phase == RunPhase.running && rate > 0) {
      _leafTimer += dt * rate;
      while (_leafTimer >= 1) {
        _leafTimer -= 1;
        final d = l.pos.y + _rng.range(0.15, 1.3);
        final hw = course.halfWidth(d);
        leaves.add(Leaf(
          pos: V2(course.centerX(d) + _rng.range(-1.0, 1.0) * hw, d),
          height: _rng.range(0.45, 0.7),
          fallSpeed: _rng.range(0.25, 0.4),
          seed: _rng.nextU32(),
        ));
      }
    }
    for (final leaf in leaves) {
      leaf.age += dt;
      switch (leaf.state) {
        case LeafState.falling:
          leaf.height -= leaf.fallSpeed * dt;
          final sway = math.sin(leaf.age * 3.1 + leaf.seed % 7) * 0.12;
          leaf.pos = leaf.pos + V2(sway * dt, 0.02 * dt);
          leaf.angle += dt * (1.5 + (leaf.seed % 5) * 0.3);
          if (leaf.height <= 0) {
            leaf.height = 0;
            final onLantern = (leaf.pos - l.pos).length < LanternBody.radius + 0.02;
            if (onLantern && phase == RunPhase.running) {
              leaf.state = LeafState.stuck;
              leaf.stuckTime = 2.5;
              l.leafStuck = 2.5;
              flame -= Tuning.leafSmotherLoss;
              events.add(const LeafSmotherEvent());
            } else {
              leaf.state = course.clearance(leaf.pos) > 0 ? LeafState.floating : LeafState.gone;
            }
          }
        case LeafState.floating:
          final u = flow.velocityAt(leaf.pos, time);
          leaf.vel = leaf.vel + (u - leaf.vel) * (1.8 * dt);
          leaf.pos = leaf.pos + leaf.vel * dt;
          leaf.angle += flow.curl(leaf.pos, time) * 0.5 * dt;
          // Soft push between a floating leaf and the lantern.
          final rel = l.pos - leaf.pos;
          final dist = rel.length;
          if (dist < LanternBody.radius + 0.025 && dist > 1e-6) {
            l.vel = l.vel + rel / dist * (0.08 * dt);
          }
          if (course.clearance(leaf.pos) < -0.02) leaf.state = LeafState.gone;
        case LeafState.stuck:
          leaf.pos = l.pos;
          leaf.stuckTime -= dt;
          if (leaf.stuckTime <= 0) {
            leaf.state = LeafState.floating;
            leaf.pos = l.pos + V2(0.06, -0.02);
            leaf.vel = l.vel;
          }
        case LeafState.gone:
          break;
      }
    }
    leaves.removeWhere((leaf) =>
        leaf.state == LeafState.gone || leaf.pos.y < l.pos.y - 3.0 || leaf.age > 60);
    if (leaves.length > 48) leaves.removeRange(0, leaves.length - 48);
  }

  void _updateFlame(double dt) {
    if (phase != RunPhase.running) return;
    final decay = Tuning.flameDecayPerSec * (1 + Tuning.rainDecayBoost * rain);
    flame -= decay * dt;
    if (flame <= 0) {
      flame = 0;
      phase = RunPhase.lost;
      endedAt = time;
      events.add(const RunEndEvent(RunPhase.lost));
    } else if ((lantern.pos - course.poolCenter).length < course.poolRadius * 0.8 &&
        lantern.pos.y > course.length) {
      phase = RunPhase.won;
      endedAt = time;
      events.add(const RunEndEvent(RunPhase.won));
    }
  }

  /// Lantern pose interpolated between the last two steps (alpha in [0, 1]).
  ({V2 pos, double angle}) lanternPose(double alpha) => (
        pos: V2.lerp(previous.pos, lantern.pos, alpha),
        angle: previous.angle + (lantern.angle - previous.angle) * alpha,
      );

  List<SimEvent> drainEvents() {
    final out = List<SimEvent>.of(events);
    events.clear();
    return out;
  }
}

/// Runs a [World] in real time with a fixed-step accumulator.
class WorldClock {
  WorldClock(this.world);

  final World world;
  double _acc = 0;

  /// Render interpolation factor after the last [advance].
  double alpha = 0;

  /// Advances by [realDt] seconds (clamped to avoid a spiral after a hitch).
  void advance(double realDt, V2 Function() input) {
    _acc += realDt.clamp(0.0, 0.1);
    var steps = 0;
    while (_acc >= Tuning.fixedDt && steps < 12) {
      world.step(input());
      _acc -= Tuning.fixedDt;
      steps++;
    }
    if (steps == 12) _acc = 0;
    alpha = _acc / Tuning.fixedDt;
  }
}
