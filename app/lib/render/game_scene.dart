import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show decodeImageFromList;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../sim/entities.dart';
import '../sim/vec2.dart';
import '../sim/world.dart';
import 'rock_assets.dart';
import 'rock_layout.dart';
import 'terrain.dart';

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
  late InstancedMesh _fireflyMesh;
  late InstancedMesh _leafMesh;
  late final Node _lantern;
  late final Node _lanternLightNode;
  late final PointLight _lanternLight;
  late final PhysicallyBasedMaterial _paper;
  bool _staticBuilt = false;
  PreprocessedMaterial? _waterMat;
  PreprocessedMaterial? _groundMat;
  Texture2D? _waterNormal;
  Texture2D? _caustics;
  Texture2D? _sky;
  // M3 stone and moss: scanned rocks (one instanced batch per scan) and the
  // photographed bank surfaces.
  List<RockScan> _rockScans = const [];
  final List<PreprocessedMaterial> _rockMats = [];
  final List<Node> _rockNodes = [];
  static final vm.Vector3 ambient = vm.Vector3(0.018, 0.022, 0.028);

  static const int maxLeaves = 48;

  /// One-time setup of everything that does not depend on the course.
  void buildStatic() {
    if (_staticBuilt) return;
    _staticBuilt = true;
    scene.environmentSettings = EnvironmentSettings(
      toneMapping: ToneMappingMode.agx,
      exposure: 1.6,
      environmentIntensity: 0.2,
    );
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(0.35, -0.8, 0.45),
      color: vm.Vector3(0.62, 0.7, 0.9),
      intensity: 0.35,
      castsShadow: false,
    );
    scene.antiAliasingMode = AntiAliasingMode.taa;
    if (Uri.base.queryParameters['nofit'] == '1') scene.fitNearPlane = false;

    // Lantern: paper cube with a warm shadow-casting point light inside.
    _paper = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.95, 0.86, 0.7, 1)
      ..metallicFactor = 0
      ..roughnessFactor = 0.85
      ..emissiveFactor = vm.Vector4(1.0, 0.62, 0.3, 1)
      ..emissiveStrength = 3.0;
    _lantern = Node(name: 'lantern');
    final body = Node(name: 'lanternBody', mesh: Mesh(CuboidGeometry(vm.Vector3(0.07, 0.07, 0.07)), _paper));
    body.position = vm.Vector3(0, 0.03, 0);
    body.shadowCastingMode = ShadowCastingMode.off;
    _lantern.add(body);
    _lanternLight = PointLight(
      color: vm.Vector3(1.0, 0.6, 0.28),
      intensity: 0.9,
      range: 2.2,
      castsShadow: Uri.base.queryParameters['noshadow'] != '1',
      radius: 0.03, // a 7 cm paper lantern, not a point: soft shadows, broad glints
      shadowSoftness: 3.0,
      shadowNear: 0.02,
      shadowMapResolution: 512,
    );
    _lanternLightNode = Node(name: 'lanternLight')..addComponent(PointLightComponent(_lanternLight));
    _lanternLightNode.position = vm.Vector3(0, 0.035, 0);
    _lantern.add(_lanternLightNode);
    scene.add(_lantern);

    // Fireflies: tiny emissive spheres, instanced.
    final fireflyMat = UnlitMaterial()..baseColorFactor = vm.Vector4(3.2, 4.0, 1.1, 1);
    _fireflyMesh = InstancedMesh(geometry: SphereGeometry(radius: 0.0065, segments: 8, rings: 5), material: fireflyMat);
    scene.add(Node(name: 'fireflies')
      ..addComponent(InstancedMeshComponent(_fireflyMesh))
      ..shadowCastingMode = ShadowCastingMode.off
      ..frustumCulled = false);

    // Leaves: thin cards, instanced; hidden ones are scaled to zero.
    final leafMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.42, 0.22, 0.08, 1)
      ..metallicFactor = 0
      ..roughnessFactor = 0.7
      ..doubleSided = true;
    _leafMesh = InstancedMesh(geometry: CuboidGeometry(vm.Vector3(0.05, 0.002, 0.034)), material: leafMat);
    for (var i = 0; i < maxLeaves; i++) {
      _leafMesh.addInstance(vm.Matrix4.zero());
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
    _waterNormal = await _loadTexture('assets/textures/water_normal.png');
    _caustics = await _loadTexture('assets/textures/caustics.png');
    _sky = await _loadTexture('assets/textures/sky_dusk.png', mipmaps: false);
    _waterMat = await loadFmatMaterial('assets/materials/water.fmat');
    _groundMat = await loadFmatMaterial('assets/materials/ground.fmat');
    _waterMat!.parameters.setTexture('normal_tex', _waterNormal!.gpuTexture, sampler: _waterNormal!.sampledSampler);
    _waterMat!.parameters.setTexture('sky_tex', _sky!.gpuTexture, sampler: _sky!.sampledSampler);
    // Baked sky encodes sqrt(radiance / 4.9162) (scale printed by tools/bake/bake_sky.py).
    // The reflected sky is 1.6x the diffuse sky level: in a banked channel the
    // bed sees only part of the sky (occluded diffuse), while the upward
    // reflection sees it unobstructed. Until M4 adds real occlusion, this
    // ratio stands in for it.
    _waterMat!.parameters.setFloat('sky_scale', 4.9162 * envIntensity * 1.6);
    _groundMat!.parameters.setTexture('caustic_tex', _caustics!.gpuTexture, sampler: _caustics!.sampledSampler);
    _groundMat!.parameters.setTexture('noise_tex', _waterNormal!.gpuTexture, sampler: _waterNormal!.sampledSampler);
    // Banks: forest ground, moss cushions and waterline mud (all CC0, ASSETS.md).
    await _bindSurface(_groundMat!, 'forest_ground', 'g_');
    await _bindSurface(_groundMat!, 'moss', 'm_');
    await _bindSurface(_groundMat!, 'mud', 'u_');
    // Rocks: two scanned sets, one material per texture atlas.
    _rockScans = await loadRockScans();
    for (final set in ['rock_moss_set_01', 'rock_moss_set_02']) {
      final m = await loadFmatMaterial('assets/materials/rock.fmat');
      await _bindSurface(m, set, 'r_');
      await _bindSurface(m, 'moss', 'm_');
      _rockMats.add(m);
    }
    for (final m in [_waterMat!, _groundMat!]) {
      m.parameters.setVec3('ambient', ambient);
    }
    // Dusk sky (after sunset) for water reflections and ambient light.
    await scene.loadEnvironment('assets/env/qwantani_dusk_2_1k.hdr', showSkybox: false, intensity: envIntensity, maxWidth: 1024);
  }

  static const double envIntensity = 0.2;

  static Future<Texture2D> _loadTexture(String path,
      {bool mipmaps = true, TextureContent content = TextureContent.data}) async {
    final bytes = await rootBundle.load(path);
    final image = await decodeImageFromList(bytes.buffer.asUint8List());
    final data = await image.toByteData();
    return Texture2D.fromPixels(data!.buffer.asUint8List(), image.width, image.height,
        content: content,
        sampling: TextureSampling(maxAnisotropy: 8, mipmaps: mipmaps));
  }

  /// Binds one packed surface (`<name>_col/_nrm/_arh.jpg`, see
  /// tools/bake/pack_surface_textures.py) to [m] as `<prefix>col` etc.
  static Future<void> _bindSurface(PreprocessedMaterial m, String name, String prefix) async {
    const dir = 'assets/textures/surfaces';
    final col = await _loadTexture('$dir/${name}_col.jpg', content: TextureContent.color);
    final nrm = await _loadTexture('$dir/${name}_nrm.jpg', content: TextureContent.normal);
    final arh = await _loadTexture('$dir/${name}_arh.jpg');
    m.parameters.setTexture('${prefix}col', col.gpuTexture, sampler: col.sampledSampler);
    m.parameters.setTexture('${prefix}nrm', nrm.gpuTexture, sampler: nrm.sampledSampler);
    m.parameters.setTexture('${prefix}arh', arh.gpuTexture, sampler: arh.sampledSampler);
  }

  /// (Re)builds everything that depends on the course of [world].
  void buildCourse(World world) {
    _world = world;
    for (final n in _chunks) {
      scene.remove(n);
    }
    _chunks.clear();
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
      final w = buildWaterChunk(c, world.flow, d0, d1);
      final water = Node(
        name: 'water_${d0.toStringAsFixed(0)}',
        mesh: Mesh(MeshGeometry.fromArrays(positions: w.positions, normals: w.normals, colors: w.colors, indices: w.indices), waterMat),
      )
        ..shadowCastingMode = ShadowCastingMode.off;
      if (Uri.base.queryParameters['noreflect'] != '1') {
        // One shared mirror capture for every water chunk (they are co-planar).
        water.addComponent(PlanarReflectorComponent(resolutionScale: 0.4, reflectionGroupId: 0, clipBias: 0.002));
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

    // Fireflies follow the course list one-to-one.
    _fireflyMesh.clearInstances();
    for (var i = 0; i < world.fireflies.length; i++) {
      _fireflyMesh.addInstance(vm.Matrix4.zero(), color: vm.Vector4.all(1));
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
    _lanternLight.intensity = 0.12 + 0.55 * f * flicker;
    _paper.emissiveStrength = 0.3 + 4.0 * f * flicker;
    final lp = vm.Vector3(pose.pos.x, 0.035 + bob, -pose.pos.y);
    final ll = vm.Vector3(1.0, 0.6, 0.28) * _lanternLight.intensity;
    for (final m in [_waterMat, _groundMat]) {
      if (m == null) continue;
      m.parameters.setVec3('lantern_pos', lp);
      m.parameters.setVec3('lantern_light', ll);
    }

    // Fireflies: hover, blink; collected ones spiral up into the lantern and fade.
    _fireflyMesh.updateInstanceTransforms((list) {
      for (var i = 0; i < w.fireflies.length; i++) {
        final ff = w.fireflies[i];
        V2 p;
        double h, s;
        if (!ff.collected) {
          p = ff.positionAt(t);
          h = ff.heightAt(t);
          s = 1;
        } else {
          final k = ((t - ff.collectedAt) / 0.8).clamp(0.0, 1.0);
          final from = ff.positionAt(ff.collectedAt);
          p = V2.lerp(from, pose.pos, k);
          h = ff.heightAt(ff.collectedAt) * (1 - k) + 0.04 * k;
          s = 1 - k;
          if (w.phase == RunPhase.won) {
            // Finale: gathered fireflies rise into the sky.
            final rise = ((t - w.endedAt) / 6.0).clamp(0.0, 1.0);
            if (rise > 0) {
              final a = i * 2.399;
              p = pose.pos + V2(math.cos(a), math.sin(a)) * (0.05 + 0.25 * rise);
              h = 0.05 + rise * 1.6 + 0.1 * math.sin(i + t);
              s = 1;
            }
          }
        }
        list[i].setFromTranslationRotationScale(vm.Vector3(p.x, h, -p.y), vm.Quaternion.identity(), vm.Vector3.all(s));
      }
    });
    for (var i = 0; i < w.fireflies.length; i++) {
      final g = w.fireflies[i].glowAt(t);
      _fireflyMesh.setInstanceColor(i, vm.Vector4(g, g, g, 1));
    }

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
        final y = leaf.state == LeafState.stuck ? 0.072 : leaf.height + 0.002;
        list[i].setFromTranslationRotationScale(
          vm.Vector3(pos.x, y, -pos.y),
          vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), leaf.angle) * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), flutter),
          vm.Vector3.all(1),
        );
      }
    });
  }
}
