import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// Large offline data (numbers in stock, copied lists) in files of their own.
//
// SharedPreferences keeps every value in one file, loaded in memory at
// startup and rewritten in full on every change: with thousands of numbers
// stored there, every scan (which saves the scanned list) rewrote megabytes.
// Here each value is its own file, and large JSON is encoded / decoded off
// the UI thread so the screen doesn't freeze.
class FileStore {
  // Above this size (characters / items) the JSON work runs in an isolate.
  static const int _isolateThreshold = 50000;
  static const int _isolateItems = 500;

  static Directory? _dir;
  // Writes of a key run one after the other (same temporary file).
  static final Map<String, Future<void>> _writes = {};

  static Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/offline');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  static String _fileName(String key) =>
      '${key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}.json';

  static Future<File> _file(String key) async =>
      File('${(await _folder()).path}/${_fileName(key)}');

  static Future<void> write(String key, Object? data) {
    final previous = _writes[key] ?? Future.value();
    final next = previous.then((_) => _write(key, data)).catchError((e) {
      print("File store write error ($key): $e");
    });
    _writes[key] = next;
    return next.whenComplete(() {
      if (identical(_writes[key], next)) _writes.remove(key);
    });
  }

  static Future<void> _write(String key, Object? data) async {
    final big = data is List && data.length > _isolateItems ||
        data is Map && data.length > _isolateItems ||
        data is Map && data.values.any((v) => v is List && v.length > _isolateItems);
    final text = big ? await compute(_encode, data) : jsonEncode(data);
    final file = await _file(key);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(file.path);
  }

  // Stored value, or null when there is none (or it can't be read).
  static Future<dynamic> read(String key) async {
    try {
      await _writes[key];
      final file = await _file(key);
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      return text.length > _isolateThreshold
          ? await compute(_decode, text)
          : jsonDecode(text);
    } catch (e) {
      print("File store read error ($key): $e");
      return null;
    }
  }

  static Future<void> remove(String key) async {
    try {
      await _writes[key];
      final file = await _file(key);
      if (await file.exists()) await file.delete();
    } catch (e) {
      print("File store remove error ($key): $e");
    }
  }

  // Removes every value whose key starts with one of [prefixes].
  static Future<void> removePrefixes(List<String> prefixes) async {
    try {
      final names = prefixes
          .map((p) => p.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_'))
          .toList();
      await for (final entry in (await _folder()).list()) {
        final name = entry.uri.pathSegments.last;
        if (entry is File && names.any(name.startsWith)) {
          await entry.delete();
        }
      }
    } catch (e) {
      print("File store cleanup error: $e");
    }
  }
}

String _encode(Object? data) => jsonEncode(data);

dynamic _decode(String text) => jsonDecode(text);
