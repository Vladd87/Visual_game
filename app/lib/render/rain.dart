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
  RainEffect({this.rate = 3000, double size = 1.0, double glow = 1.0, double stretch = 0.024})
      : _module = _LanternLitRain(glow) {
    final system = ParticleSystem(
      maxParticles: 1024,
      // Air over the water around the lantern. Only drops the lantern lights
      // show at dusk, so the drops are concentrated where its light reaches
      // (about 230 per cubic metre, light rain) instead of spread thinly over
      // the whole view.
      shape: BoxEmitterShape(
        halfExtents: vm.Vector3(0.75, 0.55, 0.75),
        // A light breeze leans the rain a little across and down the stream.
        direction: vm.Vector3(0.06, -1.0, -0.04),
      ),
      spawner: Spawner(rate: rate),
      lifetime: const UniformFloat(0.12, 0.3),
      // Fall speed grows with drop size (small drops about 3 m/s, large ones
      // 6 m/s), so streak lengths differ.
      startSpeed: const UniformFloat(3.0, 6.0),
      // Streak width (m). A drop is 1-2 mm, but motion blur and defocus at a
      // 5 m focus distance widen its streak to a few millimetres (refs 01,
      // 03); hair-thin streaks also vanish under TAA.
      startSize: UniformFloat(0.002 * size, 0.006 * size),
      modules: [_module],
      seed: 5,
      prewarm: 0.4,
    );
    final material = SpriteMaterial(colorTexture: _streakTexture())
      ..blendMode = SpriteBlendMode.additive
      ..softDepthFade = 0.02;
    emitter = ParticleEmitterComponent(system: system, material: material)
      // The game steps the rain on its own clock (see [update]): a capture
      // freezes it like a photo, and play follows real frame time.
      ..paused = true
      ..facing = BillboardFacing.velocityStretched
      // Streak length per m/s of fall: about 1/40 s of motion blur, a dusk
      // exposure (refs 01, 03).
      ..velocityStretch = stretch;
    node = Node(name: 'rain')..addComponent(emitter);
  }

  final double rate;
  late final ParticleEmitterComponent emitter;
  late final Node node;
  final _LanternLitRain _module;

  /// Places the rain slab over [focus] (world x, z of the view centre), and
  /// tells the drops where the lantern is and how bright its light is.
  void update({required double dt, required vm.Vector3 focus, required vm.Vector3 lanternPos, required vm.Vector3 lanternLight,
      required double range, required vm.Vector3 sky}) {
    // The slab's base sits just above the water: drops vanish as they reach it
    // (the impact rings are drawn by the water shader).
    node.localTransform = vm.Matrix4.translation(vm.Vector3(focus.x, _baseY, focus.z));
    _module.lanternLocal.setValues(lanternPos.x - focus.x, lanternPos.y - _baseY, lanternPos.z - focus.z);
    _module.light.setFrom(lanternLight);
    // Drops show only inside the lantern's light (round 18: glints out to
    // 1 m spread streaks a third of the frame away).
    _module.range2 = range * range;
    _module.sky.setFrom(sky);
    if (dt > 0) emitter.system.step(dt);
    // Recolour every frame, also when the rain is frozen (capture).
    _module.update(emitter.system.storage, 0);
    if (_debug && (_calls++ % 30) == 0) {
      final st = emitter.system.storage;
      var i = 0;
      for (var j = 0; j < st.aliveCount; j++) {
        if (st.colorR[j] > st.colorR[i]) i = j;
      }
      var lit = 0;
      for (var j = 0; j < st.aliveCount; j++) {
        if (st.colorR[j] > 0.05) lit++;
      }
      final hist = List<int>.filled(5, 0);
      var above = 0;
      for (var j = 0; j < st.aliveCount; j++) {
        final c = st.colorR[j];
        if (st.posY[j] > -_baseY) above++;
        if (c > 0.05) hist[0]++;
        if (c > 0.2) hist[1]++;
        if (c > 0.5) hist[2]++;
        if (c > 1.0) hist[3]++;
        if (c > 3.0) hist[4]++;
      }
      // ignore: avoid_print
      print('LANTERN_RAIN lit=$lit hist(>.05,.2,.5,1,3)=$hist aboveWater=$above light=${_module.light} r2=${_module.range2}');
      // ignore: avoid_print
      print('LANTERN_RAIN alive=${st.aliveCount} visible=${node.visible} '
          '${st.aliveCount > 0 ? 'p=(${st.posX[i].toStringAsFixed(2)},${st.posY[i].toStringAsFixed(2)},${st.posZ[i].toStringAsFixed(2)}) '
              'c=(${st.colorR[i].toStringAsFixed(3)},${st.colorA[i].toStringAsFixed(2)}) size=${st.size[i].toStringAsFixed(4)} '
              'v=${st.velY[i].toStringAsFixed(2)}' : ''} lantern=${_module.lanternLocal}');
    }
  }

  /// Height of the slab's centre: its base sits just above the water.
  static const double _baseY = 0.57;

  static final bool _debug = Uri.base.queryParameters['raindebug'] != null;
  static final bool _force = Uri.base.queryParameters['raindebug'] == '2';
  static final bool _forceNear = Uri.base.queryParameters['raindebug'] == '3';
  int _calls = 0;
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
      // Below the water surface: invisible (the system retires it at the end
      // of its life).
      if (s.posY[i] < -RainEffect._baseY) {
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
      final k = glow * 0.12 / (r2 + 0.004) * w * w;
      final life = s.lifetime[i] > 0 ? s.age[i] / s.lifetime[i] : 1.0;
      final env = math.min(1.0, math.min(life / 0.2, (1.0 - life) / 0.2)).clamp(0.0, 1.0);
      if (RainEffect._forceNear && r2 < 0.36) {
        s.colorR[i] = 2;
        s.colorG[i] = 2;
        s.colorB[i] = 2;
        s.colorA[i] = 1;
        continue;
      }
      if (RainEffect._force) {
        s.colorR[i] = 2;
        s.colorG[i] = 2;
        s.colorB[i] = 2;
        s.colorA[i] = 1;
        continue;
      }
      s.colorR[i] = (light.x * k + sky.x) * env;
      s.colorG[i] = (light.y * k + sky.y) * env;
      s.colorB[i] = (light.z * k + sky.z) * env;
      s.colorA[i] = env;
    }
  }
}
