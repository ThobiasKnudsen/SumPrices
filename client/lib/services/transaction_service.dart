import '../models/receipt.dart';
import 'api_client.dart';

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

class TransactionListResponse {
  final List<TransactionWithContext> transactions;
  final int totalCount;

  TransactionListResponse({
    required this.transactions,
    required this.totalCount,
  });

  factory TransactionListResponse.fromJson(Map<String, dynamic> json) {
    return TransactionListResponse(
      transactions: (json['transactions'] as List)
          .map((t) => TransactionWithContext.fromJson(t as Map<String, dynamic>))
          .toList(),
      totalCount: (json['total_count'] as num).toInt(),
    );
  }
}

/// A [Transaction] enriched with its receipt's store/date context, as returned
/// by `GET /api/transactions`.
class TransactionWithContext {
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
  final String? storeNameRaw;
  final String? purchaseAt;

  TransactionWithContext({
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
    this.storeNameRaw,
    this.purchaseAt,
  });

  String get displayDescription =>
      (descriptionClean != null && descriptionClean!.isNotEmpty)
          ? descriptionClean!
          : descriptionRaw;

  factory TransactionWithContext.fromJson(Map<String, dynamic> json) {
    return TransactionWithContext(
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
      storeNameRaw: json['store_name_raw'] as String?,
      purchaseAt: json['purchase_at'] as String?,
    );
  }
}

class TransactionService {
  final ApiClient _api;

  TransactionService(this._api);

  Future<TransactionListResponse> list({
    int page = 1,
    int perPage = 50,
    String? q,
    String? store,
    String? from,
    String? to,
  }) async {
    final response = await _api.dio.get('/api/transactions', queryParameters: {
      'page': page,
      'per_page': perPage,
      if (q != null && q.isNotEmpty) 'q': q,
      if (store != null) 'store': store,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
    return TransactionListResponse.fromJson(response.data);
  }

  Future<Transaction> update(int id, Map<String, dynamic> data) async {
    final response = await _api.dio.put('/api/transactions/$id', data: data);
    return Transaction.fromJson(response.data);
  }

  Future<void> delete(int id) async {
    await _api.dio.delete('/api/transactions/$id');
  }
}
