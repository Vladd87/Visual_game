import 'dart:math' as math;

import 'course.dart';
import 'vec2.dart';

/// The floating paper lantern, simulated as a 2D body on the water plane.
class LanternBody {
  LanternBody(this.pos);

  V2 pos;
  V2 vel = V2.zero;
  double angle = 0; // yaw, radians
  double angVel = 0;

  /// Seconds remaining with a leaf stuck on the lantern (slows and dims it).
  double leafStuck = 0;

  /// How long the lantern has been (nearly) motionless while in play.
  double stillTime = 0;

  /// Remaining seconds of a "slosh" that frees a pinned lantern.
  double slosh = 0;
  V2 sloshDir = V2.zero;

  static const double radius = Course.lanternRadius;

  LanternBody copy() => LanternBody(pos)
    ..vel = vel
    ..angle = angle
    ..angVel = angVel
    ..leafStuck = leafStuck
    ..stillTime = stillTime
    ..slosh = slosh
    ..sloshDir = sloshDir;
}

/// One firefly hovering over the water until the lantern gathers it.
class Firefly {
  Firefly(this.spawn);

  final FireflySpawn spawn;
  bool collected = false;
  double collectedAt = 0;

  /// Current hover position (wanders around its home).
  V2 positionAt(double t) {
    final ph = spawn.phase;
    return spawn.home +
        V2(math.sin(t * 0.7 + ph) * 0.035 + math.sin(t * 1.9 + ph * 2) * 0.012,
            math.cos(t * 0.53 + ph * 1.3) * 0.03);
  }

  double heightAt(double t) => spawn.height + math.sin(t * 1.1 + spawn.phase * 3) * 0.015;

  /// Blink envelope 0..1 (fireflies flash, they do not glow steadily).
  double glowAt(double t) {
    final cycle = (t * 0.45 + spawn.phase / (2 * math.pi)) % 1.0;
    final flash = cycle < 0.22 ? math.sin(cycle / 0.22 * math.pi) : 0.0;
    return 0.25 + 0.75 * flash;
  }
}

enum LeafState { falling, floating, stuck, gone }

/// A falling leaf: flutters down, then drifts with the current.
class Leaf {
  Leaf({required this.pos, required this.height, required this.fallSpeed, required this.seed});

  V2 pos;
  double height;
  final double fallSpeed;
  final int seed;
  V2 vel = V2.zero;
  double spin = 0;
  double angle = 0;
  LeafState state = LeafState.falling;
  double age = 0;
  double stuckTime = 0;
}
