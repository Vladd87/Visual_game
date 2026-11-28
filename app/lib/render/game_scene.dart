import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show decodeImageFromList;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../sim/entities.dart';
import '../sim/vec2.dart';
import '../sim/world.dart';
import '../game/diagnostics.dart';
import 'rock_assets.dart';
import 'leaf_model.dart';
import 'lantern_model.dart';
import 'rain.dart';
import 'rock_layout.dart';
import 'surface_pack.dart';
import 'terrain.dart';
import 'vegetation.dart';

/// Builds and animates the 3D scene for a [World].
///
/// M1 greybox: plain lighting and flat materials. Each later milestone
/// replaces one system (water, stone/moss, lighting/fog, rain, vegetation,
/// lantern/fireflies, post, grade) without changing this interface.
class GameScene {
  GameScene(this.scene);

  final Scene scene;
  World? _world;
  final List<Node> _chunks = [];
  // M7: fireflies as soft, motion-stretched glows (ref06), one batch.
  late final BillboardGeometry _fireflyGeom;
  late InstancedMesh _leafMesh;
  late final Node _lantern;
  late final Node _lanternLightNode;
  late final PointLight _lanternLight;
  late final PhysicallyBasedMaterial _paper;
  // M7: paper panels drawn with lantern.fmat (the PBR [_paper] in safe mode).
  late final Node _paperNode;
  late final MeshGeometry _paperGeom;
  PreprocessedMaterial? _paperMat;
  late final Sprite _flame;

  /// The camera's position, set by the controller each frame (the lantern
  /// paper decides which panel faces are seen from inside with it).
  vm.Vector3 cameraEye = vm.Vector3(0, 5, 5);
  late final Sprite _halo;
  bool _staticBuilt = false;
  PreprocessedMaterial? _waterMat;
  PreprocessedMaterial? _groundMat;
  Texture2D? _waterNormal;
  Texture2D? _sky;
  // M3 stone and moss: scanned rocks (one instanced batch per scan) and the
  // photographed bank surfaces.
  List<RockScan> _rockScans = const [];
  final List<PreprocessedMaterial> _rockMats = [];
  final List<Node> _rockNodes = [];
  // M6 vegetation: baked CC0 plants and procedural grass, per-chunk batches.
  List<PlantModel> _plants = const [];
  List<MeshGeometry> _grassClumps = const [];
  Material? _fernMat, _sorrelMat, _grassMat;
  final List<Node> _plantNodes = [];
  // Sky-lit ambient for the hand-made terms in water.fmat and ground.fmat:
  // about a tenth of the open-sky radiance at envIntensity (blue hour).
  // (Doubled in M4 v2: sky light scattered in the tannin water fills the
  // rock shadows on the bed, which read as black holes.)
  static final vm.Vector3 ambient = vm.Vector3(0.012, 0.016, 0.03) * _tune('amb', 1.5);

  // Candle behind paper: deep amber (ref02 paper about 248/170/95, ref10
  // about 248/214/124), not the near-white a hotter emitter turns into under
  // AgX (M4 v3).
  // M4 v6: deeper toward the candle amber of ref02 (its lit water is about
  // 90/40/19); the paler 1.0/0.52/0.2 spilled cream-yellow onto the banks.
  /// Light channel of the lantern's own parts, which its candle does not
  /// light (see the point light).
  static const int _lanternSelfChannel = 0x80;

  /// Light channel of the water, which the candle light skips too.
  static const int _waterChannel = 0x40;
  static final vm.Vector3 lanternColor = vm.Vector3(1.0, 0.42, 0.13);

  static const int maxLeaves = 48;

  final List<PlanarReflectorComponent> _reflectors = [];

  // M5 rain: lantern-lit streaks (null with ?norain=1).
  RainEffect? _rain;
  double? _lastRealTime;

  /// Device bring-up: switches each effect off and back on, so the effects
  /// probe can measure what each contributes on the phone and in the browser.
  Map<String, void Function(bool on)> get effectToggles {
    final sky = scene.directionalLight;
    final aa = scene.antiAliasingMode;
    final waters = _chunks.where((n) => n.name.startsWith('water_')).toList();
    return {
      'bloom': (on) => scene.postProcess.bloom.enabled = on,
      'rain': (on) => _rain?.node.visible = on,
      'fog': (on) => scene.fog.enabled = on,
      'ao': (on) => scene.ambientOcclusion.enabled = on,
      'taa': (on) => scene.antiAliasingMode = on ? aa : AntiAliasingMode.fxaa,
      'shadow': (on) => _lanternLight.castsShadow = on,
      'sky light': (on) => scene.directionalLight = on ? sky : null,
      'reflection': (on) {
        for (final r in _reflectors) {
          r.enabled = on;
        }
      },
      'water': (on) {
        for (final n in waters) {
          n.visible = on;
        }
      },
    };
  }

  /// One-time setup of everything that does not depend on the course.
  void buildStatic() {
    if (_staticBuilt) return;
    _staticBuilt = true;
    // M4 lighting: blue hour under a treeline. No sun or moon: the open sky
    // overhead (image-based) is a cool, dim ambient, a faint shadowless sky
    // light from the open side of the valley gives it direction, and the
    // lantern is the key light (refs 02, 05, 07, 11).
    scene.environmentSettings = EnvironmentSettings(
      toneMapping: ToneMappingMode.agx,
      // M8 round 32: 1.6 -> 2.1 (+0.4 EV). Round 31 critics: the frame is
      // underexposed (mean about 22/255 against about 69 for ref02) and the
      // lantern never clips; a phone exposes a dusk scene brighter.
      exposure: _tune('expo', 2.1),
      // M9 grade. Round 37: round 33's exposure, no colour grading, and a
      // steeper AgX curve (1.25 -> 1.6) for deeper neutral blacks and a
      // brighter lantern core. Round 36 (below, now off) lifted and tinted
      // the shadows and read as "a game night filter" (-0.42).
      // Round 36 notes: the frames sat in a compressed, murky band
      // (median 24/255, 95th percentile about 50) against the references'
      // 44-102 and 97-241, with no blue-hour colour. Graded in linear HDR
      // before AgX, so nothing is stretched after 8-bit quantisation:
      // +0.7 EV, a little more AgX contrast, a faint blue lift in the
      // shadows and a warm gain on the highlights (refs 05, 07, 15). The
      // engine's own contrast pivots on linear mid-grey (0.18): this scene's
      // ambient sits at 0.005-0.02, so even x1.15 clamped it to black.
      agxContrast: _tune('agxc', 1.6),
      colorGradingEnabled: _tune('grade', 0) > 0,
      contrast: _tune('gcon', 1.0),
      saturation: _tune('gsat', 1.15),
      lift: vm.Vector3(_tune('liftr', -0.0005), _tune('liftg', 0.0), _tune('liftb', 0.002)),
      gain: vm.Vector3(_tune('gainr', 1.03), 1.0, _tune('gainb', 0.96)),
      environmentIntensity: envIntensity,
      // Unlit dusk mist hugging the water: dark, so it deepens distance
      // rather than lifting the blacks into a veil.
      fogEnabled: Uri.base.queryParameters['nofog'] != '1',
      fogMode: FogMode.exponential,
      fogColor: vm.Vector3(0.007, 0.010, 0.02),
      fogDensity: 0.25,
      fogHeight: 0.0,
      fogHeightFalloff: 3.0,
      // Ground-truth AO at macro scale: crevices between stones, under
      // overhangs and where rocks meet the bed.
      ambientOcclusionEnabled: Uri.base.queryParameters['noao'] != '1',
      ambientOcclusionMethod: AmbientOcclusionMethod.groundTruth,
      ambientOcclusionRadius: 0.08,
      ambientOcclusionIntensity: 1.0,
      ambientOcclusionHalfResolution: true,
      // Damp air: the lantern (and fireflies) glow into a wide, faint halo
      // (refs 01, 03). Only emitters pass the threshold.
      bloomEnabled: Uri.base.queryParameters['nobloom'] != '1',
      bloomThreshold: 0.6,
      // M4 v8: 0.12 -> 0.18, so the lantern glows into the damp air
      // (critics: no halation or scatter around the light; ref03).
      // Round 32: 0.18 -> 0.3 and wider. Round 31 critics: a lens would
      // spread a wide halo from the lantern into the rainy air (refs 02,
      // 03), not a 20 px glow.
      bloomIntensity: _tune('bloom', 0.3),
      bloomScatter: _tune('bscatter', 0.92),
      // M8 post: a camera's signature (critics since M6: "everything sharp
      // on one plane", "no grain at this exposure", "no lens falloff").
      // Depth of field from a thin lens focused on the lantern each frame
      // (PLAN §1 Lens; refs 09, 11). The low tier gathers 16 taps with no
      // post filter, the phone's budget.
      depthOfFieldEnabled: _tune('dof', 2.8) > 0 && !Diagnostics.noEffects,
      depthOfFieldFStop: math.max(_tune('dof', 2.8), 0.5),
      depthOfFieldFocusDistance: 2.2,
      depthOfFieldQuality: DepthOfFieldQuality.low,
      depthOfFieldMaxForegroundBlur: _tune('dofmax', 14.0),
      depthOfFieldMaxBackgroundBlur: _tune('dofmax', 14.0),
      // Sensor noise: added in linear light before display encoding, so it
      // shows in the shadows as a phone's does at dusk and vanishes in the
      // lit areas (refs 03, 06).
      // Round 32: off; the present pass adds phone-like noise shaped by
      // brightness instead (shaders/upscale.frag).
      filmGrainEnabled: _tune('grain', 0.0) > 0,
      filmGrainIntensity: _tune('grain', 0.0),
      // A lens's gentle falloff toward the corners.
      vignetteEnabled: _tune('vig', 0.25) > 0,
      vignetteIntensity: _tune('vig', 0.25),
      vignetteRadius: 0.7,
      vignetteSmoothness: 0.7,
    );
    // Blue-hour skylight from the open, left side of the valley: cool, faint
    // and shadowless, so stones read lit on one side and darker on the other
    // instead of the flat all-round fill critics called directionless.
    scene.directionalLight = Uri.base.queryParameters['nosky'] == '1'
        ? null
        : DirectionalLight(
            direction: vm.Vector3(0.8, -0.5, 0.3)..normalize(),
            color: vm.Vector3(0.32, 0.48, 1.0),
            intensity: _tune('skyi', 0.135),
            castsShadow: false,
          );
    scene.antiAliasingMode = AntiAliasingMode.taa;
    if (Uri.base.queryParameters['nofit'] == '1') scene.fitNearPlane = false;
    if (Diagnostics.noEffects) {
      // Diagnostic mode: bare tone mapping only.
      scene.environmentSettings = EnvironmentSettings(
        toneMapping: ToneMappingMode.agx,
        exposure: scene.environmentSettings.exposure,
        environmentIntensity: scene.environmentSettings.environmentIntensity,
      );
      scene.antiAliasingMode = AntiAliasingMode.fxaa;
    }

    // Lantern (M7): a floating paper lantern (refs 02, 10) with a warm
    // shadow-casting point light inside: four tapered paper panels on a
    // wooden tray, corner ribs and a rim, open at the top so the flame shows.
    _paper = PhysicallyBasedMaterial()
      // Safe-mode stand-in for lantern.fmat: amber paper, the candle's light
      // seen through it (ref02).
      ..baseColorFactor = vm.Vector4(0.9, 0.55, 0.25, 1)
      ..metallicFactor = 0
      ..roughnessFactor = 0.85
      ..emissiveFactor = vm.Vector4(1.0, 0.44, 0.12, 1)
      ..emissiveStrength = 1.6;
    _lantern = Node(name: 'lantern');
    _paperGeom = LanternModel.paperPanels();
    _paperNode = Node(name: 'lanternPaper', mesh: Mesh(_paperGeom, _paper))
      // The light sits inside the paper: the panels must not block it.
      ..shadowCastingMode = ShadowCastingMode.off
      ..lightChannelMask = _lanternSelfChannel;
    _lantern.add(_paperNode);
    // Dark, damp wood: the tray.
    final woodMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.07, 0.045, 0.028, 1)
      ..metallicFactor = 0
      ..roughnessFactor = 0.55;
    final (trayAt, traySize) = LanternModel.tray();
    _lantern.add(Node(name: 'lanternTray', mesh: Mesh(CuboidGeometry(traySize), woodMat))
      ..position = trayAt
      // Wider than the candle holder: its shadow would be the hard black
      // hole of round 13.
      ..shadowCastingMode = ShadowCastingMode.off
      ..lightChannelMask = _lanternSelfChannel);
    // The tray floor inside, lit warm by the candle (seen through the open
    // top). The candle light itself skips the lantern's parts.
    _lantern.add(Node(name: 'lanternFloor', mesh: Mesh(LanternModel.floor(), UnlitMaterial()..baseColorFactor = vm.Vector4(0.55, 0.2, 0.05, 1)))
      ..shadowCastingMode = ShadowCastingMode.off);
    // A small wooden candle holder under the flame (M4 v5): a soft
    // darkening right under the lantern instead of a hot spot.
    final baseMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.06, 0.04, 0.025, 1)
      ..metallicFactor = 0
      ..roughnessFactor = 0.8;
    final base = Node(name: 'lanternBase', mesh: Mesh(CuboidGeometry(vm.Vector3(0.04, 0.01, 0.04)), baseMat));
    base.position = vm.Vector3(0, 0.012, 0);
    base.lightChannelMask = _lanternSelfChannel;
    _lantern.add(base);
    // The candle flame, upright, seen through the open top.
    _flame = Sprite(
        texture: LanternModel.flameTexture(),
        width: _tune('flamew', 0.014),
        height: _tune('flameh', 0.03),
        blendMode: SpriteBlendMode.additive,
        facing: BillboardFacing.axisLocked);
    _lantern.add(Node(name: 'lanternFlame', mesh: _flame.mesh)
      ..position = vm.Vector3(0, 0.03, 0)
      ..shadowCastingMode = ShadowCastingMode.off);
    // Glow in the damp air around the flame (refs 01, 03): a faint additive
    // halo that dissolves where it meets the bed or banks.
    _halo = Sprite(texture: _haloTexture(), width: 0.7, height: 0.7, blendMode: SpriteBlendMode.additive);
    _halo.material.softDepthFade = 0.05;
    _lantern.add(Node(name: 'lanternHalo', mesh: _halo.mesh)
      ..position = vm.Vector3(0, 0.035, 0)
      ..shadowCastingMode = ShadowCastingMode.off);
    _lanternLight = PointLight(
      color: lanternColor,
      intensity: 1.4,
      // A candle in paper: its light should die within about a metre
      // (refs 02, 03). The engine's falloff is inverse-square windowed to the
      // range, so the range is what bounds the pool. 1.0 m (M4 v3): at 1.3 m
      // the bank slopes facing the lantern still caught a bright rim.
      range: lanternRange,
      castsShadow: Uri.base.queryParameters['noshadow'] != '1' && !Diagnostics.noEffects,
      // The glowing paper box (6.8 × 8.5 cm) is the emitter, not the flame:
      // the radius floors the inverse-square falloff, so the bed right under
      // the lantern no longer outshines the paper (round 27 critics: a
      // waterline blob brighter than the lantern). The lantern's own parts
      // are on another light channel, so the larger sphere no longer
      // whitens them.
      radius: _tune('lrad', 0.06),
      // Wide penumbra: the bank lip and rocks cast soft-edged shade, not the
      // hard bright stripes critics flagged (round 12).
      shadowSoftness: 11.0,
      shadowNear: 0.02,
      shadowMapResolution: 512,
      // Not the lantern's own paper and wood: a few centimetres from the
      // flame they would clip to white (M7 preview). The paper's glow is its
      // emission (lantern.fmat); the frame reads dark against it.
      channelMask: 0xFF & ~_lanternSelfChannel & ~_waterChannel,
    );
    _lanternLightNode = Node(name: 'lanternLight')..addComponent(PointLightComponent(_lanternLight));
    _lanternLightNode.position = vm.Vector3(0, 0.035, 0);
    _lantern.add(_lanternLightNode);
    scene.add(_lantern);

    // Falling streaks are off: round 18 read them as an overlay and round 20
    // split the panel (+0.34 / -0.38) even confined to the lantern's light.
    // ?rainstreaks=1 for tests.
    if (Uri.base.queryParameters['rainstreaks'] == '1') {
      _rain = RainEffect(rate: _tune('rainrate', 3000), size: _tune('rainsize', 1.0), glow: _tune('rainglow', 3.0),
          stretch: _tune('rainstretch', 0.024));
      scene.add(_rain!.node
        ..shadowCastingMode = ShadowCastingMode.off
        ..frustumCulled = false);
    }

    // Fireflies (M7): soft glows of varied size and brightness, drawn out
    // a little along their flight by the exposure (ref06), instead of the
    // hard identical dots critics flagged.
    _fireflyGeom = BillboardGeometry(capacity: 256)
      ..facing = BillboardFacing.velocityStretched
      // About 1/8 s of motion (round 33).
      ..velocityStretch = _tune('ffstretch', 0.12);
    final fireflyMat = SpriteMaterial(colorTexture: fireflyTexture())
      ..blendMode = SpriteBlendMode.additive
      ..softDepthFade = 0.01;
    final fireflies = Node(name: 'fireflies', mesh: Mesh(_fireflyGeom, fireflyMat))
      ..shadowCastingMode = ShadowCastingMode.off
      // After the water: both draw in the translucent pass, sprites write no
      // depth, and the water drawn later painted over every firefly above it.
      ..renderOrder = 1
      ..layers = _noMirrorLayer
      ..frustumCulled = false;
    if (Uri.base.queryParameters['noff'] != '1') scene.add(fireflies);

    // Leaves (M7): real leaf outlines with veins, cupped, each its own shade
    // from dull green to rust (refs 08, 12), instead of flat orange cards.
    // Hidden ones are scaled to zero.
    final leafMat = PhysicallyBasedMaterial()
      ..baseColorTexture = leafTexture()
      ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
      ..alphaMode = AlphaMode.mask
      ..alphaCutoff = 0.5
      ..metallicFactor = 0
      // Wet: a soft sheen.
      ..roughnessFactor = 0.45
      ..doubleSided = true;
    _leafMesh = InstancedMesh(geometry: leafGeometry(), material: leafMat);
    // Mixed yellow and brown, as fallen leaves on a stream (ref08).
    const leafShades = [
      [0.62, 0.30, 0.10], // rust
      [0.72, 0.55, 0.14], // yellow
      [0.38, 0.22, 0.10], // brown
      [0.40, 0.40, 0.14], // dull olive
      [0.78, 0.48, 0.13], // amber
      [0.30, 0.17, 0.08], // dark, soaked
      [0.62, 0.50, 0.22], // pale ochre
    ];
    for (var i = 0; i < maxLeaves; i++) {
      final c = leafShades[(i * 7 + 3) % leafShades.length];
      // The texture is sRGB (about 0.5 linear on the blade): lift the shades
      // so the leaves read about as bright as the old cards.
      final k = _tune('leafk', 1.8) * (0.85 + 0.3 * ((math.sin(i * 3.7) * 43758.5453) % 1.0).abs());
      _leafMesh.addInstance(vm.Matrix4.zero(), color: vm.Vector4(c[0] * k, c[1] * k, c[2] * k, 1));
    }
    // The greybox leaves sit centimetres from the lantern's point light, so their
    // shadow lands on the bed magnified into a hard dark trapezoid (round-5
    // critic). Off until M6 gives leaves real shapes and softer shadows.
    scene.add(Node(name: 'leaves')
      ..addComponent(InstancedMeshComponent(_leafMesh))
      ..frustumCulled = false
      ..shadowCastingMode = ShadowCastingMode.off);
  }

  /// Loads materials, baked textures and the environment (before [buildCourse]).
  Future<void> loadAssets() async {
    if (Diagnostics.safeRender) {
      // The previous launch died while setting up rendering: plain PBR
      // materials and greybox rocks, so the game at least runs.
      await Diagnostics.checkpoint('environment');
      await scene.loadEnvironment('assets/env/blue_hour_forest.hdr', showSkybox: false, intensity: envIntensity, maxWidth: 1024);
      return;
    }
    await Diagnostics.checkpoint('materials');
    _waterNormal = await _loadTexture('assets/textures/water_normal.png');
    _sky = await _loadTexture('assets/textures/sky_blue.png', mipmaps: false);
    final wv = Diagnostics.waterVariant;
    _waterMat = await loadFmatMaterial(wv > 0 && wv < 9 ? 'assets/materials/bringup/water_v$wv.fmat' : 'assets/materials/water.fmat');
    _groundMat = await loadFmatMaterial('assets/materials/ground.fmat');
    _paperMat = await loadFmatMaterial('assets/materials/lantern.fmat');
    _paperNode.mesh = Mesh(_paperGeom, _paperMat!);
    // Saturated amber (AgX pales bright, weakly saturated colours to cream).
    _paperMat!.parameters.setVec3('tint', vm.Vector3(1.0, _tune('ptg', 0.23), _tune('ptb', 0.035)));
    _paperMat!.parameters.setFloat('inner', _tune('pinner', 0.3));
    _waterMat!.parameters.setTexture('normal_tex', _waterNormal!.gpuTexture, sampler: _waterNormal!.sampledSampler);
    _waterMat!.parameters.setTexture('sky_tex', _sky!.gpuTexture, sampler: _sky!.sampledSampler);
    // Baked sky encodes sqrt(radiance / 1.3939) (scale printed by tools/bake/bake_sky.py).
    // The reflected sky is 1.6x the diffuse sky level: in a banked channel the
    // bed sees only part of the sky (occluded diffuse), while the upward
    // reflection sees it unobstructed. Until M4 adds real occlusion, this
    // ratio stands in for it.
    _waterMat!.parameters.setFloat('sky_scale', 1.3939 * skyLevel);
    _waterMat!.parameters.setFloat('treeline', _tune('tree', 0.9));
    _waterMat!.parameters.setFloat('treeline_soft', _tune('tsoft', 0.08));
    _waterMat!.parameters.setFloat('canopy_cover', _tune('canopy', 0.5));
    _waterMat!.parameters.setFloat('sky_broad', _tune('skybroad', 0.6));
    _waterMat!.parameters.setFloat('canopy_scale', _tune('cscale', 1.0));
    // M5: light rain on the water (rings and splashes).
    _waterMat!.parameters.setFloat('rain', _tune('rain', 2.0));
    // In rain the sheltered stream's wind ripples are small next to the
    // drop rings (M5 v2): at full strength their flow-stretched pattern read
    // as painted swirls and concentric arcs (critics, rounds 15-18).
    _waterMat!.parameters.setFloat('normal_strength', _tune('nstr', 0.5));
    _waterMat!.parameters.setFloat('foam_amount', _tune('foam', 1.0));
    // M7: the lantern's reflection (see water.fmat LanternMirror).
    _waterMat!.parameters.setFloat('lantern_mirror', _tune('lmirror', 13.0));
    // Ground and rocks bind few textures: Android guarantees only 16 fragment
    // samplers and the lit pipeline already uses about ten (surface_pack.dart).
    await Diagnostics.checkpoint('textures');
    final data = await buildGroundData();
    _bind(_groundMat!, 'data_tex', data);
    // Banks: forest ground, moss cushions and waterline mud (all CC0,
    // ASSETS.md), packed into one padded atlas pair.
    final atlas = await buildSurfaceAtlas();
    _bind(_groundMat!, 's_t1', atlas.t1);
    _bind(_groundMat!, 's_t2', atlas.t2);
    // Rocks: two scanned sets, one material per texture set; moss caps come
    // from the bank atlas.
    await Diagnostics.checkpoint('rocks');
    _rockScans = await loadRockScans();
    for (final set in ['rock_moss_set_01', 'rock_moss_set_02']) {
      final m = await loadFmatMaterial('assets/materials/rock.fmat');
      final (t1, t2) = await packRockSet(set);
      _bind(m, 'r_t1', t1);
      _bind(m, 'r_t2', t2);
      _bind(m, 's_t1', atlas.t1);
      _bind(m, 's_t2', atlas.t2);
      _rockMats.add(m);
    }
    for (final m in [_waterMat!, _groundMat!]) {
      m.parameters.setVec3('ambient', ambient);
    }
    // M6 vegetation (Poly Haven fern_02 and shrub_sorrel_01, CC0).
    await Diagnostics.checkpoint('plants');
    _plants = await loadPlants();
    _fernMat = _plantMaterial(await _loadTexture('assets/textures/plants/fern_02_col.png', content: TextureContent.color));
    _sorrelMat = _plantMaterial(await _loadTexture('assets/textures/plants/shrub_sorrel_01_col.png', content: TextureContent.color));
    _grassMat = PhysicallyBasedMaterial()
      ..baseColorTexture = _grassGradient()
      ..doubleSided = true
      ..metallicFactor = 0
      // Rain-wet blades: a soft sheen.
      ..roughnessFactor = 0.5;
    _grassClumps = [for (var s = 0; s < 4; s++) buildGrassClump(101 + s, blades: 16 + 4 * s, height: 0.09 + 0.02 * s)];
    // M5: rain wets the banks and rocks (0.35 was the light drizzle of M3/M4).
    final damp = _tune('damp', 0.7);
    for (final m in [_groundMat!, ..._rockMats]) {
      m.parameters.setFloat('damp', damp);
    }
    _groundMat!.parameters.setFloat('moss_bias', _tune('mossbias', 0.1));
    // Blue hour (Poly Haven aarfontein_dawn) behind a forest treeline, baked by
    // tools/bake/bake_env.py.
    await Diagnostics.checkpoint('environment');
    await scene.loadEnvironment('assets/env/blue_hour_forest.hdr', showSkybox: false, intensity: envIntensity, maxWidth: 1024);
    await Diagnostics.checkpoint('assets loaded');
  }

  /// Diffuse sky fill (image-based light) on banks, rocks and bed. M4 v6:
  /// 0.25 -> 0.19, so the canopy-shaded banks sit darker than the open sky
  /// the water mirrors (critics: "lit by a flat grey fill, not by a sky").
  /// Render layer for things the water's planar mirror must not draw.
  static const int _noMirrorLayer = 1 << 4;

  // M9 round 39: the balance of light. More dusk sky (image light,
  // skylight and the custom shaders' ambient x1.5) and less candle (x0.7):
  // round 38 critics found the lantern lit banks a metre away 30-40x the
  // unlit grass, "an electric lamp against near-black dusk" (refs 02, 07).
  static final double envIntensity = _tune('env', 0.285);

  /// Radiance of the open sky the water reflects, in the same units as
  /// [envIntensity]. The stream's surface sees the open sky gap above the
  /// channel, which the banks see only partly. Was 0.25 x 1.6 = 0.4; 1.2 from M4 v6.
  // M9 round 38: 1.2 -> 2.5. Round 37 critics: water and banks sat at one
  // flat level, "midnight, not dusk"; at dusk the water carries the sky
  // and is much brighter than the banks (refs 01, 11).
  static final double skyLevel = _tune('skylvl', 2.5);

  /// Reach of the lantern's light (m). M4 v7: 1.0 -> 0.65, so the banks show
  /// a hot spot near the lantern that dies quickly (refs 02, 10) instead of
  /// long, evenly lit strips.
  static final double lanternRange = _tune('lrange', 0.65);

  /// Browser tuning only: a query parameter overrides a look constant, so
  /// variants can be captured from one web build. Android has no query.
  static double _tune(String key, double fallback) =>
      double.tryParse(Uri.base.queryParameters[key] ?? '') ?? fallback;

  /// Device bring-up: one flat quad over [m]'s extent at the water level,
  /// with both windings, in place of the water mesh.
  static MeshArrays _bringUpQuad(MeshArrays m) {
    var x0 = double.infinity, x1 = -double.infinity, z0 = double.infinity, z1 = -double.infinity;
    for (var i = 0; i < m.positions.length; i += 3) {
      x0 = math.min(x0, m.positions[i]);
      x1 = math.max(x1, m.positions[i]);
      z0 = math.min(z0, m.positions[i + 2]);
      z1 = math.max(z1, m.positions[i + 2]);
    }
    final pos = Float32List.fromList([x0, 0.001, z0, x1, 0.001, z0, x1, 0.001, z1, x0, 0.001, z1]);
    final nrm = Float32List.fromList([0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0]);
    final col = Float32List.fromList(List.filled(16, 0.5));
    return MeshArrays(pos, nrm, col, [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]);
  }

  /// Soft radial falloff for the lantern halo (premultiplied, white).
  static Texture2D _haloTexture() {
    const n = 64;
    final px = Uint8List(n * n * 4);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final dx = (x + 0.5) / n * 2 - 1, dy = (y + 0.5) / n * 2 - 1;
        final r = math.sqrt(dx * dx + dy * dy);
        // A bright core falling off into a long, faint tail; zero at the edge.
        final v = (math.exp(-r * r * 9) * 0.7 + math.exp(-r * 3.2) * 0.3) * (1 - r).clamp(0.0, 1.0);
        final b = (255 * v).round().clamp(0, 255);
        final o = (y * n + x) * 4;
        px[o] = b;
        px[o + 1] = b;
        px[o + 2] = b;
        px[o + 3] = b;
      }
    }
    return Texture2D.fromPixels(px, n, n, content: TextureContent.color);
  }

  static Future<Texture2D> _loadTexture(String path,
      {bool mipmaps = true, TextureContent content = TextureContent.data}) async {
    final bytes = await rootBundle.load(path);
    final image = await decodeImageFromList(bytes.buffer.asUint8List());
    final data = await image.toByteData();
    return Texture2D.fromPixels(data!.buffer.asUint8List(), image.width, image.height,
        content: content,
        sampling: TextureSampling(maxAnisotropy: 8, mipmaps: mipmaps));
  }

  /// Leaf cut-outs: alpha-tested, both sides lit; wet leaves are a little
  /// glossy (refs 01, 04).
  static Material _plantMaterial(Texture2D colour) => PhysicallyBasedMaterial()
    ..baseColorTexture = colour
    ..alphaMode = AlphaMode.mask
    ..alphaCutoff = 0.5
    ..doubleSided = true
    ..metallicFactor = 0
    ..roughnessFactor = 0.5;

  /// Blade colour from base (dark, shaded by the clump) to tip (paler).
  static Texture2D _grassGradient() {
    const w = 4, h = 64;
    final px = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      final t = y / (h - 1); // v = 0 at the base
      final r = (46 + 96 * t).round(), g = (62 + 110 * t).round(), b = (24 + 38 * t).round();
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        px[o] = r;
        px[o + 1] = g;
        px[o + 2] = b;
        px[o + 3] = 255;
      }
    }
    return Texture2D.fromPixels(px, w, h, content: TextureContent.color);
  }

  static void _bind(PreprocessedMaterial m, String name, Texture2D t) =>
      m.parameters.setTexture(name, t.gpuTexture, sampler: t.sampledSampler);

  /// (Re)builds everything that depends on the course of [world].
  void buildCourse(World world) {
    _world = world;
    for (final n in _chunks) {
      scene.remove(n);
    }
    _chunks.clear();
    _reflectors.clear();
    for (final n in _rockNodes) {
      scene.remove(n);
    }
    _rockNodes.clear();

    final c = world.course;
    final Material groundMat = _groundMat ?? (PhysicallyBasedMaterial()..metallicFactor = 0..roughnessFactor = 0.92);
    final Material waterMat = _waterMat ??
        (PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.035, 0.05, 0.055, 0.78)
          ..metallicFactor = 0
          ..roughnessFactor = 0.06
          ..alphaMode = AlphaMode.blend);
    const chunk = 4.0;
    for (var d0 = -2.5; d0 < c.endD + 4.0; d0 += chunk) {
      final d1 = math.min(d0 + chunk, c.endD + 4.5);
      final g = buildGroundChunk(c, d0, d1);
      final ground = Node(
        name: 'ground_${d0.toStringAsFixed(0)}',
        mesh: Mesh(MeshGeometry.fromArrays(positions: g.positions, normals: g.normals, colors: g.colors, texCoords: g.texCoords, indices: g.indices), groundMat),
      )..shadowStatic = true;
      final w = Diagnostics.waterQuad ? _bringUpQuad(buildWaterChunk(c, world.flow, d0, d1)) : buildWaterChunk(c, world.flow, d0, d1);
      final water = Node(
        name: 'water_${d0.toStringAsFixed(0)}',
        mesh: Mesh(
            MeshGeometry.fromArrays(
                positions: w.positions, normals: w.normals, colors: Diagnostics.waterNoColors ? null : w.colors, indices: w.indices),
            Diagnostics.waterVariant == 9 ? groundMat : waterMat),
      )
        ..shadowCastingMode = ShadowCastingMode.off
        // The candle's light does not reach the water directly (M7): as a
        // 6 cm sphere of about 70× the paper's drawn brightness, its
        // specular reflection made a blob below the lantern brighter than
        // the lantern itself (round 27). The water draws the lantern's
        // reflection from the paper instead (water.fmat LanternMirror).
        ..lightChannelMask = _tune('waterlit', 0) == 1 ? 0xFF : _waterChannel;
      if (Uri.base.queryParameters['noreflect'] != '1' && !Diagnostics.noEffects && !Diagnostics.noReflect) {
        // One shared mirror capture for every water chunk (they are co-planar).
        // Fireflies stay out of the mirror. At the mirror's 0.4 scale a 13 mm
        // firefly covers part of a pixel; the water reads any lit mirror
        // pixel as "an object hides the sky" and swapped the sky for that dim
        // value: the "dark specks" critics saw in the pools since M2.
        final reflector = PlanarReflectorComponent(
            resolutionScale: 0.4, reflectionGroupId: 0, clipBias: 0.002, layerMask: kRenderLayerAll & ~_noMirrorLayer);
        _reflectors.add(reflector);
        water.addComponent(reflector);
      }
      scene.add(ground);
      if (Uri.base.queryParameters['nowater'] != '1') scene.add(water);
      _chunks..add(ground)..add(water);
    }

    // Rocks: CC0 photogrammetry scans, one instanced batch per scan. Each sim
    // rock picks a scan, yaw and scale (rock_layout.dart), sits on the bed or a
    // gravel mound the terrain raises under it, and gets a slight tint.
    if (_rockScans.isEmpty) {
      final rockMat = PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.2, 0.2, 0.19, 1)
        ..metallicFactor = 0
        ..roughnessFactor = 0.55;
      final rocks = InstancedMesh(geometry: IcosphereGeometry(radius: 1, subdivisions: 2), material: rockMat, cullInstances: true);
      for (final r in c.rocks) {
        rocks.addInstance(vm.Matrix4.compose(vm.Vector3(r.pos.x, r.height - r.radius, -r.pos.y), vm.Quaternion.identity(),
            vm.Vector3(r.radius, r.radius, r.radius)));
      }
      _rockNodes.add(Node(name: 'rocks')
        ..addComponent(InstancedMeshComponent(rocks))
        ..shadowStatic = true);
    } else {
      final batches = [
        for (final scan in _rockScans)
          InstancedMesh(geometry: scan.geometry, material: _rockMats[scan.set], cullInstances: true),
      ];
      for (final pl in rockPlacements(c, flatGroundHeight)) {
        final seed = pl.rock.seed;
        final tint = 0.86 + 0.24 * ((seed >> 4) & 0xff) / 255.0;
        final warm = 0.96 + 0.08 * ((seed >> 12) & 0xff) / 255.0;
        batches[pl.type].addInstance(
          vm.Matrix4.compose(
            vm.Vector3(pl.rock.pos.x, pl.baseY, -pl.rock.pos.y),
            vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), pl.yaw),
            vm.Vector3(pl.sx, pl.sy, pl.sz),
          ),
          color: vm.Vector4(tint * warm, tint, tint / warm, 1),
        );
      }
      for (var i = 0; i < batches.length; i++) {
        if (batches[i].instanceCount == 0) continue;
        _rockNodes.add(Node(name: 'rocks_$i')
          ..addComponent(InstancedMeshComponent(batches[i]))
          ..shadowStatic = true);
      }
    }
    for (final n in _rockNodes) {
      scene.add(n);
    }

    // M6 vegetation, batched per 4 m chunk so whole chunks cull by bounds.
    for (final n in _plantNodes) {
      scene.remove(n);
    }
    _plantNodes.clear();
    if (_plants.isNotEmpty && Uri.base.queryParameters['noplants'] != '1') {
      final ferns = [for (final p in _plants) if (p.kind == 0) p];
      final sorrel = _plants.firstWhere((p) => p.kind == 1);
      final batches = <String, InstancedMesh>{};
      for (final pl in vegetationPlacements(c, rockPlacements(c, flatGroundHeight),
          fernVariants: ferns.length, grassVariants: _grassClumps.length)) {
        final ci = ((pl.d + 2.5) / chunk).floor();
        final key = '${pl.kind.name}_${pl.variant}_$ci';
        final mesh = batches.putIfAbsent(key, () {
          final (MeshGeometry geo, Material mat) = switch (pl.kind) {
            PlantKind.fern => (ferns[pl.variant].geometry, _fernMat!),
            PlantKind.sorrel => (sorrel.geometry, _sorrelMat!),
            PlantKind.grass || PlantKind.edgeGrass => (_grassClumps[pl.variant], _grassMat!),
          };
          return InstancedMesh(geometry: geo, material: mat, cullInstances: true);
        });
        mesh.addInstance(pl.transform, color: pl.tint);
      }
      for (final e in batches.entries) {
        final kind = e.key.split('_').first;
        final node = Node(name: 'plants_${e.key}')
          ..addComponent(InstancedMeshComponent(e.value))
          ..shadowStatic = true;
        // Only ferns are big enough to cast the lantern's shadow; ground
        // cover away from the water stays out of the mirror (cost).
        if (kind != PlantKind.fern.name) node.shadowCastingMode = ShadowCastingMode.off;
        if (kind == PlantKind.sorrel.name || kind == PlantKind.grass.name) node.layers = _noMirrorLayer;
        _plantNodes.add(node);
        scene.add(node);
      }
    }

  }

  /// Per-frame update from the simulation ([alpha] interpolates the lantern).
  void update(double alpha, double realTime) {
    final w = _world;
    if (w == null) return;
    final pose = w.lanternPose(alpha);
    final t = w.time;

    // Lantern: bob and sway on the water, yaw from the sim.
    final bob = 0.004 * math.sin(realTime * 2.1) + 0.002 * math.sin(realTime * 3.7 + 1);
    final tiltX = 0.05 * math.sin(realTime * 1.6 + 0.4);
    final tiltZ = 0.05 * math.sin(realTime * 1.3);
    _lantern.localTransform = vm.Matrix4.compose(
      vm.Vector3(pose.pos.x, bob, -pose.pos.y),
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), pose.angle) *
          vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), tiltX) *
          vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), tiltZ),
      vm.Vector3.all(1),
    );
    final flicker = 0.92 + 0.05 * math.sin(realTime * 13.0) + 0.03 * math.sin(realTime * 29.0 + 1.3);
    final f = w.flame;
    // The paper far brighter than the scene (as a candle dominates ref02), so
    // its mirror image and glints read on the water at this steep view
    // (Fresnel ~3 %); the light it casts slightly lower again (bank stripes).
    _lanternLight.intensity = (0.15 + 0.66 * f * flicker) * _tune('llight', 0.7);
    _paper.emissiveStrength = 0.1 + 1.6 * f * flicker;
    _paperMat?.parameters
      ?..setVec3('cam', cameraEye)
      ..setFloat('yaw', pose.angle);
    _paperMat?.parameters.setFloat('glow', _tune('pglow', 0.15) + _tune('pglowf', 1.25) * f * flicker);
    final fl = 0.2 + 1.0 * f * flicker;
    _flame.color = vm.Vector4(1.0 * fl, 0.62 * fl, 0.26 * fl, 1.0) * _tune('flame', 4.0);
    _halo.color = vm.Vector4(1.0, 0.42, 0.13, 1.0) * ((0.03 + 0.18 * f * flicker) * _tune('halo', 1.0));
    final lp = vm.Vector3(pose.pos.x, 0.035 + bob, -pose.pos.y);
    // Focus on the lantern (M8).
    scene.depthOfField.focusDistance = (cameraEye - lp).length;
    final ll = lanternColor * _lanternLight.intensity;
    final rainDt = _lastRealTime == null ? 0.0 : (realTime - _lastRealTime!).clamp(0.0, 0.1);
    _lastRealTime = realTime;
    _rain?.update(
      dt: rainDt,
      focus: vm.Vector3(lp.x, 0, lp.z),
      lanternPos: lp,
      lanternLight: ll,
      range: lanternRange,
      // Dusk sky light caught by the drops: next to nothing (round 18: dim
      // streaks everywhere read as an overlay).
      sky: vm.Vector3(0.002, 0.0025, 0.004),
    );
    for (final m in [_waterMat, _groundMat]) {
      if (m == null) continue;
      m.parameters.setVec3('lantern_pos', lp);
      m.parameters.setVec3('lantern_light', ll);
      m.parameters.setFloat('lantern_range', lanternRange);
      // The same extended-source near field for the custom lantern terms.
      m.parameters.setFloat('lantern_soft', _tune('lsoft', 0.0055));
      if (m == _waterMat) m.parameters.setFloat('lantern_yaw', pose.angle);
    }

    // Fireflies: hover, blink; collected ones spiral up into the lantern and
    // fade. Each has its own size and brightness, and its velocity draws its
    // glow out into a short streak.
    var nff = 0;
    final ffSize = _tune('ffsize', 0.045), ffGlow = _tune('ffglow', 3.0);
    for (var i = 0; i < w.fireflies.length && nff < _fireflyGeom.capacity; i++) {
      final ff = w.fireflies[i];
      vm.Vector3 at(double tt) {
        V2 p;
        double h;
        if (!ff.collected || tt < ff.collectedAt) {
          p = ff.positionAt(tt);
          h = ff.heightAt(tt);
        } else {
          final k = ((tt - ff.collectedAt) / 0.8).clamp(0.0, 1.0);
          final from = ff.positionAt(ff.collectedAt);
          p = V2.lerp(from, pose.pos, k);
          h = ff.heightAt(ff.collectedAt) * (1 - k) + 0.04 * k;
          if (w.phase == RunPhase.won) {
            // Finale: gathered fireflies rise into the sky.
            final rise = ((tt - w.endedAt) / 6.0).clamp(0.0, 1.0);
            if (rise > 0) {
              final a = i * 2.399;
              p = pose.pos + V2(math.cos(a), math.sin(a)) * (0.05 + 0.25 * rise);
              h = 0.05 + rise * 1.6 + 0.1 * math.sin(i + tt);
            }
          }
        }
        return vm.Vector3(p.x, h, -p.y);
      }

      var s = 1.0;
      if (ff.collected) {
        final k = ((t - ff.collectedAt) / 0.8).clamp(0.0, 1.0);
        s = 1 - k;
        if (w.phase == RunPhase.won && t > w.endedAt) s = 1;
      }
      final g = ff.glowAt(t) * s;
      if (g < 0.01) continue;
      // Per-firefly variety (stable hash of the index).
      final h1 = (math.sin(i * 12.9898) * 43758.5453) % 1.0;
      final h2 = (math.sin(i * 78.233 + 1.7) * 43758.5453) % 1.0;
      final size = ffSize * (0.6 + 0.8 * h1.abs()) * (0.75 + 0.25 * g);
      final bright = ffGlow * g * (0.3 + 1.2 * h2.abs());
      final c = at(t);
      // Exposure-time streaks (M8 round 33): on top of its sim motion each
      // firefly flits in its own direction at 0.1-0.3 m/s, so a dusk
      // exposure draws dashes of different lengths and directions, not
      // frozen dots (refs 04, 06).
      final h3 = (math.sin(i * 39.346 + 0.5) * 43758.5453) % 1.0;
      final h4 = (math.sin(i * 11.135 + 2.3) * 43758.5453) % 1.0;
      final ang = h3.abs() * 2 * math.pi + 0.6 * math.sin(t * 0.7 + i);
      final flit = _tune('ffflit', 1.0) * (0.1 + 0.2 * h4.abs());
      final vel = (c - at(t - 0.05)) / 0.05 +
          vm.Vector3(math.cos(ang) * flit, 0.25 * flit * math.sin(t * 1.3 + i * 2.1), math.sin(ang) * flit);
      _fireflyGeom.setInstance(nff++,
          center: c,
          width: size,
          height: size,
          // Saturated yellow-green bioluminescence (ref06; round 27 critics
          // measured the old tint as pale cream).
          color: vm.Vector4(0.72 * bright, 1.0 * bright, 0.16 * bright, 1),
          velocity: vel);
    }
    _fireflyGeom.commit(nff);

    // Leaves.
    _leafMesh.updateInstanceTransforms((list) {
      for (var i = 0; i < maxLeaves; i++) {
        if (i >= w.leaves.length) {
          list[i].setZero();
          continue;
        }
        final leaf = w.leaves[i];
        final flutter = leaf.state == LeafState.falling ? math.sin(leaf.age * 5 + leaf.seed % 9) * 0.6 : 0.0;
        final pos = leaf.state == LeafState.stuck ? pose.pos : leaf.pos;
        // Stuck leaves rest across the lantern's open top.
        // A third of the floating leaves ride low, soaked, their middle just
        // under the surface (ref08); sizes vary from 0.7 to 1.3.
        final hs = ((math.sin(leaf.seed * 12.9898) * 43758.5453) % 1.0).abs();
        final sunk = leaf.state == LeafState.floating && hs < 0.33 ? -0.003 : 0.0;
        final y = leaf.state == LeafState.stuck ? LanternModel.trayTop + LanternModel.height + 0.001 : leaf.height + 0.002 + sunk;
        list[i].setFromTranslationRotationScale(
          vm.Vector3(pos.x, y, -pos.y),
          vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), leaf.angle) * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), flutter),
          vm.Vector3.all(0.7 + 0.6 * ((math.sin(leaf.seed * 78.233 + 1.7) * 43758.5453) % 1.0).abs()),
        );
      }
    });
  }
}
