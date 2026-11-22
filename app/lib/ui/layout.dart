import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../render/camera_rig.dart';

/// Where things go on the current screen: the game viewport, the Flex-mode
/// panel, the hinge, and a crease-free rectangle for centred UI.
class GameLayout {
  GameLayout({
    required this.screen,
    required this.game,
    required this.panel,
    required this.hinge,
    required this.halfOpened,
    required this.safe,
  });

  final Size screen;
  final Rect game; // 3D viewport
  final Rect? panel; // Flex-mode stats panel (bottom half)
  final Rect? hinge; // screen coordinates
  final bool halfOpened;
  final EdgeInsets safe; // cutouts and system insets

  bool get flex => panel != null;

  /// Centred UI goes in the larger region beside a vertical hinge.
  Rect get uiRect {
    final h = hinge;
    final g = safe.deflateRect(game);
    if (h == null || h.height < h.width || h.right <= g.left || h.left >= g.right) return g;
    final left = Rect.fromLTRB(g.left, g.top, h.left - 12, g.bottom);
    final right = Rect.fromLTRB(h.right + 12, g.top, g.right, g.bottom);
    return left.width >= right.width ? left : right;
  }

  ViewportInfo get viewport => ViewportInfo(
        size: game.size,
        hinge: hinge?.shift(-game.topLeft),
        halfOpened: flex,
      );

  static GameLayout of(BuildContext context, {bool simulateHinge = false}) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    Rect? hinge;
    var half = false;
    for (final f in mq.displayFeatures) {
      if (f.type == DisplayFeatureType.cutout) continue;
      hinge = f.bounds;
      if (f.state == DisplayFeatureState.postureHalfOpened) half = true;
    }
    if (simulateHinge && hinge == null) {
      hinge = Rect.fromLTWH(size.width / 2 - 1, 0, 2, size.height);
    }
    final horizontal = hinge != null && hinge.width >= hinge.height;
    Rect game = Offset.zero & size;
    Rect? panel;
    if (half && horizontal && hinge.top > size.height * 0.25) {
      game = Rect.fromLTRB(0, 0, size.width, hinge.top);
      panel = Rect.fromLTRB(0, hinge.bottom, size.width, size.height);
    }
    final pad = mq.viewPadding;
    return GameLayout(
      screen: size,
      game: game,
      panel: panel,
      hinge: hinge,
      halfOpened: half,
      safe: EdgeInsets.fromLTRB(pad.left + 14, pad.top + 12, pad.right + 14, pad.bottom + 12),
    );
  }
}
