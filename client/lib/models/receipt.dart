double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

class Receipt {
  final String id;
  final String? storeNameRaw;
  final String? purchaseAt;
  final double? subtotal;
  final double? total;
  final String currency;
  final String extractionStatus;
  final double? extractionConf;
  final bool needsReview;
  final String createdAt;

  Receipt({
    required this.id,
    this.storeNameRaw,
    this.purchaseAt,
    this.subtotal,
    this.total,
    required this.currency,
    required this.extractionStatus,
    this.extractionConf,
    this.needsReview = false,
    required this.createdAt,
  });

  factory Receipt.fromJson(Map<String, dynamic> json) {
    return Receipt(
      id: json['id'] as String,
      storeNameRaw: json['store_name_raw'] as String?,
      purchaseAt: json['purchase_at'] as String?,
      subtotal: _toDouble(json['subtotal']),
      total: _toDouble(json['total']),
      currency: json['currency'] as String? ?? 'NOK',
      extractionStatus: json['extraction_status'] as String? ?? 'pending',
      extractionConf: _toDouble(json['extraction_conf']),
      needsReview: json['needs_review'] as bool? ?? false,
      createdAt: json['created_at'] as String,
    );
  }
}

class Transaction {
  final int id;
  final String receiptId;
  final String descriptionRaw;
  final String? descriptionClean;
  final double? quantity;
  final String? unit;
  final double? unitPrice;
  final double? lineTotal;
  final String itemType;
  final double? mvaRate;

  Transaction({
    required this.id,
    required this.receiptId,
    required this.descriptionRaw,
    this.descriptionClean,
    this.quantity,
    this.unit,
    this.unitPrice,
    this.lineTotal,
    required this.itemType,
    this.mvaRate,
  });

  String get displayDescription =>
      (descriptionClean != null && descriptionClean!.isNotEmpty)
          ? descriptionClean!
          : descriptionRaw;

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: (json['id'] as num).toInt(),
      receiptId: json['receipt_id'] as String,
      descriptionRaw: json['description_raw'] as String? ?? '',
      descriptionClean: json['description_clean'] as String?,
      quantity: _toDouble(json['quantity']),
      unit: json['unit'] as String?,
      unitPrice: _toDouble(json['unit_price']),
      lineTotal: _toDouble(json['line_total']),
      itemType: json['item_type'] as String? ?? 'unknown',
      mvaRate: _toDouble(json['mva_rate']),
    );
  }
}

/// Response for `GET /api/receipts/{id}`: flat Receipt header fields plus a
/// `transactions` list and a presigned `image_url` (may be null).
class ReceiptDetail {
  final Receipt receipt;
  final List<Transaction> transactions;
  final String? imageUrl;

  ReceiptDetail({
    required this.receipt,
    required this.transactions,
    this.imageUrl,
  });

  factory ReceiptDetail.fromJson(Map<String, dynamic> json) {
    return ReceiptDetail(
      receipt: Receipt.fromJson(json),
      transactions: json['transactions'] != null
          ? (json['transactions'] as List)
              .map((t) => Transaction.fromJson(t as Map<String, dynamic>))
              .toList()
          : [],
      imageUrl: json['image_url'] as String?,
    );
  }
}

class ReceiptListResponse {
  final List<Receipt> receipts;
  final int totalCount;

  ReceiptListResponse({required this.receipts, required this.totalCount});

  factory ReceiptListResponse.fromJson(Map<String, dynamic> json) {
    return ReceiptListResponse(
      receipts: (json['receipts'] as List)
          .map((r) => Receipt.fromJson(r as Map<String, dynamic>))
          .toList(),
      totalCount: (json['total_count'] as num).toInt(),
    );
  }
}

/// Response for `GET /api/receipts/{id}/status`.
class ExtractionStatus {
  final String status;
  final double? confidence;

  ExtractionStatus({required this.status, this.confidence});

  factory ExtractionStatus.fromJson(Map<String, dynamic> json) {
    return ExtractionStatus(
      status: json['extraction_status'] as String? ?? 'pending',
      confidence: _toDouble(json['extraction_conf']),
    );
  }
}
