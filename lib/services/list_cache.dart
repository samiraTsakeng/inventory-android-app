import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'local_storage_service.dart';
import 'sync_service.dart';

// Lists shown to navigate (adjustments, sheets): the phone's copy is shown
// at once, online or offline, instead of waiting for the server (offline,
// that meant waiting for a timeout on every screen). Online, the server is
// asked in the background; when its list differs, [revision] is bumped so
// open screens show it.
class ListCache {
  static final ValueNotifier<int> revision = ValueNotifier(0);
  static final Map<String, Future<void>> _refreshing = {};

  // [fetch] asks the server and saves its answer as the phone's copy.
  // [fresh]: wait for the server (after an action that changes the list).
  static Future<List<dynamic>> get(
    String name,
    Future<List<dynamic>> Function() fetch, {
    bool fresh = false,
  }) async {
    if (!fresh) {
      final cached = await LocalStorageService.getCachedResponse(name);
      if (cached is List) {
        if (SyncService.online.value) _refresh(name, fetch, cached);
        return cached;
      }
    }
    // No copy yet (first opening) or fresh list asked: the server answers,
    // or the copy is used if it can't be reached.
    return fetch();
  }

  static void _refresh(
    String name,
    Future<List<dynamic>> Function() fetch,
    List<dynamic> shown,
  ) {
    _refreshing[name] ??= () async {
      try {
        final latest = await fetch();
        if (jsonEncode(latest) != jsonEncode(shown)) revision.value++;
      } catch (e) {
        debugPrint("List refresh $name: $e");
      } finally {
        _refreshing.remove(name);
      }
    }();
  }
}
