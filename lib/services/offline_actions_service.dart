import 'package:shared_preferences/shared_preferences.dart';
import 'batch_storage_service.dart';
import 'counting_service.dart';
import 'local_storage_service.dart';
import 'sync_service.dart';

// "Commencer" and "Terminer" done without network. Kept on the phone and
// replayed in Odoo when the connection comes back: starts before the
// batches are sent, validations after (a sheet is only validated once all
// its batches reached the ERP). Odoo still decides: a refused action is
// dropped and its message reported.
class OfflineActionsService {
  static const String start = 'start';
  static const String validate = 'validate';

  static const String _prefix = 'pending_sheet_actions_';

  static Future<String> _key() async =>
      '$_prefix${await LocalStorageService.getSessionId()}';

  // Stored as "type:sheetId".
  static Future<List<String>> _entries() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(await _key()) ?? [];
  }

  static Future<void> _save(List<String> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(await _key(), entries);
  }

  static Future<void> add(String type, int sheetId) async {
    final entries = await _entries();
    final entry = '$type:$sheetId';
    if (!entries.contains(entry)) {
      entries.add(entry);
      await _save(entries);
    }
  }

  static Future<void> _remove(String type, int sheetId) async {
    final entries = await _entries();
    entries.remove('$type:$sheetId');
    await _save(entries);
  }

  // sheetId -> pending action ("validate" wins over "start").
  static Future<Map<int, String>> pendingBySheet() async {
    final result = <int, String>{};
    for (final entry in await _entries()) {
      final parts = entry.split(':');
      final sheetId = int.tryParse(parts.last);
      if (sheetId == null) continue;
      if (result[sheetId] != validate) result[sheetId] = parts.first;
    }
    return result;
  }

  static Future<List<int>> _sheetsWith(String type) async => [
        for (final entry in await _entries())
          if (entry.startsWith('$type:')) int.tryParse(entry.split(':').last),
      ].whereType<int>().toList();

  // Starts the sheets started offline. Returns Odoo's refusals.
  static Future<List<String>> replayStarts() async {
    final errors = <String>[];
    for (final sheetId in await _sheetsWith(start)) {
      // Already started (by a batch sent meanwhile, or the other phone):
      // action_begin would refuse it as "comptage en cours".
      final sheet = await CountingService.getSheetState(sheetId);
      if (sheet == null) {
        if (!SyncService.online.value) break;
        continue;
      }
      if (sheet['state'] != 'new') {
        await _remove(start, sheetId);
        continue;
      }

      final result = await CountingService.startSheet(sheetId);
      if (result.success) {
        await _remove(start, sheetId);
      } else if (!SyncService.online.value) {
        break; // Connection lost again: retried at the next reconnection.
      } else {
        await _remove(start, sheetId);
        errors.add('${sheet['name'] ?? 'Feuille $sheetId'} : ${result.message}');
      }
    }
    return errors;
  }

  // Validates the sheets finished offline whose batches are all sent.
  // Returns Odoo's refusals.
  static Future<List<String>> replayValidations() async {
    final errors = <String>[];
    final batches = await BatchStorageService.getBatches();

    for (final sheetId in await _sheetsWith(validate)) {
      final waiting = batches.any((b) => b.countingSheetId == sheetId && !b.isSynced);
      if (waiting) continue; // Validated once its batches are in the ERP.

      final sheet = await CountingService.getSheetState(sheetId);
      if (sheet == null) {
        if (!SyncService.online.value) break;
        continue;
      }
      if (sheet['state'] == 'confirm') {
        await _remove(validate, sheetId);
        continue;
      }

      final result = await CountingService.validateSheet(sheetId);
      if (result.success) {
        await _remove(validate, sheetId);
      } else if (!SyncService.online.value) {
        break;
      } else {
        await _remove(validate, sheetId);
        errors.add('${sheet['name'] ?? 'Feuille $sheetId'} : ${result.message}');
      }
    }
    return errors;
  }

  static Future<bool> hasPending() async => (await _entries()).isNotEmpty;
}
