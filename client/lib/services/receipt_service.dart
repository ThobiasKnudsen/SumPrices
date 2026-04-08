import 'dart:io';

import 'package:dio/dio.dart';

import '../models/receipt.dart';
import 'api_client.dart';

class ReceiptService {
  final ApiClient _api;

  ReceiptService(this._api);

  Future<Receipt> upload(File imageFile) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        imageFile.path,
        filename: 'receipt.jpg',
      ),
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
  }) async {
    final response = await _api.dio.get('/api/receipts', queryParameters: {
      'page': page,
      'per_page': perPage,
      if (store != null) 'store': store,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
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

  Future<OcrStatus> checkOcrStatus(String id) async {
    final response = await _api.dio.get('/api/receipts/$id/status');
    return OcrStatus.fromJson(response.data);
  }
}
