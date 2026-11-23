import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

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
  static bool opaqueSurface = false;
  static bool textureView = false;

  static void applyLaunchFlags(Map<String, bool> f) {
    if (f['plainMaterials'] == true) safeRender = true;
    if (f['noEffects'] == true) noEffects = true;
    if (f['no3d'] == true) no3d = true;
    if (f['noScene'] == true) noScene = true;
    if (f['stepByStep'] == true) stepByStep = true;
    if (f['opaqueSurface'] == true) opaqueSurface = true;
    if (f['textureView'] == true) textureView = true;
    if (stepByStep) SchedulerBinding.instance.addTimingsCallback(_countFrames);
  }

  static String get modeLabel => [
        if (safeRender) 'plain materials',
        if (noEffects) 'no effects',
        if (no3d) 'no 3D',
        if (noScene) 'no scene',
        if (opaqueSurface) 'old opaque surface',
        if (textureView) 'texture view',
      ].join(', ');

  /// The step shown on the bring-up banner.
  static final ValueNotifier<String> visibleStep = ValueNotifier('start');

  static int _rasterFrames = 0;
  static double _lastRasterMs = 0;
  static void _countFrames(List<FrameTiming> timings) {
    _rasterFrames += timings.length;
    if (timings.isNotEmpty) _lastRasterMs = timings.last.rasterDuration.inMicroseconds / 1000;
  }

  /// Boot step [name]: recorded like [step]; in [stepByStep] mode also held
  /// on screen for 1.2 s while frames keep flowing, then the phone reads back
  /// its own screen (Flutter's surface and the window above it), and the
  /// result goes to the log and the launcher's run history.
  static Future<void> checkpoint(String name) async {
    step(name);
    if (!stepByStep) return;
    visibleStep.value = name;
    final before = _rasterFrames;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final pix = await PlatformBridge.instance.screenProbe(name);
    final line = '$name: frames+${_rasterFrames - before} raster=${_lastRasterMs.toStringAsFixed(1)}ms ${pix ?? 'no probe'}';
    debugPrint('LANTERN_CHECK $line');
    PlatformBridge.instance.recordRun(line);
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
