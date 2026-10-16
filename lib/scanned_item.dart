class ScannedItem {
  final String barcode;
  String productName;
  int productId;
  int quantity;
  String? lotNumber;
  int? lotId; // id du stock.lot (Odoo) — null tant qu'il n'est pas connu
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
    // Ne jamais envoyer 0 : le backend résout le vrai lot_id dans stock.lot.
    'lot_id': (lotId != null && lotId! > 0) ? lotId : null,
    'tracking': tracking,
  };

  factory ScannedItem.fromJson(Map<String, dynamic> json) {
    final parsedLotId = int.tryParse(json['lot_id']?.toString() ?? '');
    return ScannedItem(
      barcode: json['barcode']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? '',
      productId: int.tryParse(json['product_id']?.toString() ?? '') ?? 0,
      quantity: int.tryParse(json['quantity']?.toString() ?? '') ?? 1,
      lotNumber: json['lot_number']?.toString(),
      lotId: (parsedLotId != null && parsedLotId > 0) ? parsedLotId : null,
      tracking: json['tracking']?.toString() ?? 'none',
    );
  }
}
