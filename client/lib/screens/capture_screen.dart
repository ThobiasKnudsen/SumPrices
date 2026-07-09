import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/receipt_provider.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  Uint8List? _bytes;
  String? _filename;
  bool _isUploading = false;
  bool _isPolling = false;
  String? _extractionStatus;

  bool get _isPdf => _filename?.toLowerCase().endsWith('.pdf') ?? false;

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true, // required on web to get bytes back
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the selected file')),
        );
      }
      return;
    }

    setState(() {
      _bytes = file.bytes;
      _filename = file.name;
    });
  }

  Future<void> _upload() async {
    final bytes = _bytes;
    final filename = _filename;
    if (bytes == null || filename == null) return;

    setState(() => _isUploading = true);

    final provider = context.read<ReceiptProvider>();
    final receipt =
        await provider.uploadReceipt(bytes: bytes, filename: filename);

    if (receipt == null) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.error ?? 'Upload failed')),
        );
      }
      return;
    }

    // Start polling for extraction completion.
    setState(() {
      _isUploading = false;
      _isPolling = true;
      _extractionStatus = receipt.extractionStatus;
    });

    await _pollExtractionStatus(receipt.id);
  }

  Future<void> _pollExtractionStatus(String receiptId) async {
    final provider = context.read<ReceiptProvider>();

    while (mounted && _isPolling) {
      await Future.delayed(const Duration(seconds: 2));

      final status = await provider.checkExtractionStatus(receiptId);
      if (status == null) continue;

      setState(() => _extractionStatus = status.status);

      const terminal = {'done', 'failed', 'needs_review'};
      if (terminal.contains(status.status)) {
        setState(() => _isPolling = false);
        if (mounted) {
          if (status.status == 'failed') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Extraction failed')),
            );
          } else {
            // 'done' or 'needs_review' — both have a receipt worth viewing.
            Navigator.of(context).pop(receiptId);
          }
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
      appBar: AppBar(title: const Text('Upload Receipt')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildPreview()),
            const SizedBox(height: 16),
            if (_isUploading || _isPolling)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    _isPolling
                        ? 'Processing receipt (${_extractionStatus ?? "..."})'
                        : 'Uploading...',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              )
            else ...[
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.attach_file),
                label: Text(_bytes == null
                    ? 'Choose image or PDF'
                    : 'Choose a different file'),
              ),
              const SizedBox(height: 12),
              if (_bytes != null)
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

  Widget _buildPreview() {
    if (_bytes == null) {
      return Container(
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
              Text('Select a receipt image or PDF'),
            ],
          ),
        ),
      );
    }

    if (_isPdf) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_filename ?? 'PDF selected'),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(_bytes!, fit: BoxFit.contain),
    );
  }
}
