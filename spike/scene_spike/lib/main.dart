// LANTERN engine spike: flutter_scene (Flutter GPU / Impeller, WebGL2 on web).
//
// Proves, in one tiny scene: custom .fmat water (vertex displacement,
// refraction from scene color, absorption from scene depth), PBR + IBL from an
// HDRI, a shadow-casting point light (the lantern) plus a shadowed key light,
// GTAO, bloom, depth of field, TAA, height fog, AgX tonemapping, instancing
// (rocks), and runtime render-scale changes. On web, the page can be resized
// to test the fold/unfold reframe path.
import 'dart:math' as math;
import 'dart:ui' as ui;


import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SpikePage(),
      );
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});
  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final Scene scene = Scene();
  bool ready = false;
  String status = 'loading';
  final List<String> log = [];
  final Node lantern = Node(name: 'lantern');
  PreprocessedMaterial? waterMat;
  double t = 0;
  int frames = 0;
  int resizes = 0;
  Size? lastSize;
  double renderScale = 0.7;
  final Stopwatch fpsWatch = Stopwatch()..start();
  final bool upscaleMode = Uri.base.queryParameters['upscale'] == '1';
  RenderTexture? rt;
  ui.FragmentProgram? upscaleProgram;
  final ValueNotifier<int> frameTick = ValueNotifier(0);
  double fps = 0;

  void note(String s) {
    debugPrint('SPIKE: $s');
    log.add(s);
  }

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    try {
      await Scene.initializeStaticResources();
      if (upscaleMode) {
        upscaleProgram = await ui.FragmentProgram.fromAsset('shaders/upscale.frag');
        note('upscale shader loaded');
      }
      await Scene.preload();
      note('static resources ready');

      // Look: dusk, AgX, GTAO, bloom, DoF, height fog, TAA.
      scene.environmentSettings = EnvironmentSettings(
        toneMapping: ToneMappingMode.agx,
        exposure: 0.9,
        bloomEnabled: true,
        bloomThreshold: 1.0,
        bloomIntensity: 0.12,
        ambientOcclusionEnabled: true,
        ambientOcclusionMethod: AmbientOcclusionMethod.groundTruth,
        ambientOcclusionIntensity: 1.0,
        ambientOcclusionHalfResolution: true,
        fogEnabled: true,
        fogMode: FogMode.exponential,
        fogColor: vm.Vector3(0.10, 0.12, 0.16),
        fogDensity: 0.05,
        fogHeight: 0.15,
        fogHeightFalloff: 3.0,
        depthOfFieldEnabled: true,
        depthOfFieldFocusDistance: 6.0,
        depthOfFieldFStop: 1.4,
        depthOfFieldQuality: DepthOfFieldQuality.medium,
        temporalAntiAliasingSharpness: 0.25,
      );
      scene.antiAliasingMode = AntiAliasingMode.taa;
      scene.renderScale = renderScale;
      note('post stack configured (AgX, GTAO, bloom, DoF, fog, TAA)');

      await scene.loadEnvironment('assets/env.hdr',
          showSkybox: true, skyBlur: 0.3, intensity: 0.35, maxWidth: 1024);
      note('HDRI IBL loaded');

      scene.directionalLight = DirectionalLight(
        direction: vm.Vector3(-0.5, -0.6, 0.4),
        color: vm.Vector3(0.55, 0.62, 0.85),
        intensity: 0.6,
        castsShadow: true,
        shadowFilter: DirectionalShadowFilter.pcss,
      );

      if (Uri.base.queryParameters['shadow'] == '1') {
        // Shadow proof: strong low key light, a tall caster, no fog/DoF.
        scene.fog.enabled = false;
        scene.depthOfField.enabled = false;
        scene.directionalLight = DirectionalLight(
          direction: vm.Vector3(-0.7, -0.5, 0.5),
          intensity: 4.0,
          castsShadow: true,
          shadowFilter: DirectionalShadowFilter.pcss,
        );
        final post = Node(name: 'post', mesh: Mesh(CuboidGeometry(vm.Vector3(0.2, 1.6, 0.2)), PhysicallyBasedMaterial()));
        post.position = vm.Vector3(2.2, 1.1, 1.0);
        scene.add(post);
        note('shadow test mode');
      }
      _buildGround();
      _buildRocks();
      await _buildWater();
      _buildLantern();
      note('scene built');

      if (mounted) {
        setState(() {
          ready = true;
          status = 'ready';
        });
      }
    } catch (e, st) {
      note('ERROR: $e');
      debugPrint('$st');
      if (mounted) setState(() => status = 'error: $e');
    }
  }

  // Procedural mossy-stone texture so the spike needs no texture downloads.
  Texture2D _noiseTexture(int size, List<double> a, List<double> b, int seed) {
    final rnd = math.Random(seed);
    final pixels = Uint8List(size * size * 4);
    final grid = List.generate(17 * 17, (_) => rnd.nextDouble());
    double sample(double x, double y) {
      final gx = x * 16, gy = y * 16;
      final ix = gx.floor(), iy = gy.floor();
      final fx = gx - ix, fy = gy - iy;
      double g(int i, int j) => grid[(j % 16) * 17 + (i % 16)];
      final top = g(ix, iy) * (1 - fx) + g(ix + 1, iy) * fx;
      final bot = g(ix, iy + 1) * (1 - fx) + g(ix + 1, iy + 1) * fx;
      return top * (1 - fy) + bot * fy;
    }

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final n = sample(x / size, y / size) * 0.7 + rnd.nextDouble() * 0.3;
        final i = (y * size + x) * 4;
        for (var c = 0; c < 3; c++) {
          pixels[i + c] = ((a[c] * (1 - n) + b[c] * n) * 255).round().clamp(0, 255);
        }
        pixels[i + 3] = 255;
      }
    }
    return Texture2D.fromPixels(pixels, size, size);
  }

  void _buildGround() {
    final mat = PhysicallyBasedMaterial(
      baseColorTexture: _noiseTexture(256, [0.10, 0.12, 0.07], [0.22, 0.24, 0.16], 7),
    )
      ..metallicFactor = 0
      ..roughnessFactor = 0.85;
    // Stream bed sits below the water plane so refraction/absorption have depth.
    final bed = Node(
      name: 'bed',
      mesh: Mesh(PlaneGeometry(width: 12, depth: 12, segmentsX: 8, segmentsZ: 8), mat),
    );
    bed.position = vm.Vector3(0, -0.25, 0);
    scene.add(bed);
    // Banks on both sides.
    for (final x in [-3.2, 3.2]) {
      final bank = Node(
        name: 'bank$x',
        mesh: Mesh(CuboidGeometry(vm.Vector3(3.5, 0.6, 12)), mat),
      );
      bank.position = vm.Vector3(x, 0.05, 0);
      scene.add(bank);
    }
  }

  void _buildRocks() {
    final rockMat = PhysicallyBasedMaterial(
      baseColorTexture: _noiseTexture(128, [0.12, 0.12, 0.11], [0.30, 0.29, 0.27], 3),
    )
      ..metallicFactor = 0
      ..roughnessFactor = 0.45; // wet stone
    final rocks = InstancedMesh(
      geometry: IcosphereGeometry(radius: 0.3, subdivisions: 2),
      material: rockMat,
    );
    final rnd = math.Random(42);
    for (var i = 0; i < 40; i++) {
      final m = vm.Matrix4.compose(
        vm.Vector3(rnd.nextDouble() * 2.6 - 1.3, -0.15, rnd.nextDouble() * 10 - 5),
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), rnd.nextDouble() * 6.28),
        vm.Vector3(0.6 + rnd.nextDouble(), 0.4 + rnd.nextDouble() * 0.5,
            0.6 + rnd.nextDouble()),
      );
      rocks.addInstance(m);
    }
    final node = Node(name: 'rocks')..addComponent(InstancedMeshComponent(rocks));
    scene.add(node);
    note('instanced 40 rocks in one draw');
  }

  Future<void> _buildWater() async {
    final water = await loadFmatMaterial('assets/water.fmat');
    waterMat = water;
    final node = Node(
      name: 'water',
      mesh: Mesh(
          PlaneGeometry(width: 3.0, depth: 12, segmentsX: 48, segmentsZ: 160), water),
    );
    node.position = vm.Vector3(0, -0.05, 0);
    node.shadowCastingMode = ShadowCastingMode.off;
    scene.add(node);
    note('custom .fmat water material loaded');
  }

  void _buildLantern() {
    final paper = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.85, 0.6, 1)
      ..metallicFactor = 0
      ..roughnessFactor = 0.9
      ..emissiveFactor = vm.Vector4(1.0, 0.55, 0.2, 1)
      ..emissiveStrength = 6.0;
    final body = Node(
        name: 'lanternBody',
        mesh: Mesh(CylinderGeometry(bottomRadius: 0.12, topRadius: 0.1, height: 0.22), paper));
    body.shadowCastingMode = ShadowCastingMode.off;
    lantern.add(body);
    final light = Node(name: 'lanternLight')
      ..addComponent(PointLightComponent(PointLight(
        color: vm.Vector3(1.0, 0.62, 0.3),
        intensity: 6.0,
        range: 6.0,
        castsShadow: true,
      )));
    light.position = vm.Vector3(0, 0.05, 0);
    lantern.add(light);
    lantern.position = vm.Vector3(0, 0.08, 0);
    scene.add(lantern);
  }

  void _tick(Duration elapsed, double dt) {
    t += dt;
    frames++;
    frameTick.value++;
    waterMat?.parameters.setFloat('anim_time', t);
    lantern.position = vm.Vector3(math.sin(t * 0.6) * 0.6, 0.08, math.cos(t * 0.25) * 2.0);
    // Dynamic resolution proof: step the render scale every 4 s.
    final want = ((t / 4).floor() % 2 == 0) ? 0.7 : 0.85;
    if (want != renderScale) {
      renderScale = want;
      scene.renderScale = want;
      note('renderScale -> $want at t=${t.toStringAsFixed(1)}');
    }
    if (fpsWatch.elapsedMilliseconds > 1000) {
      fps = frames * 1000 / fpsWatch.elapsedMilliseconds;
      frames = 0;
      fpsWatch.reset();
      if (mounted) setState(() {});
    }
  }

  List<Widget> _upscaled(BuildContext context, Size size, Camera cam) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = math.max(1, (size.width * dpr * renderScale).round());
    final h = math.max(1, (size.height * dpr * renderScale).round());
    rt ??= RenderTexture(width: w, height: h);
    rt!.resize(w, h);
    return [
      // Drives the scene into the internal-res target; draws nothing itself.
      Positioned.fill(
        child: SceneView(scene,
            viewsBuilder: (_) => [RenderView(camera: cam, target: rt)], onTick: _tick),
      ),
      Positioned.fill(
        child: CustomPaint(painter: _UpscalePainter(rt!, upscaleProgram!, frameTick, dpr)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070A),
      body: LayoutBuilder(builder: (context, c) {
        final size = c.biggest;
        if (lastSize != null && lastSize != size) {
          resizes++;
          SchedulerBinding.instance.addPostFrameCallback(
              (_) => note('resized to ${size.width.toInt()}x${size.height.toInt()} (#$resizes)'));
        }
        lastSize = size;
        final aspect = size.width / size.height;
        // Diorama framing on the near-square inner screen, tighter on portrait.
        final dist = aspect > 0.75 ? 9.0 : 7.0;
        final pitch = 55 * vm.degrees2Radians;
        final cam = PerspectiveCamera(
          fovRadiansY: (aspect > 0.75 ? 24 : 28) * vm.degrees2Radians,
          position: vm.Vector3(0, dist * math.sin(pitch), -dist * math.cos(pitch)),
          target: vm.Vector3(0, 0, 0),
        );
        return Stack(children: [
          if (ready && !upscaleMode)
            Positioned.fill(
              child: SceneView(scene, camera: cam, onTick: _tick),
            ),
          if (ready && upscaleMode) ..._upscaled(context, size, cam),
          Positioned(
            left: 12,
            top: 12,
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('flutter_scene spike  status=$status  fps=${fps.toStringAsFixed(1)}  '
                    'scale=$renderScale  ${kIsWeb ? "web" : "native"}  '
                    'size=${size.width.toInt()}x${size.height.toInt()}  resizes=$resizes'),
                for (final l in log.reversed.take(8)) Text(l),
              ]),
            ),
          ),
        ]);
      }),
    );
  }
}





class _UpscalePainter extends CustomPainter {
  _UpscalePainter(this.rt, this.program, this.tick, this.dpr) : super(repaint: tick);
  final RenderTexture rt;
  final ui.FragmentProgram program;
  final ValueNotifier<int> tick;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    final tex = rt.texture;
    if (tex == null) return;
    final img = tex.asImage();
    final shader = program.fragmentShader()
      ..setFloat(0, size.width * dpr)
      ..setFloat(1, size.height * dpr)
      ..setFloat(2, img.width.toDouble())
      ..setFloat(3, img.height.toDouble())
      ..setFloat(4, 0.6)
      ..setFloat(5, (tick.value % 64).toDouble())
      ..setImageSampler(0, img, filterQuality: FilterQuality.low);
    canvas.save();
    canvas.scale(1 / dpr);
    canvas.drawRect(Offset.zero & (size * dpr), Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UpscalePainter old) => true;
}
