import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../platform/platform_bridge.dart';

/// User-selectable preset. High is the game; Medium/Low are thermal fallbacks.
enum QualityPreset { high, medium, low }

/// Rolling frame statistics.
class FrameStats {
  final List<double> _ms = [];
  final List<double> _t = [];

  void add(double nowSec, double frameMs) {
    _ms.add(frameMs);
    _t.add(nowSec);
    while (_t.isNotEmpty && nowSec - _t.first > 10) {
      _t.removeAt(0);
      _ms.removeAt(0);
    }
  }

  int get count => _ms.length;

  double percentile(double p) {
    if (_ms.isEmpty) return 0;
    final s = List<double>.of(_ms)..sort();
    return s[math.min(s.length - 1, (p * (s.length - 1)).round())];
  }

  double get max => _ms.isEmpty ? 0 : _ms.reduce(math.max);

  /// Frames per second over the last second.
  double fps(double nowSec) {
    var n = 0;
    for (var i = _t.length - 1; i >= 0 && nowSec - _t[i] <= 1.0; i--) {
      n++;
    }
    return n.toDouble();
  }
}

/// Steps internal resolution (then, from later milestones, effects) down and
/// back up from frame timing and Android thermal headroom. One notch at a
/// time, never more often than [cooldown], with hysteresis, so changes are
/// gradual and hidden by TAA (PLAN.md §3 "Thermal governor").
class QualityGovernor extends ChangeNotifier {
  QualityGovernor({this.cooldown = 8.0});

  final double cooldown;
  QualityPreset preset = QualityPreset.high;
  double targetHz = 60;

  /// Base scale for the current screen profile.
  double baseScale = 0.7;

  /// Notches below the base (each notch = -0.05 render scale).
  int notch = 0;
  static const int maxScaleNotches = 3;
  double _lastChange = -1e9;
  bool adaptive = true;

  double get presetScale => switch (preset) {
        QualityPreset.high => 1.0,
        QualityPreset.medium => 0.86,
        QualityPreset.low => 0.72,
      };

  double get renderScale => math.max(0.4, (baseScale - notch * 0.05) * presetScale);

  void setBase(double scale) {
    if ((scale - baseScale).abs() > 1e-6) {
      baseScale = scale;
      notifyListeners();
    }
  }

  /// Feed once per frame.
  void evaluate(double nowSec, FrameStats stats, ThermalState thermal) {
    if (!adaptive || stats.count < 60 || nowSec - _lastChange < cooldown) return;
    final budgetMs = 1000 / targetHz;
    final p95 = stats.percentile(0.95);
    final hot = thermal.status >= 3 || (thermal.headroom >= 0 && thermal.headroom > 0.85);
    final warm = thermal.status >= 2 || (thermal.headroom >= 0 && thermal.headroom > 0.7);
    final slow = p95 > budgetMs * 0.95;
    final cool = thermal.status <= 1 && (thermal.headroom < 0 || thermal.headroom < 0.55);
    final fast = p95 < budgetMs * 0.75;
    if ((hot || slow || (warm && p95 > budgetMs * 0.85)) && notch < maxScaleNotches) {
      notch++;
      _lastChange = nowSec;
      notifyListeners();
    } else if (cool && fast && notch > 0 && nowSec - _lastChange > cooldown * 2) {
      notch--;
      _lastChange = nowSec;
      notifyListeners();
    }
  }
}
