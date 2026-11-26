import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../sim/course.dart';
import '../sim/vec2.dart';
import 'rock_layout.dart';
import 'terrain.dart';

/// M6 vegetation: CC0 plant scans (Poly Haven fern_02 and shrub_sorrel_01,
/// baked by tools/bake/bake_plants.py) and procedural grass clumps,
/// scattered over the banks so they are no longer a flat, tiled carpet and
/// the waterline is broken by plants (critics, every panel since M3).

/// One baked plant (see tools/bake/bake_plants.py for the format).
class PlantModel {
  PlantModel(this.kind, this.radius, this.height, this.geometry);

  /// Source index: 0 = fern_02 (four variants), 1 = shrub_sorrel_01 (clump).
  final int kind;

  /// Horizontal half-extent and height, metres, as baked.
  final double radius, height;
  final MeshGeometry geometry;
}

/// Loads assets/plants/plants.bin.
Future<List<PlantModel>> loadPlants() async {
  final data = await rootBundle.load('assets/plants/plants.bin');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final buf = Uint8List.fromList(bytes).buffer;
  final bd = ByteData.view(buf);
  if (String.fromCharCodes(bytes.sublist(0, 4)) != 'LPL1') {
    throw StateError('plants.bin: bad magic');
  }
  final count = bd.getUint32(4, Endian.little);
  var o = 8;
  Float32List floats(int n) {
    final v = Float32List.fromList(Float32List.view(buf, o, n));
    o += n * 4;
    return v;
  }

  final out = <PlantModel>[];
  for (var i = 0; i < count; i++) {
    final kind = bd.getUint32(o, Endian.little);
    final nv = bd.getUint32(o + 4, Endian.little);
    final ni = bd.getUint32(o + 8, Endian.little);
    final r = bd.getFloat32(o + 12, Endian.little);
    final h = bd.getFloat32(o + 16, Endian.little);
    o += 20;
    final pos = floats(nv * 3);
    final nrm = floats(nv * 3);
    final uv = floats(nv * 2);
    final idx = List<int>.from(Uint16List.view(buf, o, ni));
    o += ni * 2;
    o += (-ni * 2) % 4;
    out.add(PlantModel(kind, r, h, MeshGeometry.fromArrays(positions: pos, normals: nrm, texCoords: uv, indices: idx)));
  }
  return out;
}

/// Grass clump variants (M6 v2): fresh, mixed wet-ground clumps; drier
/// ones with straw and dead blades for the upper bank; and low dense mats
/// for the waterline.
const int kGrassWet = 0, kGrassDry = 3, kGrassMat = 6, kGrassVariants = 8;

List<MeshGeometry> buildGrassVariants() => [
      for (var s = 0; s < 3; s++) buildGrassClump(101 + s, blades: 18 + 5 * s, height: 0.09 + 0.025 * s, dry: 0.1),
      for (var s = 0; s < 3; s++) buildGrassClump(201 + s, blades: 14 + 5 * s, height: 0.08 + 0.025 * s, dry: 0.6),
      for (var s = 0; s < 2; s++) buildGrassClump(301 + s, blades: 34 + 8 * s, height: 0.05 + 0.012 * s, dry: 0.25, spread: 0.05),
    ];

/// A clump of grass blades rising from a small base and arching outward,
/// each a tapering strip of three segments. UV v runs base (0) to tip (1)
/// for a darker base and paler tip; u picks one of four colour columns per
/// blade (fresh green, olive, straw, dead brown), weighted by [dry], so a
/// clump is not one uniform colour (critics, round 22).
MeshGeometry buildGrassClump(int seed, {int blades = 14, double height = 0.13, double dry = 0.2, double spread = 0.018}) {
  final rnd = math.Random(seed);
  const segs = 3;
  final pos = <double>[];
  final nrm = <double>[];
  final uv = <double>[];
  final idx = <int>[];
  for (var b = 0; b < blades; b++) {
    final az = rnd.nextDouble() * math.pi * 2;
    final dir = vm.Vector3(math.cos(az), 0, math.sin(az));
    final side = vm.Vector3(-dir.z, 0, dir.x);
    final base = dir * (rnd.nextDouble() * spread);
    final roll = rnd.nextDouble();
    final pGreen = 0.55 - 0.4 * dry, pOlive = 0.3, pStraw = 0.1 + 0.25 * dry;
    final col = roll < pGreen ? 0 : (roll < pGreen + pOlive ? 1 : (roll < pGreen + pOlive + pStraw ? 2 : 3));
    final u = (col + 0.5) / 4;
    final h = height * (0.55 + 0.6 * rnd.nextDouble());
    final lean = 0.25 + 0.55 * rnd.nextDouble(); // how far the tip arches out, x height
    final w0 = 0.0028 + 0.0022 * rnd.nextDouble();
    final first = pos.length ~/ 3;
    for (var s = 0; s <= segs; s++) {
      final t = s / segs;
      // Arch: rises, then bends outward more toward the tip.
      final p = base + dir * (lean * h * t * t) + vm.Vector3(0, h * (t - 0.25 * t * t * lean), 0);
      final w = w0 * (1 - t * 0.92);
      final tangent = (dir * (2 * lean * t) + vm.Vector3(0, 1 - 0.5 * t * lean, 0))..normalize();
      final n = side.cross(tangent)..normalize();
      for (final k in const [-1.0, 1.0]) {
        final q = p + side * (w * k);
        pos.addAll([q.x, q.y, q.z]);
        nrm.addAll([n.x, n.y, n.z]);
        uv.addAll([u, t]);
      }
    }
    for (var s = 0; s < segs; s++) {
      final a = first + s * 2;
      idx.addAll([a, a + 1, a + 2, a + 1, a + 3, a + 2]);
    }
  }
  return MeshGeometry.fromArrays(
    positions: Float32List.fromList(pos),
    normals: Float32List.fromList(nrm),
    texCoords: Float32List.fromList(uv),
    indices: idx,
  );
}

/// What a placement draws.
enum PlantKind { fern, sorrel, grass, edgeGrass }

class PlantPlacement {
  PlantPlacement(this.kind, this.variant, this.d, this.transform, this.tint);
  final PlantKind kind;

  /// Fern model 0-3, grass clump 0-3 (sorrel has one).
  final int variant;

  /// Stream distance, for chunking.
  final double d;
  final vm.Matrix4 transform;
  final vm.Vector4 tint;
}

double _hash(int a, int b, int s) {
  var h = (a * 73856093) ^ (b * 19349663) ^ (s * 83492791);
  h = (h ^ (h >> 13)) * 1274126177;
  h = h ^ (h >> 16);
  return (h & 0xffffff) / 0x1000000;
}

/// Smooth value noise in [0, 1] at [p] (metres) with cells of [cell] m.
double _noise(V2 p, double cell, int salt) {
  final x = p.x / cell, y = p.y / cell;
  final ix = x.floor(), iy = y.floor();
  final fx = x - ix, fy = y - iy;
  final ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
  final a = _hash(ix, iy, salt), b = _hash(ix + 1, iy, salt);
  final c = _hash(ix, iy + 1, salt), d = _hash(ix + 1, iy + 1, salt);
  return (a + (b - a) * ux) * (1 - uy) + (c + (d - c) * ux) * uy;
}

/// Patchiness: grass grows in clumped stands with bare gaps, not as an
/// even sprinkle (PLAN.md: never "regularly spaced").
double _patch(V2 p, int salt) => 0.65 * _noise(p, 0.7, salt) + 0.35 * _noise(p, 0.23, salt + 1);

double _smooth(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Deterministic scatter over the banks of [c].
///
/// Zones by distance [out] outside the (noisy) water's edge:
///  - 0-12 cm: dense grass leaning over the water, which breaks the
///    knife-cut edge critics flagged (refs 01, 09, 13);
///  - 10 cm-1.2 m: ferns in loose groups (ref 04);
///  - 5 cm-2 m: low sorrel patches as ground cover;
///  - 12 cm-2.5 m: scattered grass clumps.
/// Nothing grows inside a rock's footprint.
List<PlantPlacement> vegetationPlacements(Course c, List<RockPlacement> rocks, {int fernVariants = 4}) {
  final out = <PlantPlacement>[];
  const span = 2.6;

  bool clearOfRocks(V2 p, double r) {
    for (final pl in placementsNear(rocks, p.y - 1.0, p.y + 1.0)) {
      final dx = p.x - pl.rock.pos.x, dy = p.y - pl.rock.pos.y;
      final lim = pl.reach * 1.05 + r;
      if (dx * dx + dy * dy < lim * lim) return false;
    }
    return true;
  }

  double outside(V2 p) => -(c.clearance(p) + shoreNoise(p));

  void place(PlantKind kind, int variant, V2 p, double scale, double yaw, {double tiltX = 0, double tiltZ = 0, double sink = 0.004}) {
    final pk = (p.x * 1000).round(), pd = (p.y * 1000).round();
    final y = groundHeight(c, p) - sink;
    final q = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw);
    if (tiltX != 0 || tiltZ != 0) {
      q.setFrom(vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), tiltX) * vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), tiltZ) * q);
    }
    final hue = _hash(pk, pd, 7);
    var lum = 0.78 + 0.4 * _hash(pk, pd, 11);
    var tint = vm.Vector4(lum * (0.96 + 0.1 * hue), lum, lum * (1.04 - 0.1 * hue), 1);
    if (kind == PlantKind.fern) {
      // Ferns read as "flat dark cards": lift them, and turn some bronze as
      // late-season fronds do (refs 03, 05).
      lum = 1.15 + 0.35 * _hash(pk, pd, 12);
      tint = _hash(pk, pd, 14) < 0.3
          ? vm.Vector4(lum * 1.3, lum * 0.95, lum * 0.55, 1)
          : vm.Vector4(lum * (0.95 + 0.1 * hue), lum, lum * 0.9, 1);
    }
    out.add(PlantPlacement(kind, variant, p.y,
        vm.Matrix4.compose(vm.Vector3(p.x, y, -p.y), q, vm.Vector3.all(scale)), tint));
  }

  final dEnd = c.endD + 2.0;
  // Fine grid: grass.
  const g = 0.07;
  for (var i = (-2.5 / g).floor(); i * g < dEnd; i++) {
    final d0 = i * g;
    final cx = c.centerX(d0.clamp(0.0, c.length));
    for (var j = (-span / g).floor(); j * g <= span; j++) {
      final jx = _hash(i, j, 1), jy = _hash(i, j, 2);
      final p = V2(cx + (j + jx) * g, d0 + jy * g);
      final o = outside(p);
      if (o < -0.01) continue;
      final r = _hash(i, j, 3);
      final patch = _patch(p, 5);
      if (o < 0.16) {
        // A dense, continuous mat along the waterline that spills over it,
        // with a few gaps of bare mud.
        if (r > 0.45 + 0.5 * _smooth(0.25, 0.55, patch)) continue;
        if (!clearOfRocks(p, 0.03)) continue;
        // Lean toward the water: tilt about the bank's tangent.
        final e = 0.02;
        final gx = c.clearance(V2(p.x + e, p.y)) - c.clearance(V2(p.x - e, p.y));
        final gy = c.clearance(V2(p.x, p.y + e)) - c.clearance(V2(p.x, p.y - e));
        final len = math.sqrt(gx * gx + gy * gy) + 1e-9;
        final wx = gx / len, wz = -gy / len; // world x/z toward the water
        final lean = 0.25 + 0.3 * _hash(i, j, 4);
        final mat = _hash(i, j, 7) < 0.45;
        final v = mat ? kGrassMat + (r * 97).floor() % 2 : kGrassWet + (r * 97).floor() % 3;
        place(PlantKind.edgeGrass, v, p, 0.7 + 1.1 * _hash(i, j, 5),
            _hash(i, j, 6) * math.pi * 2,
            tiltX: wz * lean, tiltZ: -wx * lean);
      } else if (o < 2.5) {
        // Stands of grass separated by bare patches, thicker toward the
        // wet ground by the water; drier (straw, dead blades) up the bank.
        final wet = 1 - _smooth(0.15, 1.6, o);
        final density = (0.35 + 0.4 * wet) * _smooth(0.45, 0.7, patch) + 0.02;
        if (r > density) continue;
        // Irregular, not one clump per cell: a random offset up to a whole
        // cell beyond the cell (critics: "almost on a grid").
        final q = V2(p.x + (_hash(i, j, 8) - 0.5) * g * 1.6, p.y + (_hash(i, j, 9) - 0.5) * g * 1.6);
        if (!clearOfRocks(q, 0.03)) continue;
        final v = _hash(i, j, 10) < wet ? kGrassWet + (r * 97).floor() % 3 : kGrassDry + (r * 97).floor() % 3;
        final sz = 0.5 + 1.5 * math.pow(_hash(i, j, 5), 1.6);
        place(PlantKind.grass, v, q, sz, _hash(i, j, 6) * math.pi * 2);
      }
    }
  }
  // Coarse grids: ferns and sorrel.
  for (final (kind, cell, oMin, oMax, prob) in const [
    (PlantKind.fern, 0.42, 0.08, 1.4, 0.55),
    (PlantKind.sorrel, 0.22, 0.04, 2.2, 0.6),
  ]) {
    final salt = kind.index * 31;
    for (var i = (-2.5 / cell).floor(); i * cell < dEnd; i++) {
      final d0 = i * cell;
      final cx = c.centerX(d0.clamp(0.0, c.length));
      for (var j = (-span / cell).floor(); j * cell <= span; j++) {
        final p = V2(cx + (j + _hash(i, j, salt + 1)) * cell, d0 + _hash(i, j, salt + 2) * cell);
        final o = outside(p);
        if (o < oMin || o > oMax) continue;
        // Ferns favour the moist ground near the water and grow in groups;
        // sorrel carpets the gaps between grass stands.
        final pr = kind == PlantKind.fern
            ? prob * (1.2 - 0.6 * (o / oMax)) * _smooth(0.35, 0.65, _noise(p, 1.1, 9))
            : prob * (1 - _smooth(0.4, 0.62, _patch(p, 5))) * _smooth(0.45, 0.7, _noise(p, 0.9, 13));
        if (_hash(i, j, salt + 3) > pr) continue;
        if (kind == PlantKind.fern) {
          final v = (_hash(i, j, salt + 4) * fernVariants).floor() % fernVariants;
          if (!clearOfRocks(p, 0.12)) continue;
          place(kind, v, p, 0.45 + 0.45 * _hash(i, j, salt + 5), _hash(i, j, salt + 6) * math.pi * 2, sink: 0.01);
        } else {
          if (!clearOfRocks(p, 0.08)) continue;
          place(kind, 0, p, 1.0 + 0.8 * _hash(i, j, salt + 5), _hash(i, j, salt + 6) * math.pi * 2, sink: 0.002);
        }
      }
    }
  }
  return out;
}
