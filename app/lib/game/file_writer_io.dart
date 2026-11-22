import 'dart:io';

Future<void> writeTextFile(String path, String contents) => File(path).writeAsString(contents);
