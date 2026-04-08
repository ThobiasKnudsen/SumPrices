import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/receipt_provider.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  File? _imageFile;
  bool _isUploading = false;
  bool _isPolling = false;
  String? _ocrStatus;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _upload() async {
    if (_imageFile == null) return;

    setState(() => _isUploading = true);

    final provider = context.read<ReceiptProvider>();
    final receipt = await provider.uploadReceipt(_imageFile!);

    if (receipt == null) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.error ?? 'Upload failed')),
        );
      }
      return;
    }

    // Start polling for OCR completion
    setState(() {
      _isUploading = false;
      _isPolling = true;
      _ocrStatus = receipt.ocrStatus;
    });

    await _pollOcrStatus(receipt.id);
  }

  Future<void> _pollOcrStatus(String receiptId) async {
    final provider = context.read<ReceiptProvider>();

    while (mounted && _isPolling) {
      await Future.delayed(const Duration(seconds: 2));

      final status = await provider.checkOcrStatus(receiptId);
      if (status == null) continue;

      setState(() => _ocrStatus = status.status);

      if (status.status == 'done' || status.status == 'failed') {
        setState(() => _isPolling = false);
        if (mounted && status.status == 'done') {
          Navigator.of(context).pop(receiptId);
        }
        break;
      }
    }
  }

  @override
  void dispose() {
    _isPolling = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Receipt')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _imageFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(_imageFile!, fit: BoxFit.contain),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('Take a photo or pick from gallery'),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            if (_isUploading || _isPolling)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    _isPolling
                        ? 'Processing receipt (${_ocrStatus ?? "..."})'
                        : 'Uploading...',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_imageFile != null)
                FilledButton.icon(
                  onPressed: _upload,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Upload & Scan'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
