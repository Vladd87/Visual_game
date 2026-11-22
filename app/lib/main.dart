import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

import 'game/capture.dart';
import 'game/game_controller.dart';
import 'ui/game_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Surface framework errors in every build mode (release swallows them otherwise).
  FlutterError.onError = (details) => debugPrint('LANTERN_ERROR ${details.exceptionAsString()}\n${details.stack}');
  final capture = kIsWeb ? CaptureConfig.fromUri(Uri.base) : null;
  // Automated smoke tests on web find buttons through the semantics tree.
  if (kIsWeb && Uri.base.queryParameters['semantics'] == '1') {
    SemanticsBinding.instance.ensureSemantics();
  }
  runApp(LanternApp(controller: GameController(capture: capture)));
}

class LanternApp extends StatelessWidget {
  const LanternApp({super.key, required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lantern',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(primary: Color(0xFFFFC27A), surface: Color(0xFF0B0E12)),
        scaffoldBackgroundColor: const Color(0xFF07090B),
      ),
      home: GamePage(controller: controller),
    );
  }
}
