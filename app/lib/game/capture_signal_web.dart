import 'package:web/web.dart' as web;

/// Tells the Playwright harness the shot has settled: it waits for this title.
void signalReady(String info) {
  web.document.title = 'LANTERN_READY $info';
}
