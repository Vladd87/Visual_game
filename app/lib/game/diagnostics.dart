import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show GlobalKey;

import '../platform/platform_bridge.dart';
import 'boot_journal_stub.dart' if (dart.library.io) 'boot_journal_io.dart' as journal;

/// On-device diagnostics, for crashes nobody can reproduce off the phone.
///
/// * A boot journal: each startup step is written (synchronously, flushed)
///   before it runs and `ready` once frames are flowing. If the process dies
///   on the way, the next launch finds the journal stuck at that step, says
///   so on screen and starts with [safeRender] on (plain materials).
/// * Errors: framework and uncaught async errors are kept in [lastError]
///   and shown on screen, so a screenshot is enough to report them.
class Diagnostics {
  Diagnostics._();

  /// Step at which the previous launch stopped, if it never became ready.
  static String? previousStall;

  /// Plain PBR materials instead of the custom shaders (set after a stall
  /// in a rendering step).
  static bool safeRender = false;

  /// Diagnostic mode: no TAA, AO, fog, shadows, planar reflection or custom
  /// upscale (the scene is presented directly).
  static bool noEffects = false;

  /// Diagnostic mode: no 3D view at all (checks that Flutter itself draws).
  static bool no3d = false;

  /// Diagnostic mode: no flutter_scene / Flutter GPU work at all (no GPU
  /// context, no textures, no environment); the title UI over a flat colour.
  static bool noScene = false;

  /// Device bring-up: each boot step is held on screen for a moment under a
  /// bright banner with a live frame counter, and the phone reads back what
  /// it actually shows (see [checkpoint]).
  static bool stepByStep = false;

  /// Labels of the Android-side presentation modes (set by the launcher).
  static bool textureView = false;

  /// Bring-up: hold each loading step for 1.2 s and read the screen back at
  /// it (otherwise loading runs at full speed and only the title screen is
  /// checked).
  static bool slowSteps = false;

  /// Bring-up: part of the launcher's automatic test series; [autoLabel] is
  /// "run k/n". The run hands over to the next one when its checks are done.
  static bool auto = false;
  static String autoLabel = '';

  /// Bring-up: 0 = the real water material, k = bring-up variant k
  /// (assets/materials/bringup/water_vk.fmat), to find which material
  /// feature fails on the phone's GPU.
  static int waterVariant = 0;

  /// Bring-up experiment: the 3D view is taken off screen while this is set.
  static final ValueNotifier<bool> hide3d = ValueNotifier(false);

  /// Bring-up experiment: which pieces of the title screen are shown.
  static final ValueNotifier<UiStage> uiStage = ValueNotifier(UiStage.full);

  /// Bring-up: the whole game page, rendered offscreen by [probe] for
  /// comparison with what the screen shows.
  static final GlobalKey rootKey = GlobalKey();

  static void applyLaunchFlags(Map<String, bool> f) {
    if (f['plainMaterials'] == true) safeRender = true;
    if (f['noEffects'] == true) noEffects = true;
    if (f['no3d'] == true) no3d = true;
    if (f['noScene'] == true) noScene = true;
    if (f['stepByStep'] == true) stepByStep = true;
    if (f['slowSteps'] == true) slowSteps = true;
    if (f['auto'] == true) auto = true;
    if (f['textureView'] == true) textureView = true;
    if (stepByStep) SchedulerBinding.instance.addTimingsCallback(_countFrames);
  }

  static String get modeLabel => [
        if (safeRender) 'plain materials',
        if (noEffects) 'no effects',
        if (no3d) 'no 3D',
        if (noScene) 'no scene',
        if (textureView) 'texture view',
        if (slowSteps) 'slow load',
        if (waterVariant > 0) 'water v$waterVariant',
      ].join(', ');

  static String get modeName => modeLabel.isEmpty ? 'default' : modeLabel;

  /// The step shown on the bring-up banner.
  static final ValueNotifier<String> visibleStep = ValueNotifier('start');

  static int _rasterFrames = 0;
  static double _lastRasterMs = 0;
  static void _countFrames(List<FrameTiming> timings) {
    _rasterFrames += timings.length;
    if (timings.isNotEmpty) _lastRasterMs = timings.last.rasterDuration.inMicroseconds / 1000;
  }

  /// Boot step [name]: recorded like [step]. In [stepByStep] runs it is also
  /// shown on the banner, and with [slowSteps] held on screen for 1.2 s while
  /// frames keep flowing and then read back (see [probe]).
  static Future<void> checkpoint(String name) async {
    step(name);
    if (!stepByStep) return;
    visibleStep.value = name;
    if (slowSteps) await probe(name);
  }

  static final List<String> _summary = [];

  /// Lit share of the loading screen read just before the title (-1 unknown).
  static int lastLoadingLit = -1;

  /// Waits [wait], then reads back what the phone shows (Flutter's surface or
  /// texture, and the window) and logs it with the frames rasterized meanwhile.
  /// Returns the share of lit pixels in Flutter's layer (-1 if unknown).
  static Future<int> probe(String name, {Duration wait = const Duration(milliseconds: 1200)}) async {
    visibleStep.value = name;
    final before = _rasterFrames;
    await Future<void>.delayed(wait);
    final pix = await PlatformBridge.instance.screenProbe(name);
    final line = '$name: frames+${_rasterFrames - before} raster=${_lastRasterMs.toStringAsFixed(1)}ms ${pix ?? 'no probe'}';
    debugPrint('LANTERN_CHECK $line');
    final m = RegExp(r'(?:surface|texture)=L=[\d.]+ A=\d+ lit=(\d+)%').firstMatch(pix ?? '');
    final lit = m == null ? -1 : int.parse(m.group(1)!);
    final off = await _offscreenLit();
    debugPrint('LANTERN_CHECK $name offscreen=${off < 0 ? '?' : '$off%'}');
    _summary.add('$name ${lit < 0 ? '?' : '$lit%'}${off < 0 ? '' : ' (off $off%)'}');
    if (!auto) PlatformBridge.instance.recordRun('$line offscreen=$off%');
    return lit;
  }

  /// The same page rendered offscreen (Picture.toImage path): share of lit
  /// pixels, -1 if not available.
  static Future<int> _offscreenLit() async {
    try {
      final ro = rootKey.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) return -1;
      final img = await ro.toImage(pixelRatio: 0.15);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      if (bytes == null) return -1;
      final px = bytes.buffer.asUint8List();
      var lit = 0, n = 0;
      for (var i = 0; i + 3 < px.length; i += 4) {
        final l = (px[i] * 2 + px[i + 1] * 5 + px[i + 2]) >> 3;
        if (l > 8) lit++;
        n++;
      }
      return n == 0 ? -1 : 100 * lit ~/ n;
    } catch (e) {
      debugPrint('LANTERN_CHECK offscreen error $e');
      return -1;
    }
  }

  /// Waits until [n] more frames have been drawn.
  static Future<void> frames(int n) async {
    for (var i = 0; i < n; i++) {
      await SchedulerBinding.instance.endOfFrame;
      SchedulerBinding.instance.scheduleFrame();
    }
  }

  /// Samples a frame's luma (every 7th pixel), or null.
  static Future<List<double>?> _lumaSamples(ui.Image? img) async {
    if (img == null) return null;
    final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) return null;
    final px = bytes.buffer.asUint8List();
    final out = <double>[];
    for (var i = 0; i + 3 < px.length; i += 4 * 7) {
      out.add((px[i] * 2 + px[i + 1] * 5 + px[i + 2]) / 8);
    }
    return out;
  }

  /// Device bring-up: switches each effect off in turn and measures how much
  /// the 3D frame changes (mean absolute luma difference, 0-255). An effect
  /// that changes the frame in the browser but not on the phone is not
  /// working on the phone. [frame] returns the latest 3D frame.
  static Future<String> effectsProbe(Map<String, void Function(bool on)> toggles, ui.Image? Function() frame) async {
    const settle = 16; // TAA history needs a few frames to converge
    visibleStep.value = 'effects';
    await frames(settle);
    final base = await _lumaSamples(frame());
    if (base == null) return 'FX: no 3D frame';
    final mean = base.reduce((a, b) => a + b) / base.length;
    final parts = <String>['mean ${mean.toStringAsFixed(1)}'];
    for (final e in toggles.entries) {
      visibleStep.value = 'effects: ${e.key} off';
      e.value(false);
      await frames(settle);
      final off = await _lumaSamples(frame());
      e.value(true);
      if (off == null || off.length != base.length) {
        parts.add('${e.key} ?');
      } else {
        var d = 0.0, signed = 0.0;
        for (var i = 0; i < base.length; i++) {
          d += (base[i] - off[i]).abs();
          signed += base[i] - off[i];
        }
        parts.add('${e.key} ${(d / base.length).toStringAsFixed(2)}${signed >= 0 ? '+' : '-'}');
      }
      await frames(settle);
    }
    final line = 'FX: ${parts.join(' · ')}';
    debugPrint('LANTERN_FX $line');
    return line;
  }

  /// One line for the launcher's history: every probe of this run and a verdict.
  static void recordSummary(String verdict) {
    final head = auto ? 'RUN $autoLabel [$modeName]' : '[$modeName]';
    PlatformBridge.instance.recordRun('$head: ${_summary.join(' · ')} => $verdict');
  }

  static final ValueNotifier<String?> lastError = ValueNotifier(null);

  static const _renderSteps = {'gpu', 'scene', 'materials', 'textures', 'rocks', 'environment', 'course', 'frames'};

  static void init() {
    final prev = journal.read();
    if (prev != null && prev.isNotEmpty && prev != 'ready') {
      previousStall = prev;
      safeRender = _renderSteps.contains(prev);
    }
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      report('${details.exceptionAsString()}\n${details.stack ?? ''}');
      previousOnError?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report('$error\n$stack');
      return true;
    };
  }

  /// Records that boot is entering [step].
  static void step(String step) {
    journal.write(step);
    debugPrint('LANTERN_STEP $step');
    PlatformBridge.instance.reportStep(step);
  }

  static void report(String text) {
    debugPrint('LANTERN_ERROR $text');
    final lines = text.split('\n');
    lastError.value = lines.take(14).join('\n');
  }

  /// Text for the on-screen panel, or null when there is nothing to say.
  static String? panelText(String? error) {
    final parts = <String>[];
    if (previousStall != null) {
      parts.add('The last launch stopped during "$previousStall".'
          '${safeRender ? ' Starting with plain materials (safe mode).' : ''}');
    }
    if (modeLabel.isNotEmpty) parts.add('Diagnostic mode: $modeLabel.');
    if (error != null) parts.add(error);
    if (parts.isEmpty) return null;
    return '${parts.join('\n\n')}\n\nA screenshot of this is enough to report it.';
  }
}

/// Bring-up: title-screen variants, to find which piece blanks the screen.
enum UiStage {
  full('title'),
  noCard('no card'),
  noGame('no 3D'),
  bannerOnly('banner only'),
  plainCard('plain card'),
  cardNoStretch('card, no stretch'),
  loadingLook('loading look');

  const UiStage(this.label);
  final String label;

  bool get hideGame => this != full && this != noCard;
  bool get hideCard => this == noCard || this == bannerOnly || this == loadingLook;
}
