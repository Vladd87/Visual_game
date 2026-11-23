import '../game/diagnostics.dart';
import '../game/render_probe.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';

/// Renders the 3D scene at an internal resolution into a [RenderTexture] and
/// presents it at native resolution through `shaders/upscale.frag`
/// (Catmull-Rom upscale + contrast-adaptive sharpen + TPDF dither).
///
/// Changing the internal resolution only resizes the off-screen target; the
/// display surface is never touched. While a resized target has not rendered
/// yet, the last completed frame keeps being drawn (stretched), so a fold or a
/// governor step never shows a blank frame.
class ScenePresenter extends StatefulWidget {
  const ScenePresenter({
    super.key,
    required this.scene,
    required this.cameraFor,
    required this.onTick,
    required this.renderScale,
    this.sharpen = 0.55,
  });

  final Scene scene;

  /// Camera for the current frame, given the viewport aspect.
  final Camera Function(double aspect) cameraFor;
  final void Function(double dt) onTick;
  final double renderScale;
  final double sharpen;

  @override
  State<ScenePresenter> createState() => _ScenePresenterState();
}

class _ScenePresenterState extends State<ScenePresenter> {
  /// Device bring-up: the last 3D frame drawn, for the effects probe.
  static ui.Image? latestFrame;

  static ui.FragmentProgram? _program;
  RenderTexture? _rt;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  double _aspect = 1;

  @override
  void initState() {
    super.initState();
    if (_program == null) {
      ui.FragmentProgram.fromAsset('shaders/upscale.frag').then((p) {
        _program = p;
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final size = c.biggest;
      final w = math.max(16, (size.width * dpr * widget.renderScale).round());
      final h = math.max(16, (size.height * dpr * widget.renderScale).round());
      _aspect = size.width / math.max(1, size.height);
      _rt ??= RenderTexture(width: w, height: h);
      _rt!.resize(w, h);
      final rt = _rt!;
      return Stack(fit: StackFit.expand, children: [
        // Drives the scene into the internal-resolution target; draws nothing itself.
        SceneView(
          widget.scene,
          viewsBuilder: (_) => [RenderView(camera: widget.cameraFor(_aspect), target: rt)],
          onTick: (elapsed, dt) {
            widget.onTick(dt);
            _frame.value++;
          },
        ),
        if (_program != null)
          CustomPaint(painter: _UpscalePainter(rt, _program!, _frame, dpr, widget.sharpen)),
      ]);
    });
  }
}

/// Device bring-up: the last 3D frame the presenter drew (null before the first).
ui.Image? latestSceneFrame() => _ScenePresenterState.latestFrame;

class _UpscalePainter extends CustomPainter {
  _UpscalePainter(this.rt, this.program, this.tick, this.dpr, this.sharpen) : super(repaint: tick);

  final RenderTexture rt;
  final ui.FragmentProgram program;
  final ValueNotifier<int> tick;
  final double dpr;
  final double sharpen;

  static bool _firstPaint = true;
  static int _paints = 0;

  @override
  void paint(Canvas canvas, Size size) {
    final tex = rt.texture;
    if (tex == null) return;
    if (_firstPaint) {
      _firstPaint = false;
      Diagnostics.step('first 3D paint');
    }
    final img = tex.asImage();
    _ScenePresenterState.latestFrame = img;
    // Bring-up on new hardware: log what the 3D target actually contains.
    if (++_paints == 30) probe3dImage(img);
    final shader = program.fragmentShader()
      ..setFloat(0, size.width * dpr)
      ..setFloat(1, size.height * dpr)
      ..setFloat(2, img.width.toDouble())
      ..setFloat(3, img.height.toDouble())
      ..setFloat(4, sharpen)
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
