import 'package:flutter/foundation.dart';

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
  static void step(String step) => journal.write(step);

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
    if (error != null) parts.add(error);
    if (parts.isEmpty) return null;
    return '${parts.join('\n\n')}\n\nA screenshot of this is enough to report it.';
  }
}
