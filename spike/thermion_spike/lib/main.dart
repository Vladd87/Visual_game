// LANTERN engine spike: Thermion (Filament).
//
// Same checklist as the flutter_scene spike: runtime-compiled custom water
// material (Filament screen-space refraction), KTX IBL + skybox, shadowed sun
// and point light, GTAO, bloom, height fog, TAA, glTF instancing. Depth of
// field and dynamic resolution are probed and reported (no Dart bindings).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:thermion_flutter/thermion_flutter.dart' hide Transform;

void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});
  @override
  Widget build(BuildContext context) => WidgetsApp(
        color: const Color(0xFF05070A),
        debugShowCheckedModeBanner: false,
        builder: (_, __) => const SpikePage(),
      );
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});
  @override
  State<SpikePage> createState() => _SpikePageState();
}

const _waterSource = '''
material {
    name : SpikeWater,
    shadingModel : lit,
    blending : opaque,
    refractionMode : screenspace,
    refractionType : thin,
    parameters : [ { type : float, name : time } ],
    requires : [ uv0 ]
}
fragment {
    float hash12(vec2 p) {
        vec3 p3 = fract(vec3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }
    float vnoise(vec2 p) {
        vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
                   mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
    }
    void material(inout MaterialInputs material) {
        vec2 uv = getUV0() * 24.0 - vec2(0.0, materialParams.time * 1.2);
        float e = 0.05;
        float h = vnoise(uv);
        vec2 g = vec2(vnoise(uv + vec2(e, 0.0)) - h, vnoise(uv + vec2(0.0, e)) - h) / e;
        material.normal = normalize(vec3(-g.x * 0.1, -g.y * 0.1, 1.0));
        prepareMaterial(material);
        material.baseColor = vec4(0.02, 0.05, 0.05, 1.0);
        material.roughness = 0.05;
        material.metallic = 0.0;
        material.transmission = 0.9;
        material.absorption = vec3(2.0, 1.1, 0.9);
        material.ior = 1.33;
    }
}
''';

class _SpikePageState extends State<SpikePage> {
  final List<String> log = [];
  ThermionViewer? viewer;
  MaterialInstance? water;
  Timer? timer;
  double t = 0;
  int resizes = 0;
  Size? lastSize;

  void note(String s) {
    debugPrint('SPIKE: $s');
    if (mounted) setState(() => log.add(s));
  }

  Future<void> _setup(ThermionViewer v) async {
    viewer = v;
    note('viewer available (${kIsWeb ? "web" : "native"})');
    try {
      await v.loadIbl('assets/default_env_ibl.ktx', intensity: 8000);
      note('KTX IBL loaded');
      await v.setPostProcessing(true);
      await v.setBloom(true, 0.12);
      await v.setAntiAliasing(false, false, true);
      await v.setShadowsEnabled(true);
      note('post: bloom + TAA + shadows on');
      try {
        await v.view.setAmbientOcclusionOptions(const AmbientOcclusionOptions(
            enabled: true, aoType: AmbientOcclusionType.GTAO));
        note('GTAO on');
      } catch (e) {
        note('GTAO FAILED: $e');
      }
      try {
        await v.view.setFogOptions(FogOptions(
            enabled: true, density: 0.08, height: 0.1, heightFalloff: 3.0,
            linearColor: Vector3(0.10, 0.12, 0.16)));
        note('height fog on');
      } catch (e) {
        note('fog FAILED: $e');
      }
      note('DoF: no binding in thermion_dart 0.7.0 View API');
      note('dynamic resolution: no binding in thermion_dart 0.7.0 View API');

      await v.addDirectLight(DirectLight.sun(
          direction: Vector3(-0.5, -0.6, 0.4).normalized(),
          intensity: 20000,
          castShadows: true));
      await v.addDirectLight(DirectLight.point(
          position: Vector3(0, 0.15, 0),
          intensity: 200000,
          falloffRadius: 6,
          colorTemperature: 2700,
          castShadows: true));
      note('sun + shadowed point light added');

      // Instancing: one glTF, many native instances sharing GPU resources.
      final cube = await v.loadGltf('assets/cube.glb');
      final rnd = math.Random(42);
      await cube.setTransform(Matrix4.compose(
          Vector3(0.4, -0.1, 0.5), Quaternion.identity(), Vector3.all(0.25)));
      for (var i = 0; i < 20; i++) {
        final inst = await cube.createInstance();
        await inst.setTransform(Matrix4.compose(
            Vector3(rnd.nextDouble() * 2.4 - 1.2, -0.12, rnd.nextDouble() * 8 - 4),
            Quaternion.axisAngle(Vector3(0, 1, 0), rnd.nextDouble() * 6),
            Vector3.all(0.15 + rnd.nextDouble() * 0.2)));
        await v.addToScene(inst);
      }
      note('glTF + 20 instances');

      // Stream bed + water with a runtime-compiled Filament material.
      final bed = await v.createGeometry(GeometryUtils.plane(width: 6, height: 12));
      await bed.setTransform(Matrix4.translation(Vector3(0, -0.25, 0)));
      if (FilamentApp.instance!.runtimeMaterialsSupported) {
        final mat = await FilamentApp.instance!.compileMaterialPackage('SpikeWater', _waterSource);
        water = await mat.createInstance();
        final plane = await v.createGeometry(GeometryUtils.plane(width: 3, height: 12),
            materialInstances: [water!]);
        await plane.setTransform(Matrix4.translation(Vector3(0, -0.05, 0)));
        note('runtime-compiled refractive water material OK');
      } else {
        note('runtime materials NOT supported in this build');
      }

      final cam = await v.getActiveCamera();
      final pitch = 55 * math.pi / 180;
      const dist = 9.0;
      await cam.lookAt(Vector3(0, dist * math.sin(pitch), -dist * math.cos(pitch)),
          focus: Vector3.zero(), up: Vector3(0, 1, 0));
      note('scene built');
      timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        t += 0.033;
        water?.setParameterFloat('time', t);
      });
    } catch (e, st) {
      note('ERROR: $e');
      debugPrint('$st');
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = c.biggest;
      if (lastSize != null && lastSize != size) {
        resizes++;
        scheduleMicrotask(() => note('resized to ${size.width.toInt()}x${size.height.toInt()} (#$resizes)'));
      }
      lastSize = size;
      return Stack(children: [
        Positioned.fill(
          child: ViewerWidget(
            skyboxPath: 'assets/default_env_skybox.ktx',
            onViewerAvailable: _setup,
            initial: const ColoredBox(color: Color(0xFF101010)),
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 11, fontFamily: 'monospace'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('thermion spike size=${size.width.toInt()}x${size.height.toInt()} resizes=$resizes'),
              for (final l in log.reversed.take(14)) Text(l),
            ]),
          ),
        ),
      ]);
    });
  }
}
