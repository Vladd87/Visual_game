import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';

/// One baked rock scan (see tools/bake/bake_rocks.py for the format).
class RockScan {
  RockScan(this.set, this.height, this.geometry);

  /// Which texture atlas (rock_moss_set_01 = 0, _02 = 1).
  final int set;

  /// Height divided by the horizontal half-extent (the footprint is unit).
  final double height;
  final MeshGeometry geometry;
}

/// Loads assets/rocks/rocks.bin: decimated CC0 photogrammetry rocks.
Future<List<RockScan>> loadRockScans() async {
  final data = await rootBundle.load('assets/rocks/rocks.bin');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  // Copy into an aligned buffer so typed views can be taken directly.
  final buf = Uint8List.fromList(bytes).buffer;
  final bd = ByteData.view(buf);
  if (String.fromCharCodes(bytes.sublist(0, 4)) != 'LRK1') {
    throw StateError('rocks.bin: bad magic');
  }
  final count = bd.getUint32(4, Endian.little);
  var o = 8;
  final out = <RockScan>[];
  Float32List floats(int n) {
    final v = Float32List.fromList(Float32List.view(buf, o, n));
    o += n * 4;
    return v;
  }

  for (var i = 0; i < count; i++) {
    final set = bd.getUint32(o, Endian.little);
    final nv = bd.getUint32(o + 4, Endian.little);
    final ni = bd.getUint32(o + 8, Endian.little);
    final h = bd.getFloat32(o + 12, Endian.little);
    o += 16;
    final pos = floats(nv * 3);
    final nrm = floats(nv * 3);
    final uv = floats(nv * 2);
    final tan = floats(nv * 4);
    final idx = List<int>.from(Uint16List.view(buf, o, ni));
    o += ni * 2;
    o += (-ni * 2) % 4;
    out.add(RockScan(
      set,
      h,
      MeshGeometry.fromArrays(positions: pos, normals: nrm, texCoords: uv, tangents: tan, indices: idx),
    ));
  }
  return out;
}
