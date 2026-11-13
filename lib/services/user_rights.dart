import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'local_storage_service.dart';

// What the logged-in user may see, from their Odoo groups: the app shows
// the consolidations only to the group that sees them in Odoo
// (Ajustement Général / Resp. Ajustement). Asked at each offline
// preparation (login, startup, connection back) and kept on the phone, so
// it also applies offline.
class UserRights {
  // null until known: the consolidations stay hidden meanwhile.
  static final ValueNotifier<bool?> consolidation = ValueNotifier(null);

  static Future<String> _key() async =>
      'user_rights_${await LocalStorageService.getSessionId()}';

  // Rights kept on the phone for the current account (startup, login).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _key());
    if (raw == null) {
      consolidation.value = null;
      return;
    }
    try {
      consolidation.value = (jsonDecode(raw) as Map)['consolidation'] == true;
    } catch (_) {
      consolidation.value = null;
    }
  }

  // Asks Odoo. The rights kept stay when it can't be reached.
  static Future<void> refresh() async {
    try {
      final response = await ApiClient.call(ApiConfig.userRights);
      final bool value;
      if (response.statusCode == 404) {
        // Module not updated yet: no rights check there, as before.
        value = true;
      } else if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is! Map || data['success'] != true) return;
        value = data['consolidation'] == true;
      } else {
        return;
      }
      consolidation.value = value;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(await _key(), jsonEncode({'consolidation': value}));
    } catch (e) {
      debugPrint("User rights unavailable: $e");
    }
  }

  // Logout: nothing shown until the next account's rights are known.
  static void reset() => consolidation.value = null;
}
