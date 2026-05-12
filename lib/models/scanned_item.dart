class ScannedItem {
  final String barcode;
  String productName;
  int productId;
  int quantity;
  String? lotNumber;
  bool isSynced;
  String tracking; // 'none', 'lot', or 'serial'

  ScannedItem({
    required this.barcode,
    this.productName = '',
    this.productId = 0,
    this.quantity = 1,
    this.lotNumber,
    this.isSynced = false,
    this.tracking = 'none',
  });

  Map<String, dynamic> toJson() => {
    'barcode': barcode,
    'product_name': productName,
    'product_id': productId,
    'quantity': quantity,
    'lot_number': lotNumber,
    'tracking': tracking,
  };

  factory ScannedItem.fromJson(Map<String, dynamic> json) => ScannedItem(
    barcode: json['barcode'],
    productName: json['product_name'] ?? '',
    productId: json['product_id'] ?? 0,
    quantity: json['quantity'] ?? 1,
    lotNumber: json['lot_number'],
    tracking: json['tracking'] ?? 'none',
  );
}