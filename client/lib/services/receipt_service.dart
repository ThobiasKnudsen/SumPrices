import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/receipt.dart';
import 'api_client.dart';

class ReceiptService {
  final ApiClient _api;

  ReceiptService(this._api);

  /// Uploads a receipt as raw bytes (web-safe, no `dart:io`).
  ///
  /// Images (jpg/png/webp) are sent under the multipart field `image`; PDFs are
  /// sent under `pdf`, chosen by the file extension.
  Future<Receipt> upload({
    required Uint8List bytes,
    required String filename,
  }) async {
    final isPdf = filename.toLowerCase().endsWith('.pdf');
    final field = isPdf ? 'pdf' : 'image';

    final formData = FormData.fromMap({
      field: MultipartFile.fromBytes(bytes, filename: filename),
    });

    final response = await _api.dio.post(
      '/api/receipts',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return Receipt.fromJson(response.data);
  }

  Future<ReceiptListResponse> list({
    int page = 1,
    int perPage = 20,
    String? store,
    String? from,
    String? to,
    String? status,
  }) async {
    final response = await _api.dio.get('/api/receipts', queryParameters: {
      'page': page,
      'per_page': perPage,
      if (store != null) 'store': store,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (status != null) 'status': status,
    });
    return ReceiptListResponse.fromJson(response.data);
  }

  Future<ReceiptDetail> getOne(String id) async {
    final response = await _api.dio.get('/api/receipts/$id');
    return ReceiptDetail.fromJson(response.data);
  }

  Future<Receipt> update(String id, Map<String, dynamic> data) async {
    final response = await _api.dio.put('/api/receipts/$id', data: data);
    return Receipt.fromJson(response.data);
  }

  Future<void> delete(String id) async {
    await _api.dio.delete('/api/receipts/$id');
  }

  Future<ExtractionStatus> checkExtractionStatus(String id) async {
    final response = await _api.dio.get('/api/receipts/$id/status');
    return ExtractionStatus.fromJson(response.data);
  }
}
