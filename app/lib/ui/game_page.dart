import 'package:flutter_scene/scene.dart' show RenderView, SceneView;
import '../game/diagnostics.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../game/game_controller.dart';
import '../game/settings.dart';
import '../render/present.dart';
import '../render/quality_governor.dart';
import '../sim/world.dart';
import 'layout.dart';
import 'perf_overlay.dart';

const _warm = Color(0xFFFFC27A);
const _ink = Color(0xFFE9E2D6);
const _dim = Color(0x99E9E2D6);

/// The single game screen: 3D viewport, input, HUD and overlays.
class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.controller});
  final GameController controller;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  GameController get c => widget.controller;
  Offset? _touchOrigin;
  Offset? _touchNow;
  int _pointer = -1;
  final List<double> _tapTimes = [];
  Duration _downAt = Duration.zero;
  GameLayout? _layout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_changed);
    c.governor.addListener(_changed);
    c.settings.addListener(_changed);
    Diagnostics.hide3d.addListener(_changed);
    Diagnostics.uiStage.addListener(_changed);
    unawaited(c.boot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_changed);
    c.governor.removeListener(_changed);
    c.settings.removeListener(_changed);
    Diagnostics.hide3d.removeListener(_changed);
    Diagnostics.uiStage.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      c.pause('paused');
    } else {
      unawaited(c.platform.reassertImmersive());
    }
  }

  // --- input -------------------------------------------------------------------

  void _down(PointerDownEvent e) {
    if (_pointer != -1) return;
    _pointer = e.pointer;
    _touchOrigin = e.localPosition;
    _touchNow = e.localPosition;
    _downAt = e.timeStamp;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _touchOrigin == null) return;
    _touchNow = e.localPosition;
    if (c.phase == AppPhase.playing && c.settings.control == ControlMode.drag) {
      final reach = 0.16 * math.min(_layout!.game.width, _layout!.game.height);
      c.setDrag(e.localPosition - _touchOrigin!, math.max(reach, 40));
    }
    setState(() {});
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    final moved = (_touchNow! - _touchOrigin!).distance;
    final held = (e.timeStamp - _downAt).inMilliseconds;
    _pointer = -1;
    _touchOrigin = null;
    _touchNow = null;
    c.endDrag();
    if (moved < 12 && held < 280) _tap(e.timeStamp);
    setState(() {});
  }

  void _tap(Duration at) {
    // Event timestamps (not processing or game time), chained: each tap must
    // follow the previous one within 0.6 s. Robust at any frame rate.
    final now = at.inMicroseconds / 1e6;
    if (_tapTimes.isNotEmpty && now - _tapTimes.last > 0.6) _tapTimes.clear();
    _tapTimes.add(now);
    if (_tapTimes.length >= 3) {
      _tapTimes.clear();
      c.settings.update((s) => s.showPerf = !s.showPerf);
      return;
    }
    if (c.phase == AppPhase.paused) {
      // Resume on a deliberate tap (not the first of a possible triple tap).
      Future.delayed(const Duration(milliseconds: 260), () {
        if (_tapTimes.length == 1 && c.phase == AppPhase.paused) c.resume();
      });
    }
  }

  // --- build -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final layout = GameLayout.of(context, simulateHinge: c.capture?.hinge ?? false);
    final prev = _layout;
    _layout = layout;
    if (prev == null || prev.game != layout.game || prev.flex != layout.flex || prev.hinge != layout.hinge) {
      SchedulerBinding.instance.addPostFrameCallback((_) => c.setViewport(layout.viewport));
    }
    final loading = c.phase == AppPhase.loading;
    final stage = Diagnostics.uiStage.value;
    final page = Scaffold(
      backgroundColor: const Color(0xFF07090B),
      // StackFit.expand: the page always fills the screen. With the default
      // loose fit a Stack takes the size of its non-positioned children; on
      // the title screen the only one was the (empty, zero-size) diagnostics
      // panel, so the Stack was 0 x 0 and its overflow clip hid every layer:
      // the black screen on the phone (test build 9). The capture harness
      // has no diagnostics panel, so it never showed there.
      body: Stack(fit: StackFit.expand, children: [
        if (!loading)
          Positioned.fromRect(
            rect: layout.game,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: Diagnostics.no3d || Diagnostics.noScene || Diagnostics.hide3d.value || stage.hideGame
                  ? const ColoredBox(
                      color: Color(0xFF0B0E12),
                      child: Center(child: Text('3D view off (diagnostic mode)', style: TextStyle(color: Color(0xFF8A9099)))),
                    )
                  : Diagnostics.noEffects
                      ? SceneView(
                          c.scene,
                          // Straight to the screen: no off-screen target, no upscale shader.
                          viewsBuilder: (_) => [RenderView(camera: c.cameraFor(layout.game.width / math.max(1, layout.game.height)))],
                          onTick: (elapsed, dt) => c.onTick(dt, layout.game.width / math.max(1, layout.game.height)),
                        )
                      : ScenePresenter(
                          scene: c.scene,
                          renderScale: c.governor.renderScale,
                          cameraFor: c.cameraFor,
                          onTick: (dt) => c.onTick(dt, layout.game.width / math.max(1, layout.game.height)),
                        ),
            ),
          ),
        if (!loading && c.capture == null && !stage.hideCard) ..._overlays(layout),
        if (loading || stage == UiStage.loadingLook) _Loading(text: c.loadingText),
        if (c.capture == null) _DiagnosticsPanel(),
        if (Diagnostics.stepByStep) const Positioned(left: 0, right: 0, bottom: 0, child: _BringUpBanner()),
      ]),
    );
    // Bring-up: a repaint boundary the probe can render offscreen.
    return Diagnostics.stepByStep ? RepaintBoundary(key: Diagnostics.rootKey, child: page) : page;
  }

  List<Widget> _overlays(GameLayout layout) {
    final w = c.world;
    final safe = layout.safe.deflateRect(layout.game);
    final out = <Widget>[];
    if (w != null && (c.phase == AppPhase.playing || c.phase == AppPhase.paused) && !layout.flex) {
      out.add(Positioned(left: safe.left, top: safe.top, child: _FlameMeter(flame: w.flame)));
      out.add(Positioned(
        right: layout.screen.width - safe.right,
        top: safe.top - 6,
        child: Row(children: [
          _FireflyCount(n: w.collected),
          const SizedBox(width: 8),
          _IconButtonBare(icon: Icons.pause_rounded, onTap: () => c.pause('paused')),
        ]),
      ));
    }
    if (_touchOrigin != null && c.phase == AppPhase.playing && c.settings.control == ControlMode.drag) {
      out.add(Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _DragHint(_touchOrigin!, _touchNow!, layout.game.topLeft)))));
    }
    if (layout.flex) out.add(Positioned.fromRect(rect: layout.panel!, child: _FlexPanel(c: c, layout: layout)));
    final ui = layout.uiRect;
    switch (c.phase) {
      case AppPhase.title:
        out.add(Positioned.fromRect(rect: ui, child: _TitleCard(c: c)));
      case AppPhase.paused:
        out.add(Positioned.fromRect(rect: layout.game, child: IgnorePointer(child: Container(color: const Color(0x8807090B)))));
        if (!layout.flex) out.add(Positioned.fromRect(rect: ui, child: _PauseCard(c: c)));
      case AppPhase.results:
        out.add(Positioned.fromRect(rect: ui, child: _ResultsCard(c: c)));
      case AppPhase.playing:
      case AppPhase.loading:
        break;
    }
    if (c.settings.showPerf) {
      out.add(Positioned(left: safe.left, top: safe.top + 40, child: PerfOverlay(c: c)));
    }
    return out;
  }
}

// --- pieces --------------------------------------------------------------------

class _Loading extends StatelessWidget {
  const _Loading({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF07090B),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 1.5, color: _warm)),
          const SizedBox(height: 18),
          Text(text, style: const TextStyle(color: _dim, fontSize: 13, letterSpacing: 2)),
        ]),
      );
}

class _FlameMeter extends StatelessWidget {
  const _FlameMeter({required this.flame});
  final double flame;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('FLAME', style: TextStyle(color: _dim, fontSize: 10, letterSpacing: 2.5)),
        const SizedBox(height: 5),
        Container(
          width: 120,
          height: 3,
          decoration: BoxDecoration(color: const Color(0x33E9E2D6), borderRadius: BorderRadius.circular(2)),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: flame.clamp(0.0, 1.0),
            child: Container(decoration: BoxDecoration(color: Color.lerp(const Color(0xFFB4532A), _warm, flame), borderRadius: BorderRadius.circular(2))),
          ),
        ),
      ]);
}

class _FireflyCount extends StatelessWidget {
  const _FireflyCount({required this.n});
  final int n;
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFD6F05A), shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$n', style: const TextStyle(color: _ink, fontSize: 15, fontFeatures: [FontFeature.tabularFigures()])),
      ]);
}

class _IconButtonBare extends StatelessWidget {
  const _IconButtonBare({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, color: _dim, size: 22)),
      );
}

class _DragHint extends CustomPainter {
  _DragHint(this.origin, this.now, this.offset);
  final Offset origin, now, offset;
  @override
  void paint(Canvas canvas, Size size) {
    final o = origin + offset, n = now + offset;
    final p = Paint()
      ..color = const Color(0x55E9E2D6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(o, 22, p);
    canvas.drawCircle(n, 5, p..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_DragHint old) => old.origin != origin || old.now != now;
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final stage = Diagnostics.uiStage.value;
    final box = Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
            decoration: BoxDecoration(
              color: const Color(0xCC0B0E12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x22E9E2D6)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          );
    // Bring-up variants: no scroll view at all, or a scroll view without
    // Android's stretch overscroll effect.
    if (stage == UiStage.plainCard) return Center(child: box);
    final scroll = SingleChildScrollView(clipBehavior: Clip.none, child: box);
    if (stage == UiStage.cardNoStretch) {
      return Center(child: ScrollConfiguration(behavior: const _NoOverscroll(), child: scroll));
    }
    return Center(child: scroll);
  }
}

class _NoOverscroll extends ScrollBehavior {
  const _NoOverscroll();
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}

class _Btn extends StatelessWidget {
  const _Btn(this.label, this.onTap, {this.primary = false});
  final String label;
  final VoidCallback onTap;
  final bool primary;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: primary ? const Color(0x33FFC27A) : const Color(0x14E9E2D6),
            foregroundColor: primary ? _warm : _ink,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 14, letterSpacing: 1.5)),
        ),
      );
}

String _fmtTime(double s) {
  final m = s ~/ 60, r = (s % 60).floor();
  return '$m:${r.toString().padLeft(2, '0')}';
}

class _TitleCard extends StatelessWidget {
  const _TitleCard({required this.c});
  final GameController c;
  @override
  Widget build(BuildContext context) {
    final s = c.settings;
    return _Card(children: [
      const Text('LANTERN', textAlign: TextAlign.center, style: TextStyle(color: _warm, fontSize: 26, letterSpacing: 9, fontWeight: FontWeight.w300)),
      const SizedBox(height: 8),
      const Text('Carry the flame downstream.\nGather fireflies. Mind the stones.',
          textAlign: TextAlign.center, style: TextStyle(color: _dim, fontSize: 13, height: 1.5)),
      if (s.bestFireflies > 0) ...[
        const SizedBox(height: 12),
        Text('best  ${s.bestFireflies} fireflies · ${(s.bestFlame * 100).round()}% flame · ${_fmtTime(s.bestTime)}',
            textAlign: TextAlign.center, style: const TextStyle(color: _dim, fontSize: 11, letterSpacing: 1)),
      ],
      const SizedBox(height: 8),
      _Btn('BEGIN', c.startRun, primary: true),
      _SettingsBlock(c: c),
    ]);
  }
}

class _PauseCard extends StatelessWidget {
  const _PauseCard({required this.c});
  final GameController c;
  @override
  Widget build(BuildContext context) => _Card(children: [
        Text(c.pauseReason == 'screen switched' ? 'SCREEN SWITCHED' : 'PAUSED',
            textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontSize: 15, letterSpacing: 4)),
        const SizedBox(height: 4),
        const Text('tap to continue', textAlign: TextAlign.center, style: TextStyle(color: _dim, fontSize: 12)),
        _Btn('CONTINUE', c.resume, primary: true),
        _Btn('LEAVE THE STREAM', c.toTitle),
        _SettingsBlock(c: c),
      ]);
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({required this.c});
  final GameController c;
  @override
  Widget build(BuildContext context) {
    final w = c.world!;
    final won = w.phase == RunPhase.won;
    return _Card(children: [
      Text(won ? 'THE POOL' : 'THE FLAME WENT OUT',
          textAlign: TextAlign.center, style: const TextStyle(color: _warm, fontSize: 16, letterSpacing: 4)),
      const SizedBox(height: 14),
      Text('${w.collected} fireflies', textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontSize: 22)),
      const SizedBox(height: 4),
      Text('${(w.flame * 100).round()}% flame · ${_fmtTime(w.endedAt)} · ${(w.progress * 100).round()}% of the way',
          textAlign: TextAlign.center, style: const TextStyle(color: _dim, fontSize: 12)),
      if (c.newBest) const Padding(padding: EdgeInsets.only(top: 8), child: Text('new best', textAlign: TextAlign.center, style: TextStyle(color: _warm, fontSize: 12, letterSpacing: 2))),
      _Btn('AGAIN', c.startRun, primary: true),
      _Btn('TITLE', c.toTitle),
    ]);
  }
}

class _SettingsBlock extends StatelessWidget {
  const _SettingsBlock({required this.c});
  final GameController c;
  @override
  Widget build(BuildContext context) {
    final s = c.settings;
    Widget seg<T>(String label, List<(T, String)> items, T value, void Function(T) onPick) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            SizedBox(width: 74, child: Text(label, style: const TextStyle(color: _dim, fontSize: 11, letterSpacing: 1.5))),
            for (final (v, name) in items)
              Expanded(
                child: GestureDetector(
                  onTap: () => onPick(v),
                  child: Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: v == value ? const Color(0x33FFC27A) : const Color(0x0FE9E2D6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(name, style: TextStyle(color: v == value ? _warm : _dim, fontSize: 11)),
                  ),
                ),
              ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 10),
      seg<ControlMode>('CONTROL', [(ControlMode.drag, 'drag'), (ControlMode.tilt, 'tilt')], s.control, c.setControl),
      seg<bool>('HAPTICS', [(true, 'on'), (false, 'off')], s.haptics, (v) => s.update((x) => x.haptics = v)),
      seg<QualityPreset>('QUALITY', [(QualityPreset.high, 'high'), (QualityPreset.medium, 'med'), (QualityPreset.low, 'low')], s.quality, c.setQuality),
      seg<bool>('REFRESH', [(false, '60 Hz'), (true, '120 Hz')], s.performance120, c.setPerformance120),
      if (s.control == ControlMode.tilt)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextButton(onPressed: c.recalibrateTilt, child: const Text('recalibrate tilt', style: TextStyle(color: _dim, fontSize: 11))),
        ),
    ]);
  }
}

/// Flex mode (half-folded): minimal stats and pause controls below the hinge.
class _FlexPanel extends StatelessWidget {
  const _FlexPanel({required this.c, required this.layout});
  final GameController c;
  final GameLayout layout;
  @override
  Widget build(BuildContext context) {
    final w = c.world;
    final s = c.settings;
    final playing = c.phase == AppPhase.playing;
    return Container(
      color: const Color(0xFF0B0E12),
      padding: EdgeInsets.fromLTRB(layout.safe.left + 8, 18, layout.safe.right + 8, layout.safe.bottom + 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (w != null) _FlameMeter(flame: w.flame),
            const SizedBox(height: 14),
            if (w != null)
              Row(children: [
                _FireflyCount(n: w.collected),
                const SizedBox(width: 18),
                Text(_fmtTime(w.time), style: const TextStyle(color: _dim, fontSize: 13)),
                const SizedBox(width: 18),
                Text('${(w.progress * 100).round()}%', style: const TextStyle(color: _dim, fontSize: 13)),
              ]),
            const SizedBox(height: 10),
            if (s.bestFireflies > 0) Text('best ${s.bestFireflies}', style: const TextStyle(color: _dim, fontSize: 11)),
          ]),
        ),
        if (c.phase == AppPhase.title) _Btn('BEGIN', c.startRun, primary: true),
        if (c.phase == AppPhase.results) _Btn('AGAIN', c.startRun, primary: true),
        if (c.phase == AppPhase.playing || c.phase == AppPhase.paused)
          _IconButtonBare(icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded, onTap: playing ? () => c.pause('paused') : c.resume),
      ]),
    );
  }
}


/// Shows a crashed previous launch or an error, so a screenshot reports it.
class _DiagnosticsPanel extends StatefulWidget {
  // Not const: rebuilt with the page, since its text depends on launch flags
  // that arrive after the first frame.
  // ignore: prefer_const_constructors_in_immutables
  _DiagnosticsPanel();

  @override
  State<_DiagnosticsPanel> createState() => _DiagnosticsPanelState();
}

class _DiagnosticsPanelState extends State<_DiagnosticsPanel> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
        valueListenable: Diagnostics.lastError,
        builder: (context, error, _) {
          final text = Diagnostics.panelText(error);
          if (text == null || (_dismissed && error == null)) return const SizedBox.shrink();
          return SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: () => setState(() {
                  _dismissed = true;
                  Diagnostics.lastError.value = null;
                }),
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 560),
                  decoration: BoxDecoration(
                    color: const Color(0xE6201010),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x66FF8A65)),
                  ),
                  child: Text(
                    '$text\n(tap to dismiss)',
                    style: const TextStyle(color: Color(0xFFFFD8CC), fontSize: 12, height: 1.3),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// Device bring-up banner: bright, with the current boot step, a frame
/// counter and a moving block, so a glance shows whether the screen is still
/// being updated (and at which step it stopped).
class _BringUpBanner extends StatefulWidget {
  const _BringUpBanner();

  @override
  State<_BringUpBanner> createState() => _BringUpBannerState();
}

class _BringUpBannerState extends State<_BringUpBanner> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _frames = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => setState(() => _frames++))..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ink = TextStyle(color: Color(0xFF000000), fontSize: 20, fontWeight: FontWeight.w600);
    final mode = '${Diagnostics.auto ? 'AUTO ${Diagnostics.autoLabel} · ' : ''}${Diagnostics.modeName}';
    return Container(
      height: 150,
      color: const Color(0xFFFFD54F),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ValueListenableBuilder<String>(
          valueListenable: Diagnostics.visibleStep,
          builder: (context, step, _) => Text('STEP: $step', style: ink),
        ),
        Text('frame $_frames   ($mode)', style: ink.copyWith(fontSize: 16, fontWeight: FontWeight.w400)),
        const Spacer(),
        LayoutBuilder(builder: (context, c) {
          final x = (c.maxWidth - 40) * (0.5 + 0.5 * math.sin(_frames / 20));
          return SizedBox(
            height: 24,
            child: Stack(children: [Positioned(left: x, top: 0, child: Container(width: 40, height: 24, color: const Color(0xFF000000)))]),
          );
        }),
      ]),
    );
  }
}
