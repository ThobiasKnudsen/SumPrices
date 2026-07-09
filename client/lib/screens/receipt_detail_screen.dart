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
    final transactions = _detail!.transactions;
    final imageUrl = _detail!.imageUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(receipt.storeNameRaw ?? 'Receipt'),
        actions: [
          IconButton(icon: const Icon(Icons.delete), onPressed: _deleteReceipt),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDetail,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Receipt image preview (presigned URL, web-safe)
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const SizedBox(
                    height: 120,
                    child: Center(child: Text('Could not load image')),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Receipt header card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow('Store', receipt.storeNameRaw ?? 'Unknown'),
                    _InfoRow('Date', receipt.purchaseAt ?? 'Unknown'),
                    _InfoRow(
                      'Total',
                      receipt.total != null
                          ? '${receipt.total!.toStringAsFixed(2)} ${receipt.currency}'
                          : '--',
                    ),
                    _InfoRow('Status', receipt.extractionStatus),
                    if (receipt.extractionConf != null)
                      _InfoRow('Confidence',
                          '${(receipt.extractionConf! * 100).toStringAsFixed(0)}%'),
                    if (receipt.needsReview)
                      _InfoRow('Review', 'Needs review'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Transactions
            Text('Items (${transactions.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (transactions.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No items extracted yet')),
                ),
              )
            else
              ...transactions.map((t) => Card(
                    child: ListTile(
                      title: Text(t.displayDescription),
                      subtitle: Text(_transactionSubtitle(t)),
                      trailing: Text(
                        t.lineTotal != null
                            ? t.lineTotal!.toStringAsFixed(2)
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

  String _transactionSubtitle(Transaction t) {
    final parts = <String>[];
    if (t.quantity != null) {
      final qty = t.quantity!;
      final qtyStr = qty == qty.roundToDouble()
          ? qty.toStringAsFixed(0)
          : qty.toStringAsFixed(1);
      parts.add('Qty: $qtyStr${t.unit != null ? " ${t.unit}" : ""}');
    }
    if (t.unitPrice != null) {
      parts.add('@ ${t.unitPrice!.toStringAsFixed(2)}');
    }
    if (t.itemType != 'product' && t.itemType.isNotEmpty) {
      parts.add(t.itemType);
    }
    return parts.join('  ·  ');
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
