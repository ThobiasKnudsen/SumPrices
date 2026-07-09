import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/transaction_service.dart';
import 'receipt_detail_screen.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  late final TransactionService _transactionService;
  final _searchController = TextEditingController();
  List<TransactionWithContext> _items = [];
  int _totalCount = 0;
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _transactionService = TransactionService(context.read<ApiClient>());
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadItems({String? query}) async {
    setState(() => _isLoading = true);

    try {
      final response = await _transactionService.list(q: query);
      setState(() {
        _items = response.transactions;
        _totalCount = response.totalCount;
      });
    } catch (_) {
      // Handle error silently for now
    }

    setState(() => _isLoading = false);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _loadItems(query: value.isEmpty ? null : value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search items...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('$_totalCount items', style: const TextStyle(color: Colors.grey)),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _isLoading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(child: Text('No items found'))
                  : RefreshIndicator(
                      onRefresh: () => _loadItems(
                        query: _searchController.text.isEmpty
                            ? null
                            : _searchController.text,
                      ),
                      child: ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: ListTile(
                              title: Text(item.displayDescription),
                              subtitle: Text(
                                '${item.storeNameRaw ?? "Unknown store"} - ${item.purchaseAt ?? ""}',
                              ),
                              trailing: Text(
                                item.lineTotal != null
                                    ? item.lineTotal!.toStringAsFixed(2)
                                    : '--',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ReceiptDetailScreen(
                                        receiptId: item.receiptId),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
