import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/receipt.dart';
import '../services/api_client.dart';
import '../services/receipt_service.dart';

class ReceiptProvider extends ChangeNotifier {
  final ReceiptService _receiptService;

  List<Receipt> _receipts = [];
  int _totalCount = 0;
  bool _isLoading = false;
  String? _error;

  List<Receipt> get receipts => _receipts;
  int get totalCount => _totalCount;
  bool get isLoading => _isLoading;
  String? get error => _error;

  ReceiptProvider(ApiClient api) : _receiptService = ReceiptService(api);

  Future<void> loadReceipts({int page = 1}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _receiptService.list(page: page);
      _receipts = response.receipts;
      _totalCount = response.totalCount;
    } on DioException catch (e) {
      _error = e.response?.data?['error'] ?? 'Failed to load receipts';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<Receipt?> uploadReceipt({
    required Uint8List bytes,
    required String filename,
  }) async {
    try {
      final receipt =
          await _receiptService.upload(bytes: bytes, filename: filename);
      _receipts.insert(0, receipt);
      _totalCount++;
      notifyListeners();
      return receipt;
    } on DioException catch (e) {
      _error = e.response?.data?['error'] ?? 'Upload failed';
      notifyListeners();
      return null;
    }
  }

  Future<ReceiptDetail?> getReceipt(String id) async {
    try {
      return await _receiptService.getOne(id);
    } on DioException catch (e) {
      _error = e.response?.data?['error'] ?? 'Failed to load receipt';
      notifyListeners();
      return null;
    }
  }

  Future<ExtractionStatus?> checkExtractionStatus(String id) async {
    try {
      return await _receiptService.checkExtractionStatus(id);
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteReceipt(String id) async {
    try {
      await _receiptService.delete(id);
      _receipts.removeWhere((r) => r.id == id);
      _totalCount--;
      notifyListeners();
    } on DioException catch (e) {
      _error = e.response?.data?['error'] ?? 'Delete failed';
      notifyListeners();
    }
  }
}
