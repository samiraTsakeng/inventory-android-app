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
    barcode: json['barcode']?.toString() ?? '',
    productName: json['product_name']?.toString() ?? '',
    productId: int.tryParse(json['product_id']?.toString() ?? '') ?? 0,
    quantity: int.tryParse(json['quantity']?.toString() ?? '') ?? 1,
    lotNumber: json['lot_number']?.toString(),
    lotId: json['lot_id'] != null
        ? int.tryParse(json['lot_id'].toString())
        : null,
    tracking: json['tracking']?.toString() ?? 'none',
  );
}