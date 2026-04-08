import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/receipt.dart';
import '../providers/receipt_provider.dart';

class ReceiptDetailScreen extends StatefulWidget {
  final String receiptId;
  const ReceiptDetailScreen({super.key, required this.receiptId});

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  ReceiptDetail? _detail;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final provider = context.read<ReceiptProvider>();
    final detail = await provider.getReceipt(widget.receiptId);
    if (mounted) {
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteReceipt() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete receipt?'),
        content: const Text('This will permanently delete this receipt and all its items.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await context.read<ReceiptProvider>().deleteReceipt(widget.receiptId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Receipt')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Receipt')),
        body: const Center(child: Text('Receipt not found')),
      );
    }

    final receipt = _detail!.receipt;
    final items = _detail!.items;

    return Scaffold(
      appBar: AppBar(
        title: Text(receipt.storeName ?? 'Receipt'),
        actions: [
          IconButton(icon: const Icon(Icons.delete), onPressed: _deleteReceipt),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDetail,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Receipt header card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow('Store', receipt.storeName ?? 'Unknown'),
                    _InfoRow('Date', receipt.purchaseDate ?? 'Unknown'),
                    _InfoRow(
                      'Total',
                      receipt.total != null
                          ? '${receipt.total!.toStringAsFixed(2)} ${receipt.currency ?? "NOK"}'
                          : '--',
                    ),
                    _InfoRow('OCR Status', receipt.ocrStatus),
                    if (receipt.ocrConfidence != null)
                      _InfoRow('Confidence', '${(receipt.ocrConfidence! * 100).toStringAsFixed(0)}%'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Items
            Text('Items (${items.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No items extracted yet')),
                ),
              )
            else
              ...items.map((item) => Card(
                    child: ListTile(
                      title: Text(item.description),
                      subtitle: item.quantity != null
                          ? Text('Qty: ${item.quantity!.toStringAsFixed(item.quantity == item.quantity!.roundToDouble() ? 0 : 1)}')
                          : null,
                      trailing: Text(
                        item.lineTotal != null
                            ? item.lineTotal!.toStringAsFixed(2)
                            : '--',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
