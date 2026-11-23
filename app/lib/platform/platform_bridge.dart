import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thermal state from Android's PowerManager.
class ThermalState {
  const ThermalState({this.status = 0, this.headroom = -1, this.powerSave = false});

  /// PowerManager.THERMAL_STATUS_* (0 none … 6 shutdown).
  final int status;

  /// getThermalHeadroom(10 s): 1.0 means throttling, < 0 = unavailable.
  final double headroom;
  final bool powerSave;

  static const labels = ['none', 'light', 'moderate', 'severe', 'critical', 'emergency', 'shutdown'];
  String get label => status >= 0 && status < labels.length ? labels[status] : '$status';
}

/// Everything native the game uses. Every call degrades to a no-op on web
/// (captures) or when a channel is missing.
class PlatformBridge {
  PlatformBridge._();
  static final PlatformBridge instance = PlatformBridge._();

  static const _methods = MethodChannel('lantern/platform');
  static const _thermalEvents = EventChannel('lantern/thermal');
  static const _tiltEvents = EventChannel('lantern/tilt');
  static const _displayEvents = EventChannel('lantern/display');

  bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final ValueNotifier<ThermalState> thermal = ValueNotifier(const ThermalState());
  final ValueNotifier<Map<String, Object?>> display = ValueNotifier(const {});

  /// Latest gravity in screen space (x right, y down, z out), in g.
  final ValueNotifier<List<double>> gravity = ValueNotifier(const [0, 0, 1]);

  StreamSubscription<dynamic>? _thermalSub;
  StreamSubscription<dynamic>? _tiltSub;
  StreamSubscription<dynamic>? _displaySub;

  void start() {
    if (!available) return;
    _thermalSub ??= _thermalEvents.receiveBroadcastStream().listen((e) {
      final m = Map<String, Object?>.from(e as Map);
      thermal.value = ThermalState(
        status: (m['status'] as num?)?.toInt() ?? 0,
        headroom: (m['headroom'] as num?)?.toDouble() ?? -1,
        powerSave: m['powerSave'] as bool? ?? false,
      );
    }, onError: (_) {});
    _displaySub ??= _displayEvents.receiveBroadcastStream().listen((e) {
      display.value = Map<String, Object?>.from(e as Map);
    }, onError: (_) {});
  }

  void enableTilt(bool on) {
    if (!available) return;
    if (on) {
      _tiltSub ??= _tiltEvents.receiveBroadcastStream().listen((e) {
        final v = (e as List).cast<num>();
        gravity.value = [v[0].toDouble(), v[1].toDouble(), v[2].toDouble()];
      }, onError: (_) {});
    } else {
      _tiltSub?.cancel();
      _tiltSub = null;
    }
  }

  Future<double> setRefreshRate(double hz) async {
    if (!available) return 0;
    try {
      return (await _methods.invokeMethod<double>('setRefreshRate', {'hz': hz})) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> haptic(double strength) async {
    if (!available) return;
    try {
      await _methods.invokeMethod('haptic', {'strength': strength});
    } catch (_) {
      await HapticFeedback.lightImpact();
    }
  }

  /// Diagnostic modes picked on the crash/stall report screen:
  /// plainMaterials, noEffects, no3d.
  Future<Map<String, bool>> launchFlags() async {
    if (!available) return const {};
    try {
      final m = await _methods.invokeMapMethod<String, Object?>('launchFlags');
      return {for (final e in (m ?? const {}).entries) e.key: e.value == true};
    } catch (_) {
      return const {};
    }
  }

  /// Records a boot step natively (synchronously committed), so a launch that
  /// hangs and is swiped away can still be reported on the next start.
  void reportStep(String step) {
    if (!available) return;
    _methods.invokeMethod('bootStep', {'step': step}).catchError((_) => null);
  }

  /// Device bring-up: reads back what the phone shows (Flutter's surface and
  /// the window) and returns a one-line summary.
  Future<String?> screenProbe(String step) async {
    if (!available) return null;
    try {
      return await _methods.invokeMethod<String>('screenProbe', {'step': step});
    } catch (e) {
      return 'probe error $e';
    }
  }

  /// Bring-up auto test: this run's label ("run k/n"), or null.
  Future<String?> autoLabel() async {
    if (!available) return null;
    try {
      return await _methods.invokeMethod<String>('autoLabel');
    } catch (_) {
      return null;
    }
  }

  /// Bring-up auto test: hand over to the next run (the launcher restarts
  /// the game in the next mode).
  void nextRun() {
    if (!available) return;
    _methods.invokeMethod('nextRun').catchError((_) => null);
  }

  /// Appends a line to the launcher's history of test runs.
  void recordRun(String line) {
    if (!available) return;
    _methods.invokeMethod('recordRun', {'line': line}).catchError((_) => null);
  }

  Future<String?> perfLogDir() async {
    if (!available) return null;
    try {
      return await _methods.invokeMethod<String>('perfLogDir');
    } catch (_) {
      return null;
    }
  }

  Future<void> reassertImmersive() async {
    if (!available) return;
    try {
      await _methods.invokeMethod('immersive');
    } catch (_) {}
  }
}
