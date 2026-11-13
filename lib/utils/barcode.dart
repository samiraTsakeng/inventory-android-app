// A number as read by the camera can carry invisible characters: spaces,
// line breaks, the GS1 group separator (0x1D) of DataMatrix labels...
// Typed numbers are trimmed, scanned ones must be cleaned the same way, or
// they match neither the phone's copy nor Odoo once offline.
String cleanBarcode(String raw) =>
    raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
