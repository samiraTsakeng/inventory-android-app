import 'dart:async';

/// Converts an exception into a short French message that can be shown to
/// the user. Technical details (URLs, exception class names) stay in logs.
String friendlyError(Object error) {
  if (error is TimeoutException) {
    return 'Le serveur met trop de temps à répondre. Réessayez.';
  }

  final raw = error.toString();
  final lower = raw.toLowerCase();

  if (lower.contains('failed to fetch') ||
      lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('connection refused') ||
      lower.contains('connection failed') ||
      lower.contains('network is unreachable') ||
      lower.contains('failed host lookup')) {
    return 'Impossible de joindre le serveur. Vérifiez votre connexion.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'Le serveur met trop de temps à répondre. Réessayez.';
  }
  if (lower.contains('401') ||
      lower.contains('session expired') ||
      lower.contains('invalid or expired session')) {
    return 'Votre session a expiré. Veuillez vous reconnecter.';
  }

  // Keep messages produced by the app itself, without the Dart prefix.
  final message = raw
      .replaceFirst(
        RegExp(r'^(Exception|Error|FormatException|StateError):\s*'),
        '',
      )
      .trim();
  if (message.isEmpty || message.length > 160) {
    return 'Une erreur est survenue. Réessayez.';
  }
  return message;
}
