import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';

/// M7: fallen leaves on the water and fireflies, in place of the flat orange
/// cards and hard dots critics flagged every round.

/// A leaf blade, 5 cm long and 3.4 cm wide (x along the leaf, base at -x),
/// cupped a little along the midrib like a drying leaf on water. UV u runs
/// base to tip, v across.
MeshGeometry leafGeometry() {
  const nx = 6, nz = 4;
  const length = 0.05, width = 0.034;
  final pos = <double>[], nrm = <double>[], uv = <double>[];
  final idx = <int>[];
  for (var i = 0; i <= nx; i++) {
    for (var j = 0; j <= nz; j++) {
      final u = i / nx, v = j / nz;
      final x = (u - 0.5) * length, z = (v - 0.5) * width;
      // Edges curl up, the tip lifts a little.
      final across = (v - 0.5) * 2;
      final y = 0.004 * across * across + 0.003 * u * u;
      pos.addAll([x, y, z]);
      nrm.addAll([0, 1, 0]);
      uv.addAll([u, v]);
    }
  }
  for (var i = 0; i < nx; i++) {
    for (var j = 0; j < nz; j++) {
      final a = i * (nz + 1) + j, b = a + nz + 1;
      idx.addAll([a, a + 1, b + 1, a, b + 1, b]);
    }
  }
  return MeshGeometry.fromArrays(
    positions: Float32List.fromList(pos),
    normals: Float32List.fromList(nrm),
    texCoords: Float32List.fromList(uv),
    indices: idx,
  );
}

double _h(int x, int y, int s) {
  final v = math.sin(x * 127.1 + y * 311.7 + s * 74.7) * 43758.5453;
  return v - v.floorToDouble();
}

double _vnoise(double x, double y, int s) {
  final xi = x.floor(), yi = y.floor();
  final fx = x - xi, fy = y - yi;
  final wx = fx * fx * (3 - 2 * fx), wy = fy * fy * (3 - 2 * fy);
  final a = _h(xi, yi, s), b = _h(xi + 1, yi, s), c = _h(xi, yi + 1, s), d = _h(xi + 1, yi + 1, s);
  return (a + (b - a) * wx) + ((c + (d - c) * wx) - (a + (b - a) * wx)) * wy;
}

/// A fallen leaf, colour in RGB and its outline in alpha: an ovate blade
/// with a pointed tip and a stalk, a pale midrib and paired side veins,
/// browner toward the edges and spotted with decay (refs 08, 12). Neutral
/// enough that per-instance colours tint it from dull green to rust.
Texture2D leafTexture() {
  const w = 256, h = 128;
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final u = (x + 0.5) / w; // base (0) to tip (1)
      final v = (y + 0.5) / h * 2 - 1; // across, -1..1
      // Blade half-width along the leaf: widest a third of the way, pointed
      // tip, short stalk at the base.
      final t = ((u - 0.08) / 0.9).clamp(0.0, 1.0);
      var half = math.pow(math.sin(math.pi * math.pow(t, 0.75)), 0.8).toDouble() * 0.92;
      // Slightly serrated, irregular margin.
      half *= 0.95 + 0.05 * math.sin(u * 90) + 0.04 * (_vnoise(u * 30, v.sign, 3) - 0.5);
      final stalk = u < 0.1 && v.abs() < 0.05;
      final inside = v.abs() < half || stalk;
      final o = (y * w + x) * 4;
      if (!inside) {
        px[o + 3] = 0;
        continue;
      }
      final edgeD = half > 0 ? 1 - v.abs() / half : 0.0;
      // Midrib and paired side veins running out toward the tip.
      final midrib = math.exp(-math.pow(v / 0.035, 2));
      final along = u - v.abs() * 0.35;
      final veinPhase = (along * 9) - (along * 9).floorToDouble();
      final vein = math.exp(-math.pow((veinPhase - 0.5) / 0.06, 2)) * (edgeD > 0.08 ? 1.0 : 0.0) * (t > 0.05 && t < 0.92 ? 1.0 : 0.0);
      // Mottling and decay spots.
      final mott = _vnoise(u * 14, v * 7, 1);
      final spot = (_vnoise(u * 26, v * 13, 2) > 0.78) ? 1.0 : 0.0;
      // Lighter blade, browner rim.
      var l = 0.72 + 0.18 * mott;
      l *= 1 - 0.35 * (1 - math.min(1.0, edgeD * 4));
      l *= 1 - 0.45 * spot;
      l += 0.18 * midrib + 0.08 * vein;
      final br = (1 - math.min(1.0, edgeD * 3)) * 0.5 + spot * 0.4;
      final r = (l * (0.9 + 0.1 * br)).clamp(0.0, 1.0);
      final g = (l * (0.85 - 0.25 * br)).clamp(0.0, 1.0);
      final b = (l * (0.62 - 0.25 * br)).clamp(0.0, 1.0);
      px[o] = (255 * r).round();
      px[o + 1] = (255 * g).round();
      px[o + 2] = (255 * b).round();
      px[o + 3] = 255;
    }
  }
  return Texture2D.fromPixels(px, w, h, content: TextureContent.color);
}

/// A firefly's light as a camera sees it at dusk (ref06): a small bright
/// core inside a soft halo of defocus and damp air.
Texture2D fireflyTexture() {
  const n = 32;
  final px = Uint8List(n * n * 4);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final dx = (x + 0.5) / n * 2 - 1, dy = (y + 0.5) / n * 2 - 1;
      final r2 = dx * dx + dy * dy;
      final v = (math.exp(-r2 / 0.05) + 0.3 * math.exp(-r2 / 0.3)) * (1 - math.min(1.0, r2)).clamp(0.0, 1.0);
      final b = (255 * v.clamp(0.0, 1.0)).round();
      final o = (y * n + x) * 4;
      // Brightness in colour only: additive sprites multiply colour by
      // alpha, so the same profile in both would square it (a 1 px core).
      px[o] = b;
      px[o + 1] = b;
      px[o + 2] = b;
      px[o + 3] = 255;
    }
  }
  return Texture2D.fromPixels(px, n, n, content: TextureContent.color);
}
