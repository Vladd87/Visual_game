import 'diagnostics.dart';
import 'render_probe.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming, Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart';

import '../platform/platform_bridge.dart';
import '../render/camera_rig.dart';
import '../render/game_scene.dart';
import '../render/quality_governor.dart';
import '../sim/vec2.dart';
import '../sim/world.dart';
import 'capture.dart';
import 'file_writer_stub.dart' if (dart.library.io) 'file_writer_io.dart';
import 'settings.dart';

enum AppPhase { loading, title, playing, paused, results }

/// Owns the run: simulation, scene, camera, input, quality and platform glue.
class GameController extends ChangeNotifier {
  GameController({this.capture});

  final CaptureConfig? capture;
  final Settings settings = Settings();
  final QualityGovernor governor = QualityGovernor();
  final FrameStats stats = FrameStats();
  final CameraRig rig = CameraRig();
  final PlatformBridge platform = PlatformBridge.instance;

  late final Scene scene;
  late final GameScene gameScene;
  World? world;
  WorldClock? _clock;
  AppPhase phase = AppPhase.loading;
  String loadingText = 'warming up';
  String pauseReason = '';
  bool newBest = false;

  // Input.
  V2 _drag = V2.zero;
  List<double> _tiltNeutral = const [0, 0, 1];
  V2 get input => settings.control == ControlMode.tilt ? _tiltInput() : _drag;

  // Timing.
  double _realTime = 0;
  int _captureFrames = 0;
  Camera? _camera;
  ViewportInfo? _viewport;
  final List<String> _perfLog = ['t,fps,p95_ms,max_ms,scale,notch,thermal,headroom,profile,refresh'];
  double _lastLog = 0;
  double lastBuildMs = 0, lastRasterMs = 0;

  Future<void> boot() async {
    try {
      await _boot();
    } catch (e, st) {
      Diagnostics.report('Startup failed: $e\n$st');
    }
  }

  int _framesSinceBoot = 0;

  Future<void> _boot() async {
    Diagnostics.step('settings');
    Diagnostics.applyLaunchFlags(await platform.launchFlags());
    if (Diagnostics.auto) Diagnostics.autoLabel = await platform.autoLabel() ?? '';
    // Bring-up on new hardware: which 2D primitives render (logged).
    if (Diagnostics.stepByStep && !Diagnostics.auto) platform.recordRun('=== mode: ${Diagnostics.modeName}');
    if (platform.available || Uri.base.queryParameters['probe'] == '1') {
      Diagnostics.step('render probe');
      await runRenderProbe();
    }
    await settings.load();
    governor.preset = settings.quality;
    governor.adaptive = capture == null;
    loadingText = 'loading the stream';
    notifyListeners();
    if (!Diagnostics.noScene) {
      await Diagnostics.checkpoint('gpu');
      await Scene.initializeStaticResources();
      await Scene.preload();
      await Diagnostics.checkpoint('scene');
      scene = Scene();
      gameScene = GameScene(scene)..buildStatic();
      loadingText = 'filling the stream';
      notifyListeners();
      await gameScene.loadAssets();
    } else {
      await Diagnostics.checkpoint('no scene');
    }
    platform.start();
    platform.enableTilt(settings.control == ControlMode.tilt);
    unawaited(platform.setRefreshRate(settings.performance120 ? 120 : 60));
    governor.targetHz = settings.performance120 ? 120 : 60;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);

    await Diagnostics.checkpoint('course');
    // The loading screen as the phone shows it, just before the title.
    if (Diagnostics.stepByStep) Diagnostics.lastLoadingLit = await Diagnostics.probe('loading', wait: const Duration(milliseconds: 400));
    final cap = capture;
    if (cap != null) {
      final w = World(cap.seed);
      cap.advanceToShot(w);
      _install(w);
      phase = AppPhase.playing; // frozen: capture mode never steps the sim
    } else {
      _install(World(_newSeed()));
      phase = AppPhase.title;
    }
    Diagnostics.step('frames');
    // With the 3D view off nothing ticks, so the UI drawing is the success.
    if (Diagnostics.no3d || Diagnostics.noScene) Diagnostics.step('ready');
    notifyListeners();
    if (Diagnostics.stepByStep) unawaited(_afterBootChecks());
  }

  /// Device bring-up: what the title screen actually shows, then the same
  /// screen piece by piece (see [UiStage]): the first variant that shows
  /// again names the piece that blanks the screen. The offscreen render of
  /// each variant tells "only on-screen drawing fails" from "it never draws".
  Future<void> _afterBootChecks() async {
    final loading = Diagnostics.lastLoadingLit;
    final results = <String>[];
    Future<void> stage(UiStage s, String name, {int ms = 900}) async {
      Diagnostics.uiStage.value = s;
      final lit = await Diagnostics.probe(name, wait: Duration(milliseconds: ms));
      results.add('$name ${lit < 0 ? '?' : (lit >= 5 ? 'shows' : 'BLACK')}');
    }
    await stage(UiStage.full, 'title', ms: 1500);
    await stage(UiStage.noCard, 'no card');
    await stage(UiStage.noGame, 'no 3D');
    await stage(UiStage.bannerOnly, 'banner only');
    await stage(UiStage.plainCard, 'plain card');
    await stage(UiStage.cardNoStretch, 'card no stretch');
    await stage(UiStage.loadingLook, 'loading look');
    await stage(UiStage.full, 'title again', ms: 1200);
    Diagnostics.visibleStep.value = 'done';
    Diagnostics.recordSummary('loading ${loading >= 5 ? 'shows' : 'BLACK'}; ${results.join(', ')}');
    if (Diagnostics.auto) platform.nextRun();
  }

  int _newSeed() => DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;

  void _install(World w) {
    world = w;
    _clock = WorldClock(w);
    if (!Diagnostics.noScene) gameScene.buildCourse(w);
    rig.snapTo(w.lantern.pos);
  }

  // --- run lifecycle ----------------------------------------------------------

  void startRun() {
    final w = (phase == AppPhase.title && world != null && world!.time == 0) ? world! : World(_newSeed());
    if (!identical(w, world)) _install(w);
    newBest = false;
    recalibrateTilt();
    phase = AppPhase.playing;
    notifyListeners();
  }

  void pause(String reason) {
    if (phase != AppPhase.playing || capture != null) return;
    phase = AppPhase.paused;
    pauseReason = reason;
    _drag = V2.zero;
    notifyListeners();
  }

  void resume() {
    if (phase != AppPhase.paused) return;
    phase = AppPhase.playing;
    recalibrateTilt();
    notifyListeners();
  }

  void toTitle() {
    _install(World(_newSeed()));
    phase = AppPhase.title;
    notifyListeners();
  }

  // --- viewport (fold / unfold / flex) ----------------------------------------

  void setViewport(ViewportInfo info) {
    final prev = _viewport;
    _viewport = info;
    final prevProfile = rig.profile;
    rig.setViewport(info);
    governor.setBase(rig.framing.renderScale);
    if (prev != null && prevProfile != rig.profile) {
      // A screen switch keeps the run but soft-pauses it (PLAN.md decisions);
      // Flex mode keeps playing with the panel below.
      if (rig.profile != ScreenProfile.flex && prevProfile != ScreenProfile.flex) {
        pause('screen switched');
      }
      recalibrateTilt();
    }
  }

  // --- input -------------------------------------------------------------------

  /// Drag offset from the touch-down point, in logical px.
  void setDrag(Offset delta, double reachPx) {
    final v = V2(delta.dx, delta.dy) / reachPx;
    _drag = v.clampLength(1);
  }

  void endDrag() => _drag = V2.zero;

  void recalibrateTilt() => _tiltNeutral = List.of(platform.gravity.value);

  V2 _tiltInput() {
    final g = platform.gravity.value;
    final dx = g[0] - _tiltNeutral[0];
    final dy = g[1] - _tiltNeutral[1];
    var v = V2(dx, dy) / 0.26; // ~15 degrees of tilt for a full nudge
    if (v.length < 0.08) return V2.zero;
    return v.clampLength(1);
  }

  void setControl(ControlMode m) {
    settings.update((s) => s.control = m);
    platform.enableTilt(m == ControlMode.tilt);
    recalibrateTilt();
  }

  void setQuality(QualityPreset q) {
    settings.update((s) => s.quality = q);
    governor.preset = q;
    governor.notifyListeners();
  }

  void setPerformance120(bool on) {
    settings.update((s) => s.performance120 = on);
    governor.targetHz = on ? 120 : 60;
    unawaited(platform.setRefreshRate(on ? 120 : 60));
  }

  // --- frame -------------------------------------------------------------------

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      lastBuildMs = t.buildDuration.inMicroseconds / 1000;
      lastRasterMs = t.rasterDuration.inMicroseconds / 1000;
    }
  }

  Camera cameraFor(double aspect) => _camera ?? rig.update(0, world!.lantern.pos, aspect);

  void onTick(double dt, double aspect) {
    final w = world;
    if (w == null) return;
    // Heartbeat for the first frames; a second of frames means this launch
    // is good.
    if (_framesSinceBoot < 60) {
      _framesSinceBoot++;
      if (_framesSinceBoot == 1) Diagnostics.step('frame 1');
      if (_framesSinceBoot == 10) Diagnostics.step('frame 10');
      if (_framesSinceBoot == 60) Diagnostics.step('ready');
    }
    _realTime += dt;
    stats.add(_realTime, dt * 1000);
    final cap = capture;
    if (cap != null) {
      // Frozen sim; let temporal effects settle, then tell the harness.
      _captureFrames++;
      gameScene.update(0, w.time);
      _camera = rig.update(1 / 60, w.lantern.pos, aspect);
      if (_captureFrames == cap.settleFrames) {
        cap.signalReady('shot=${cap.shot} t=${w.time.toStringAsFixed(2)} d=${w.lantern.pos.y.toStringAsFixed(2)} ff=${w.collected}');
      }
      return;
    }
    if (phase == AppPhase.playing) {
      _clock!.advance(dt, () => input);
      for (final e in w.drainEvents()) {
        _onEvent(e);
      }
    }
    final alpha = phase == AppPhase.playing ? _clock!.alpha : 1.0;
    gameScene.update(alpha, _realTime);
    _camera = rig.update(dt, w.lanternPose(alpha).pos, aspect);
    governor.evaluate(_realTime, stats, platform.thermal.value);
    if (_realTime - _lastLog >= 1.0) {
      _lastLog = _realTime;
      final th = platform.thermal.value;
      _perfLog.add([
        _realTime.toStringAsFixed(1),
        stats.fps(_realTime).toStringAsFixed(0),
        stats.percentile(0.95).toStringAsFixed(2),
        stats.max.toStringAsFixed(2),
        governor.renderScale.toStringAsFixed(2),
        governor.notch,
        th.status,
        th.headroom.toStringAsFixed(2),
        rig.profile.name,
        (platform.display.value['refreshRate'] ?? 0).toString(),
      ].join(','));
      if (_perfLog.length > 3600) _perfLog.removeAt(1);
    }
  }

  void _onEvent(SimEvent e) {
    switch (e) {
      case CollisionEvent(:final strength):
        if (settings.haptics) unawaited(platform.haptic(0.25 + 0.75 * strength));
      case FireflyEvent():
        if (settings.haptics) unawaited(platform.haptic(0.08));
      case LeafSmotherEvent():
        if (settings.haptics) unawaited(platform.haptic(0.15));
      case RunEndEvent(:final phase):
        final w = world!;
        newBest = settings.submitRun(
            won: phase == RunPhase.won, fireflies: w.collected, time: w.endedAt, flame: w.flame);
        // Let the ending play for a moment before the results card.
        Future.delayed(Duration(milliseconds: phase == RunPhase.won ? 5200 : 2600), () {
          if (this.phase == AppPhase.playing) {
            this.phase = AppPhase.results;
            notifyListeners();
          }
        });
    }
  }

  /// Writes the perf log as CSV into the app's external files dir.
  Future<String?> exportPerfLog() async {
    final dir = await platform.perfLogDir();
    if (dir == null) return null;
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final path = '$dir/lantern_perf_$stamp.csv';
    await writeTextFile(path, _perfLog.join('\n'));
    return path;
  }

  double get elapsed => world?.time ?? 0;
  double get realTime => _realTime;

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }
}

/// Clamp helper used by widgets.
double clampD(double v, double lo, double hi) => math.min(hi, math.max(lo, v));
