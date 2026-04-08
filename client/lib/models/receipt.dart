class Receipt {
  final String id;
  final String? storeName;
  final String? purchaseDate;
  final double? total;
  final String? currency;
  final String ocrStatus;
  final double? ocrConfidence;
  final String createdAt;

  Receipt({
    required this.id,
    this.storeName,
    this.purchaseDate,
    this.total,
    this.currency,
    required this.ocrStatus,
    this.ocrConfidence,
    required this.createdAt,
  });

  factory Receipt.fromJson(Map<String, dynamic> json) {
    return Receipt(
      id: json['id'],
      storeName: json['store_name'],
      purchaseDate: json['purchase_date'],
      total: json['total'] != null ? double.tryParse(json['total'].toString()) : null,
      currency: json['currency'],
      ocrStatus: json['ocr_status'],
      ocrConfidence: json['ocr_confidence']?.toDouble(),
      createdAt: json['created_at'],
    );
  }
}

class ReceiptDetail {
  final Receipt receipt;
  final List<Item> items;
  final String? imageUrl;

  ReceiptDetail({required this.receipt, required this.items, this.imageUrl});

  factory ReceiptDetail.fromJson(Map<String, dynamic> json) {
    return ReceiptDetail(
      receipt: Receipt.fromJson(json),
      items: json['items'] != null
          ? (json['items'] as List).map((i) => Item.fromJson(i)).toList()
          : [],
      imageUrl: json['image_url'],
    );
  }
}

class Item {
  final String id;
  final String receiptId;
  final String description;
  final double? quantity;
  final double? unitPrice;
  final double? lineTotal;
  final String? productCode;

  Item({
    required this.id,
    required this.receiptId,
    required this.description,
    this.quantity,
    this.unitPrice,
    this.lineTotal,
    this.productCode,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['id'],
      receiptId: json['receipt_id'],
      description: json['description'],
      quantity: json['quantity']?.toDouble(),
      unitPrice: json['unit_price'] != null ? double.tryParse(json['unit_price'].toString()) : null,
      lineTotal: json['line_total'] != null ? double.tryParse(json['line_total'].toString()) : null,
      productCode: json['product_code'],
    );
  }
}

class ReceiptListResponse {
  final List<Receipt> receipts;
  final int totalCount;

  ReceiptListResponse({required this.receipts, required this.totalCount});

  factory ReceiptListResponse.fromJson(Map<String, dynamic> json) {
    return ReceiptListResponse(
      receipts: (json['receipts'] as List).map((r) => Receipt.fromJson(r)).toList(),
      totalCount: json['total_count'],
    );
  }
}

class OcrStatus {
  final String status;
  final double? confidence;

  OcrStatus({required this.status, this.confidence});

  factory OcrStatus.fromJson(Map<String, dynamic> json) {
    return OcrStatus(
      status: json['ocr_status'],
      confidence: json['ocr_confidence']?.toDouble(),
    );
  }
}
