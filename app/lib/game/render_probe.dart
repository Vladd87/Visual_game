import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// On-device render probe (diagnostic builds): draws each kind of 2D
/// primitive Flutter's UI uses into a small offscreen image, reads the pixels
/// back and logs whether anything came out. A GPU pipeline the driver failed
/// to compile shows up as a blank (or failed) primitive.
///
/// Logged as `LANTERN_PRIM <name> ok|BLANK|ERROR ...` (picked up by the
/// launcher's report).
Future<void> runRenderProbe() async {
  const size = 48.0;
  final r = const Rect.fromLTWH(6, 6, size - 12, size - 12);
  final white = Paint()..color = const Color(0xFFFFFFFF);
  final img = await _solidImage();
  ui.FragmentProgram? program;
  try {
    program = await ui.FragmentProgram.fromAsset('shaders/upscale.frag');
  } catch (e) {
    debugPrint('LANTERN_PRIM runtime-effect-load ERROR $e');
  }
  final tests = <String, void Function(ui.Canvas)>{
    'rect': (c) => c.drawRect(r, white),
    'rrect': (c) => c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), white),
    'rrect-stroke': (c) => c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)),
        Paint()..color = const Color(0xFFFFFFFF)..style = PaintingStyle.stroke..strokeWidth = 3),
    'circle': (c) => c.drawCircle(r.center, 16, white),
    'arc-stroke': (c) => c.drawArc(r, 0, 4, false,
        Paint()..color = const Color(0xFFFFFFFF)..style = PaintingStyle.stroke..strokeWidth = 3),
    'path': (c) => c.drawPath(
        ui.Path()
          ..moveTo(r.left, r.bottom)
          ..lineTo(r.center.dx, r.top)
          ..lineTo(r.right, r.bottom)
          ..close(),
        white),
    'text': (c) {
      final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 28))
        ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)))
        ..addText('WM');
      final p = b.build()..layout(const ui.ParagraphConstraints(width: size));
      c.drawParagraph(p, const Offset(2, 6));
    },
    'linear-gradient': (c) => c.drawRect(
        r, Paint()..shader = ui.Gradient.linear(r.topLeft, r.bottomRight, const [Color(0xFFFFFFFF), Color(0xFF808080)])),
    'radial-gradient': (c) => c.drawRect(
        r, Paint()..shader = ui.Gradient.radial(r.center, 20, const [Color(0xFFFFFFFF), Color(0xFF808080)])),
    'image': (c) => c.drawImageRect(img, const Rect.fromLTWH(0, 0, 4, 4), r, Paint()),
    'save-layer-alpha': (c) {
      c.saveLayer(r, Paint()..color = const Color(0x80FFFFFF));
      c.drawRect(r, white);
      c.restore();
    },
    'blur': (c) => c.drawRect(r, Paint()..color = const Color(0xFFFFFFFF)..imageFilter = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3)),
    'color-filter': (c) => c.drawRect(
        r, Paint()..color = const Color(0xFFFFFFFF)..colorFilter = const ColorFilter.mode(Color(0xFF80FF80), BlendMode.modulate)),
    'clip-rect': (c) {
      c.save();
      c.clipRect(r.deflate(4));
      c.drawRect(r, white);
      c.restore();
    },
    'clip-rrect': (c) {
      c.save();
      c.clipRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)));
      c.drawRect(r, white);
      c.restore();
    },
    'clip-path': (c) {
      c.save();
      c.clipPath(ui.Path()..addOval(r));
      c.drawRect(r, white);
      c.restore();
    },
    'clip-rect-text': (c) {
      c.save();
      c.clipRect(const Rect.fromLTWH(0, 0, size, size));
      final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 28))
        ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)))
        ..addText('WM');
      c.drawParagraph(b.build()..layout(const ui.ParagraphConstraints(width: size)), const Offset(2, 6));
      c.restore();
    },
    'shadow': (c) => c.drawShadow(ui.Path()..addRect(r), const Color(0xFFFFFFFF), 4, false),
    'mask-blur': (c) => c.drawRect(r, Paint()..color = const Color(0xFFFFFFFF)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)),
    if (program != null)
      'runtime-effect': (c) {
        final s = program!.fragmentShader()
          ..setFloat(0, size)
          ..setFloat(1, size)
          ..setFloat(2, 4)
          ..setFloat(3, 4)
          ..setFloat(4, 0)
          ..setFloat(5, 0)
          ..setImageSampler(0, img);
        c.drawRect(r, Paint()..shader = s);
      },
  };
  for (final e in tests.entries) {
    try {
      final rec = ui.PictureRecorder();
      final canvas = ui.Canvas(rec, const Rect.fromLTWH(0, 0, size, size));
      e.value(canvas);
      final pic = rec.endRecording();
      final out = await pic.toImage(size.toInt(), size.toInt());
      final bytes = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
      final n = bytes == null ? -1 : _lit(bytes.buffer.asUint8List());
      debugPrint('LANTERN_PRIM ${e.key} ${n > 20 ? 'ok' : 'BLANK'} lit=$n');
      out.dispose();
      pic.dispose();
    } catch (err) {
      debugPrint('LANTERN_PRIM ${e.key} ERROR $err');
    }
  }
}

/// Logs the average brightness of a rendered 3D frame (diagnostic builds).
Future<void> probe3dImage(ui.Image image) async {
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) {
      debugPrint('LANTERN_3D readback null');
      return;
    }
    final px = bytes.buffer.asUint8List();
    var sum = 0, lit = 0, n = 0;
    for (var i = 0; i < px.length; i += 4 * 97) {
      final l = (px[i] * 2 + px[i + 1] * 5 + px[i + 2]) >> 3;
      sum += l;
      if (l > 8) lit++;
      n++;
    }
    debugPrint('LANTERN_3D ${image.width}x${image.height} meanLuma=${(sum / n).toStringAsFixed(1)} litPct=${(100 * lit / n).toStringAsFixed(1)}');
  } catch (e) {
    debugPrint('LANTERN_3D ERROR $e');
  }
}

int _lit(Uint8List px) {
  var n = 0;
  for (var i = 0; i < px.length; i += 4) {
    if (px[i] > 40 || px[i + 1] > 40 || px[i + 2] > 40) n++;
  }
  return n;
}

Future<ui.Image> _solidImage() {
  final px = Uint8List(4 * 4 * 4)..fillRange(0, 64, 255);
  final c = ui.ImmutableBuffer.fromUint8List(px);
  return c.then((buf) async {
    final desc = ui.ImageDescriptor.raw(buf, width: 4, height: 4, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  });
}
