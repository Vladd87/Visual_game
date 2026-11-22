import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../sim/vec2.dart';

/// Which screen layout the game is being shown on.
enum ScreenProfile { cover, inner, flex, wide }

/// Framing for one screen profile (PLAN.md §1 "Lens").
class Framing {
  const Framing({
    required this.vfovDeg,
    required this.distance,
    required this.anchorX,
    required this.anchorY,
    required this.renderScale,
  });

  final double vfovDeg; // vertical field of view
  final double distance; // camera to lantern, metres
  final double anchorX; // where the lantern sits on screen, 0..1 from left
  final double anchorY; // 0..1 from top
  final double renderScale; // default internal resolution for this screen

  Framing lerp(Framing o, double t) => Framing(
        vfovDeg: lerpD(vfovDeg, o.vfovDeg, t),
        distance: lerpD(distance, o.distance, t),
        anchorX: lerpD(anchorX, o.anchorX, t),
        anchorY: lerpD(anchorY, o.anchorY, t),
        renderScale: o.renderScale,
      );
}

/// Inputs that decide the framing.
class ViewportInfo {
  const ViewportInfo({required this.size, this.hinge, this.halfOpened = false});

  /// Logical size of the game viewport.
  final Size size;

  /// Hinge/fold rectangle in viewport coordinates, if any.
  final Rect? hinge;

  /// Device is half-folded (Flex mode).
  final bool halfOpened;

  double get aspect => size.width / math.max(1, size.height);
}

/// Fixed tilted overhead camera that keeps the lantern at an anchor point.
///
/// The camera never rotates (PLAN.md: fixed 55° pitch, long lens). It follows
/// the lantern with a short lag and moves between screen profiles with a
/// critically damped spring, so a fold/unfold reframes smoothly.
class CameraRig {
  static const double pitchDeg = 55;

  ScreenProfile profile = ScreenProfile.cover;
  Framing? _current;
  Framing _target = profileFraming(ScreenProfile.cover, null);
  Framing _from = profileFraming(ScreenProfile.cover, null);
  double _blend = 1; // 0 → 1 while moving from _from to _target
  V2? _follow;

  /// Picks the profile and framing for [info].
  static ScreenProfile classify(ViewportInfo info) {
    if (info.halfOpened) return ScreenProfile.flex;
    final a = info.aspect;
    if (a < 0.72) return ScreenProfile.cover;
    if (a <= 1.45) return ScreenProfile.inner;
    return ScreenProfile.wide;
  }

  static Framing profileFraming(ScreenProfile p, ViewportInfo? info) {
    switch (p) {
      case ScreenProfile.cover:
        return const Framing(vfovDeg: 28, distance: 5.0, anchorX: 0.5, anchorY: 0.36, renderScale: 0.80);
      case ScreenProfile.inner:
        // Diorama: wider and further back; lantern beside the crease.
        return Framing(vfovDeg: 24, distance: 5.0, anchorX: _creaseAnchorX(info), anchorY: 0.40, renderScale: 0.70);
      case ScreenProfile.flex:
        return const Framing(vfovDeg: 17, distance: 5.2, anchorX: 0.5, anchorY: 0.46, renderScale: 0.75);
      case ScreenProfile.wide:
        return const Framing(vfovDeg: 20, distance: 5.0, anchorX: 0.42, anchorY: 0.40, renderScale: 0.75);
    }
  }

  /// Puts the lantern in the larger region beside a vertical hinge (or at
  /// 32 % of the width by default on the inner screen, which is where the
  /// crease sits when the fold feature is not reported).
  static double _creaseAnchorX(ViewportInfo? info) {
    final hinge = info?.hinge;
    final w = info?.size.width ?? 1;
    if (hinge == null || hinge.height < hinge.width) return 0.32;
    final leftRoom = hinge.left;
    final rightRoom = w - hinge.right;
    if (leftRoom >= rightRoom) {
      return (leftRoom * 0.62) / w;
    }
    return (hinge.right + rightRoom * 0.38) / w;
  }

  /// Updates the target framing for a new viewport (fold/unfold/resize).
  void setViewport(ViewportInfo info) {
    final p = classify(info);
    final f = profileFraming(p, info);
    profile = p;
    if (_current == null) {
      _current = f;
      _target = f;
      _from = f;
      _blend = 1;
      return;
    }
    if (_sameFraming(f, _target)) return;
    _from = _current!;
    _target = f;
    _blend = 0;
  }

  static bool _sameFraming(Framing a, Framing b) =>
      (a.vfovDeg - b.vfovDeg).abs() < 1e-3 &&
      (a.distance - b.distance).abs() < 1e-3 &&
      (a.anchorX - b.anchorX).abs() < 1e-3 &&
      (a.anchorY - b.anchorY).abs() < 1e-3;

  Framing get framing => _current ?? _target;

  /// Snap the follow point (new run, capture).
  void snapTo(V2 lantern) {
    _follow = lantern;
    _current = _target;
    _blend = 1;
  }

  /// Advances smoothing and returns the camera for this frame.
  Camera update(double dt, V2 lantern, double aspect) {
    // Reframe: smootherstep over ~0.55 s.
    if (_blend < 1) {
      _blend = math.min(1, _blend + dt / 0.55);
      final t = _blend * _blend * _blend * (_blend * (_blend * 6 - 15) + 10);
      _current = _from.lerp(_target, t);
    } else {
      _current = _target;
    }
    // Follow with a short lag (half-life ~0.12 s), more slack across the stream.
    _follow ??= lantern;
    final kx = 1 - math.exp(-dt * 4.0), ky = 1 - math.exp(-dt * 7.0);
    _follow = V2(_follow!.x + (lantern.x - _follow!.x) * kx, _follow!.y + (lantern.y - _follow!.y) * ky);
    return cameraFor(_follow!, _current!, aspect);
  }

  /// Camera that puts world point [focus] (sim coords, on the water) at the
  /// framing's anchor for a viewport of [aspect].
  static PerspectiveCamera cameraFor(V2 focus, Framing f, double aspect) {
    final pitch = pitchDeg * math.pi / 180;
    final fwd = vm.Vector3(0, -math.sin(pitch), math.cos(pitch)); // looks upstream (+Z) and down
    final up = vm.Vector3(0, math.cos(pitch), math.sin(pitch));
    final right = vm.Vector3(1, 0, 0);
    final tanV = math.tan(f.vfovDeg * math.pi / 360);
    final tanH = tanV * aspect;
    final nx = f.anchorX * 2 - 1;
    final ny = 1 - f.anchorY * 2;
    final dir = fwd + right * (nx * tanH) + up * (ny * tanV);
    final l = vm.Vector3(focus.x, 0.03, -focus.y);
    final eye = l - dir * f.distance;
    return PerspectiveCamera(
      fovRadiansY: f.vfovDeg * math.pi / 180,
      position: eye,
      target: eye + fwd,
      fovNear: 0.05,
      fovFar: 60,
    );
  }

  /// World-space direction on the water for a screen-space drag (dx right,
  /// dy down): the camera never rotates, so screen right is sim +x and screen
  /// down is downstream (+y).
  static V2 screenToSim(Offset drag) => V2(drag.dx, drag.dy);
}
