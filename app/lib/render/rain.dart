import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// M5 rain: light dusk rain as velocity-stretched streaks.
///
/// At dusk a camera sees rain only where something lights it (refs 01, 03):
/// each drop's brightness comes from its distance to the lantern, plus a
/// faint share of the sky, so streaks show around the lantern and fade to
/// nothing in the dark. The emitter box follows the view along the stream;
/// particles live in its local space.
class RainEffect {
  RainEffect({this.rate = 900, double size = 1.0, double glow = 1.0})
      : _module = _LanternLitRain(glow) {
    final system = ParticleSystem(
      maxParticles: 640,
      // A slab of air over the water around the lantern: wide enough for the
      // cover and inner framings (about 1.7 m of stream in view).
      shape: BoxEmitterShape(
        halfExtents: vm.Vector3(1.1, 0.7, 1.4),
        // A light breeze leans the rain a little across and down the stream.
        direction: vm.Vector3(0.06, -1.0, -0.04),
      ),
      spawner: Spawner(rate: rate),
      lifetime: const UniformFloat(0.12, 0.3),
      startSpeed: const UniformFloat(4.2, 5.6),
      // Streak width (m). A drop is 1-2 mm, but motion blur and defocus at a
      // 5 m focus distance widen its streak to a few millimetres (refs 01,
      // 03); hair-thin streaks also vanish under TAA.
      startSize: UniformFloat(0.003 * size, 0.005 * size),
      modules: [_module],
      seed: 5,
      prewarm: 0.4,
    );
    final material = SpriteMaterial(colorTexture: _streakTexture())
      ..blendMode = SpriteBlendMode.additive
      ..softDepthFade = 0.02;
    emitter = ParticleEmitterComponent(system: system, material: material)
      ..facing = BillboardFacing.velocityStretched
      // Streak length per m/s of fall: about 1/60 s of motion blur.
      ..velocityStretch = 0.014;
    node = Node(name: 'rain')..addComponent(emitter);
  }

  final double rate;
  late final ParticleEmitterComponent emitter;
  late final Node node;
  final _LanternLitRain _module;

  /// Places the rain slab over [focus] (world x, z of the view centre), and
  /// tells the drops where the lantern is and how bright its light is.
  void update({required vm.Vector3 focus, required vm.Vector3 lanternPos, required vm.Vector3 lanternLight,
      required double range, required vm.Vector3 sky}) {
    // The slab's base sits just above the water: drops vanish as they reach it
    // (the impact rings are drawn by the water shader).
    node.localTransform = vm.Matrix4.translation(vm.Vector3(focus.x, 0.72, focus.z));
    _module.lanternLocal.setValues(lanternPos.x - focus.x, lanternPos.y - 0.72, lanternPos.z - focus.z);
    _module.light.setFrom(lanternLight);
    _module.range2 = range * range;
    _module.sky.setFrom(sky);
  }
}

/// Colours each drop by the light reaching it, with a fade in and out over
/// its short life so streaks do not pop.
/// A soft streak: Gaussian across (u), even along (v) with soft ends.
Texture2D _streakTexture() {
  const n = 32;
  final px = Uint8List(n * n * 4);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final dx = (x + 0.5) / n * 2 - 1, dy = (y + 0.5) / n * 2 - 1;
      final across = math.exp(-dx * dx * 5.0) * (1 - dx.abs()).clamp(0.0, 1.0);
      final along = 1.0 - ((dy.abs() - 0.55) / 0.45).clamp(0.0, 1.0);
      final b = (255 * across * along * along).round().clamp(0, 255);
      final o = (y * n + x) * 4;
      px[o] = b;
      px[o + 1] = b;
      px[o + 2] = b;
      px[o + 3] = b;
    }
  }
  return Texture2D.fromPixels(px, n, n, content: TextureContent.color);
}

class _LanternLitRain extends ParticleModule {
  _LanternLitRain(this.glow);
  final double glow;
  final vm.Vector3 lanternLocal = vm.Vector3.zero();
  final vm.Vector3 light = vm.Vector3.zero();
  final vm.Vector3 sky = vm.Vector3.zero();
  double range2 = 1.0;

  @override
  void update(ParticleStorage s, double dt) {
    for (var i = 0; i < s.aliveCount; i++) {
      // Below the water surface (local y -0.72): invisible (the system
      // retires it at the end of its life).
      if (s.posY[i] < -0.72) {
        s.colorR[i] = 0;
        s.colorG[i] = 0;
        s.colorB[i] = 0;
        s.colorA[i] = 0;
        continue;
      }
      final dx = s.posX[i] - lanternLocal.x;
      final dy = s.posY[i] - lanternLocal.y;
      final dz = s.posZ[i] - lanternLocal.z;
      final r2 = dx * dx + dy * dy + dz * dz;
      final w = math.max(0.0, 1.0 - r2 / range2);
      // Same falloff as the lit materials' lantern term, scaled for a drop:
      // water refracts and reflects the light toward the camera (forward
      // scatter), so a drop near the light glints well above a matte surface.
      final k = glow * 0.05 / (r2 + 0.004) * w * w;
      final life = s.lifetime[i] > 0 ? s.age[i] / s.lifetime[i] : 1.0;
      final env = math.min(1.0, math.min(life / 0.2, (1.0 - life) / 0.2)).clamp(0.0, 1.0);
      s.colorR[i] = (light.x * k + sky.x) * env;
      s.colorG[i] = (light.y * k + sky.y) * env;
      s.colorB[i] = (light.z * k + sky.z) * env;
      s.colorA[i] = env;
    }
  }
}
