import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/quality_governor.dart';

enum ControlMode { drag, tilt }

/// Persisted player settings and best run.
class Settings extends ChangeNotifier {
  ControlMode control = ControlMode.drag;
  bool haptics = true;
  // M10: sound level, 0 = off.
  double volume = 0.8;
  QualityPreset quality = QualityPreset.high;
  bool performance120 = false;
  bool showPerf = false;

  int bestFireflies = 0;
  double bestTime = 0; // seconds, for the best run
  double bestFlame = 0;

  SharedPreferences? _prefs;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = p;
      control = ControlMode.values[(p.getInt('control') ?? 0).clamp(0, ControlMode.values.length - 1)];
      haptics = p.getBool('haptics') ?? true;
      volume = p.getDouble('volume') ?? 0.8;
      quality = QualityPreset.values[(p.getInt('quality') ?? 0).clamp(0, QualityPreset.values.length - 1)];
      performance120 = p.getBool('perf120') ?? false;
      bestFireflies = p.getInt('bestFireflies') ?? 0;
      bestTime = p.getDouble('bestTime') ?? 0;
      bestFlame = p.getDouble('bestFlame') ?? 0;
    } catch (_) {
      // Storage unavailable (e.g. some web contexts): run with defaults.
    }
    notifyListeners();
  }

  void update(void Function(Settings s) change) {
    change(this);
    final p = _prefs;
    if (p != null) {
      p.setInt('control', control.index);
      p.setBool('haptics', haptics);
      p.setDouble('volume', volume);
      p.setInt('quality', quality.index);
      p.setBool('perf120', performance120);
    }
    notifyListeners();
  }

  /// Records a finished run; returns true if it is a new best.
  bool submitRun({required bool won, required int fireflies, required double time, required double flame}) {
    if (!won) return false;
    final better = fireflies > bestFireflies ||
        (fireflies == bestFireflies && (flame > bestFlame + 1e-6 || (flame == bestFlame && (bestTime == 0 || time < bestTime))));
    if (!better) return false;
    bestFireflies = fireflies;
    bestTime = time;
    bestFlame = flame;
    final p = _prefs;
    if (p != null) {
      p.setInt('bestFireflies', fireflies);
      p.setDouble('bestTime', time);
      p.setDouble('bestFlame', flame);
    }
    notifyListeners();
    return true;
  }
}
