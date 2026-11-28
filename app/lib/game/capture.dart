import '../sim/autopilot.dart';
import '../sim/course.dart';
import '../sim/vec2.dart';
import '../sim/world.dart';
import 'capture_signal_stub.dart' if (dart.library.js_interop) 'capture_signal_web.dart' as signal;

/// Deterministic capture mode for the builder/critic loop (PLAN.md §5).
///
/// Enabled on web with `?capture=<shot>` (1..8). Optional `seed`, `hinge=1`
/// (simulate the inner-screen hinge), `frames` (settle frames).
class CaptureConfig {
  CaptureConfig({required this.shot, required this.seed, required this.hinge, required this.settleFrames});

  final int shot;
  final int seed;
  final bool hinge;
  final int settleFrames;

  static CaptureConfig? fromUri(Uri uri) {
    final q = uri.queryParameters;
    final shot = int.tryParse(q['capture'] ?? '');
    if (shot == null) return null;
    return CaptureConfig(
      shot: shot.clamp(1, 8),
      seed: int.tryParse(q['seed'] ?? '') ?? 2026,
      hinge: q['hinge'] == '1',
      settleFrames: int.tryParse(q['frames'] ?? '') ?? 90,
    );
  }

  static const shotNames = [
    'opening reach, wide',
    'lantern beside foaming rocks',
    'firefly cluster close pass',
    'heavy rain on open water',
    'moss bank and ferns',
    'collision moment (flame dipped)',
    'misty narrows',
    'end pool, fireflies rising',
  ];

  String get name => shotNames[shot - 1];

  /// Steps [w] with the autopilot until this shot's moment (or a time cap).
  void advanceToShot(World w) {
    final ap = Autopilot();
    bool step() {
      w.step(ap.input(w));
      return w.phase == RunPhase.running || shot == 8;
    }

    double sectionStart(String name) => w.course.sections.firstWhere((s) => s.spec.name == name).startD;
    final cap = 420.0;
    switch (shot) {
      case 1:
        while (w.time < 7.0 && step()) {}
      // M11: shots 2, 3 and 6 stand at fixed distances down the stream: where
      // their M10 event rules (a rock within reach in the rock garden, two
      // fireflies close by, the first collision) put them on the M10 course
      // (captures/round-40). The bigger lantern changes the rock gaps and the
      // autopilot's path, so the event rules chose other places and the
      // paired comparison with the baseline lost its matching moments.
      case 2:
        while (w.lantern.pos.y < 7.35 && w.time < cap && step()) {}
      case 3:
        while (w.lantern.pos.y < 3.59 && w.time < cap && step()) {}
      case 4:
        final d = sectionStart('rain meadow') + 3.0;
        while (w.lantern.pos.y < d && w.time < cap && step()) {}
      case 5:
        final d = sectionStart('fern tunnel') + 2.5;
        while (w.lantern.pos.y < d && w.time < cap && step()) {}
      case 6:
        while (w.lantern.pos.y < 7.37 && w.time < cap && step()) {}
      case 7:
        final d = sectionStart('misty narrows') + 3.0;
        while (w.lantern.pos.y < d && w.time < cap && step()) {}
      case 8:
        while (w.time < cap) {
          w.step(ap.input(w));
          if (w.phase == RunPhase.won && w.time > w.endedAt + 4.5) break;
          if (w.phase == RunPhase.lost) break;
        }
    }
    w.drainEvents();
  }

  void signalReady(String info) => signal.signalReady(info);
}

/// Used by tests and the harness to sanity-check a course for shots.
V2 courseStart(Course c) => V2(c.centerX(0.6), 0.6);
