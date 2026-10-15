import 'package:shared_preferences/shared_preferences.dart';
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

  // Sheets with a pending action, in the order the actions were done on
  // the phone (the order Odoo must see them: finish F1 before starting F2
  // of the same zone).
  static Future<List<int>> sheetsInOrder() async {
    final order = <int>[];
    for (final entry in await _entries()) {
      final sheetId = int.tryParse(entry.split(':').last);
      if (sheetId != null && !order.contains(sheetId)) order.add(sheetId);
    }
    return order;
  }

  static Future<bool> _has(String type, int sheetId) async =>
      (await _entries()).contains('$type:$sheetId');

  // Starts the sheet in Odoo if it was started offline.
  static Future<ReplayOutcome> replayStart(int sheetId) async {
    if (!await _has(start, sheetId)) return ReplayOutcome.nothing;

    final sheet = await CountingService.getSheetState(sheetId);
    if (sheet == null) {
      return SyncService.online.value ? ReplayOutcome.nothing : ReplayOutcome.offline;
    }
    // Already started (by a batch sent meanwhile, or in Odoo): action_begin
    // would refuse it as "comptage en cours".
    if (sheet['state'] != 'new') {
      await _remove(start, sheetId);
      return ReplayOutcome.done;
    }

    final result = await CountingService.startSheet(sheetId);
    if (result.success) {
      await _remove(start, sheetId);
      return ReplayOutcome.done;
    }
    if (!SyncService.online.value) return ReplayOutcome.offline;
    // Refused by Odoo: dropped, the message is reported.
    await _remove(start, sheetId);
    return ReplayOutcome.refused(result.message);
  }

  // Validates the sheet in Odoo if it was finished offline. The caller only
  // calls it once all the sheet's batches are in the ERP.
  static Future<ReplayOutcome> replayValidate(int sheetId) async {
    if (!await _has(validate, sheetId)) return ReplayOutcome.nothing;

    final sheet = await CountingService.getSheetState(sheetId);
    if (sheet == null) {
      return SyncService.online.value ? ReplayOutcome.nothing : ReplayOutcome.offline;
    }
    if (sheet['state'] == 'confirm') {
      await _remove(validate, sheetId);
      return ReplayOutcome.done;
    }

    final result = await CountingService.validateSheet(sheetId);
    if (result.success) {
      await _remove(validate, sheetId);
      return ReplayOutcome.done;
    }
    if (!SyncService.online.value) return ReplayOutcome.offline;
    await _remove(validate, sheetId);
    return ReplayOutcome.refused(result.message);
  }

  static Future<bool> hasPending() async => (await _entries()).isNotEmpty;
}

class ReplayOutcome {
  // nothing: no pending action; done: replayed (or already true in Odoo);
  // offline: connection lost, kept for later; refused: Odoo said no.
  final String kind;
  final String? message;

  const ReplayOutcome._(this.kind, [this.message]);

  static const nothing = ReplayOutcome._('nothing');
  static const done = ReplayOutcome._('done');
  static const offline = ReplayOutcome._('offline');
  static ReplayOutcome refused(String? message) => ReplayOutcome._('refused', message);

  bool get isRefused => kind == 'refused';
  bool get isOffline => kind == 'offline';
  bool get isDone => kind == 'done';
}
