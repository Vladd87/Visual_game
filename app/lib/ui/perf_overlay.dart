import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../game/game_controller.dart';

/// Triple-tap debug overlay: fps, p95/max frame time, render scale, thermal
/// status, active screen and refresh mode, plus CSV export for
/// captures/device/.
class PerfOverlay extends StatefulWidget {
  const PerfOverlay({super.key, required this.c});
  final GameController c;

  @override
  State<PerfOverlay> createState() => _PerfOverlayState();
}

class _PerfOverlayState extends State<PerfOverlay> {
  Timer? _timer;
  String? _exported;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final now = c.realTime;
    final th = c.platform.thermal.value;
    final disp = c.platform.display.value;
    final g = c.governor;
    final rows = <String>[
      'fps   ${c.stats.fps(now).toStringAsFixed(0)}  (target ${g.targetHz.toStringAsFixed(0)})',
      'frame p95 ${c.stats.percentile(0.95).toStringAsFixed(1)} ms  max ${c.stats.max.toStringAsFixed(1)} ms',
      'build ${c.lastBuildMs.toStringAsFixed(1)} ms  raster ${c.lastRasterMs.toStringAsFixed(1)} ms',
      'scale ${g.renderScale.toStringAsFixed(2)}  notch ${g.notch}  ${g.preset.name}',
      'thermal ${th.label}  headroom ${th.headroom < 0 ? 'n/a' : th.headroom.toStringAsFixed(2)}${th.powerSave ? '  power-save' : ''}',
      'screen ${c.rig.profile.name}  ${disp['widthPx'] ?? '?'}x${disp['heightPx'] ?? '?'} @ ${(disp['refreshRate'] as num?)?.toStringAsFixed(0) ?? '?'} Hz',
      if (c.world != null) 'd ${c.world!.lantern.pos.y.toStringAsFixed(1)} m  ${c.world!.section.spec.name}',
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(8)),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFB8F5A0), fontSize: 10.5, fontFamily: 'monospace', height: 1.35),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          for (final r in rows) Text(r),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () async {
              final p = await c.exportPerfLog();
              setState(() => _exported = p ?? 'export unavailable here');
            },
            child: const Text('[ export perf CSV ]', style: TextStyle(color: Color(0xFFFFC27A))),
          ),
          if (_exported != null) SizedBox(width: 260, child: Text(_exported!, style: const TextStyle(fontSize: 9))),
        ]),
      ),
    );
  }
}
