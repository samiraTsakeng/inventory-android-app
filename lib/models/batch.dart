import 'scanned_item.dart';

class Batch {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<ScannedItem> items;
  bool isSynced;
  int countingSheetId;
  int adjustmentId;
  String zoneName;
  String sheetName;

  Batch({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.items,
    this.isSynced = false,
    required this.countingSheetId,
    required this.adjustmentId,
    required this.zoneName,
    required this.sheetName,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'items': items.map((e) => e.toJson()).toList(),
    'isSynced': isSynced,
    'countingSheetId': countingSheetId,
    'adjustmentId': adjustmentId,
    'zoneName': zoneName,
    'sheetName': sheetName,
  };

  factory Batch.fromJson(Map<String, dynamic> json) => Batch(
    id: json['id'],
    name: json['name'],
    createdAt: DateTime.parse(json['createdAt']),
    items: (json['items'] as List).map((e) => ScannedItem.fromJson(e)).toList(),
    isSynced: json['isSynced'] ?? false,
    countingSheetId: json['countingSheetId'],
    adjustmentId: json['adjustmentId'],
    zoneName: json['zoneName'],
    sheetName: json['sheetName'],
  );
}