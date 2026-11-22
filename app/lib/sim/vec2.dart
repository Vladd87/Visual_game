import 'dart:math' as math;

/// Immutable 2D vector in the sim plane.
///
/// Sim coordinates: `x` is across the stream (screen right), `y` is distance
/// downstream (screen down). World space maps `x → X`, `y → -Z`, water
/// surface at `Y = 0`.
class V2 {
  const V2(this.x, this.y);
  static const zero = V2(0, 0);

  final double x;
  final double y;

  V2 operator +(V2 o) => V2(x + o.x, y + o.y);
  V2 operator -(V2 o) => V2(x - o.x, y - o.y);
  V2 operator *(double s) => V2(x * s, y * s);
  V2 operator /(double s) => V2(x / s, y / s);
  V2 operator -() => V2(-x, -y);

  double dot(V2 o) => x * o.x + y * o.y;
  double cross(V2 o) => x * o.y - y * o.x;
  double get length => math.sqrt(x * x + y * y);
  double get length2 => x * x + y * y;
  V2 get perp => V2(-y, x);

  V2 normalized() {
    final l = length;
    return l > 1e-12 ? V2(x / l, y / l) : V2.zero;
  }

  V2 clampLength(double max) {
    final l = length;
    return l > max ? this * (max / l) : this;
  }

  static V2 lerp(V2 a, V2 b, double t) =>
      V2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);

  @override
  String toString() => 'V2(${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)})';
}

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

double smoothstep(double e0, double e1, double x) {
  final t = clamp01((x - e0) / (e1 - e0));
  return t * t * (3 - 2 * t);
}

double lerpD(double a, double b, double t) => a + (b - a) * t;
