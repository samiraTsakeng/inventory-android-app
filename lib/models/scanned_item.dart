class ScannedItem {
  final String barcode;
  String productName;
  int productId;
  int quantity;
  String? lotNumber;
  int? lotId;
  bool isSynced;
  String tracking; // 'none', 'lot', or 'serial' (from Odoo)

  ScannedItem({
    required this.barcode,
    this.productName = '',
    this.productId = 0,
    this.quantity = 1,
    this.lotNumber,
    this.lotId,
    this.isSynced = false,
    this.tracking = 'none',
  });

  Map<String, dynamic> toJson() => {
    'barcode': barcode,
    'product_name': productName,
    'product_id': productId,
    'quantity': quantity,
    'lot_number': lotNumber,
    'lot_id': lotId,
    'tracking': tracking,
  };

  factory ScannedItem.fromJson(Map<String, dynamic> json) => ScannedItem(
    barcode: json['barcode'],
    productName: json['product_name'] ?? '',
    productId: json['product_id'] ?? 0,
    quantity: json['quantity'] ?? 1,
    lotNumber: json['lot_number'],
    lotId: json['lot_id'],
    tracking: json['tracking'] ?? 'none',
  );
}