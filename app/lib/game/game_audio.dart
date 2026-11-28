import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/audio.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_soloud/flutter_scene_soloud.dart';

import '../sim/world.dart';
import 'diagnostics.dart';

/// M10 sound: two ambience loops (light rain on the pool, the stream's
/// burble) and short cues for the game's events, all synthesised offline
/// (tools/audio/synth_audio.py, CC0 by construction; ASSETS.md).
///
/// Off on the web (the capture harness needs no sound, and SoLoud's web
/// loader would be one more moving part) and in diagnostic safe mode. Any
/// failure to start leaves the game silent rather than broken.
class GameAudio {
  GameAudio(this.scene);

  final Scene scene;
  SoloudAudioEngine? _engine;
  AudioClip? _firefly, _knock, _rustle, _finale;
  final List<AudioVoice> _loops = [];
  final math.Random _rng = math.Random(7);
  double _volume = 1.0;
  bool get running => _engine != null;

  Future<void> start(double volume) async {
    _volume = volume;
    if (kIsWeb || Diagnostics.safeRender) return;
    try {
      final engine = SoloudAudioEngine(maxActiveVoices: 24, bufferSize: 1024);
      scene.root.addComponent(engine);
      engine.masterVolume = _volume;
      final rain = await engine.loadClip('assets/audio/rain_loop.wav');
      final stream = await engine.loadClip('assets/audio/stream_loop.wav');
      _firefly = await engine.loadClip('assets/audio/firefly.wav');
      _knock = await engine.loadClip('assets/audio/knock.wav');
      _rustle = await engine.loadClip('assets/audio/rustle.wav');
      _finale = await engine.loadClip('assets/audio/finale.wav');
      for (final (clip, level) in [(rain, 0.55), (stream, 0.35)]) {
        final v = engine.createVoice(clip)
          ..looping = true
          ..volume = level;
        v.start();
        _loops.add(v);
      }
      _engine = engine;
    } catch (e) {
      // ignore: avoid_print
      print('LANTERN_AUDIO off: $e');
      _engine = null;
    }
  }

  /// 0 mutes; 1 is full level.
  set volume(double v) {
    _volume = v;
    _engine?.masterVolume = v;
  }

  void onEvent(SimEvent e) {
    final engine = _engine;
    if (engine == null || _volume <= 0) return;
    // A little pitch variety so repeated cues do not sound stamped.
    double pitch() => 0.94 + 0.12 * _rng.nextDouble();
    switch (e) {
      case CollisionEvent(:final strength):
        final c = _knock;
        if (c != null) engine.playOneShot(c, volume: 0.25 + 0.6 * strength.clamp(0.0, 1.0), pitch: pitch());
      case FireflyEvent():
        final c = _firefly;
        if (c != null) engine.playOneShot(c, volume: 0.35, pitch: pitch());
      case LeafSmotherEvent():
        final c = _rustle;
        if (c != null) engine.playOneShot(c, volume: 0.5, pitch: pitch());
      case RunEndEvent(:final phase):
        final c = _finale;
        if (c != null && phase == RunPhase.won) engine.playOneShot(c, volume: 0.5);
    }
  }
}
