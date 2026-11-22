import 'dart:io';

/// The journal lives in the app's temp directory (on Android, its private
/// code cache). Writes are synchronous and flushed, so the last step reached
/// survives a native crash right after it.
File get _file => File('${Directory.systemTemp.path}/lantern_boot_journal.txt');

String? read() {
  try {
    return _file.existsSync() ? _file.readAsStringSync().trim() : null;
  } catch (_) {
    return null;
  }
}

void write(String step) {
  try {
    _file.writeAsStringSync(step, flush: true);
  } catch (_) {}
}
