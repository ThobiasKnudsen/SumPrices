import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';

class _SpendingPeriod {
  final String label;
  final double total;
  _SpendingPeriod({required this.label, required this.total});
}

class _StoreSpending {
  final String name;
  final double total;
  final int count;
  _StoreSpending({required this.name, required this.total, required this.count});
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isLoading = true;
  String _period = 'month';
  List<_SpendingPeriod> _spending = [];
  List<_StoreSpending> _stores = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final api = context.read<ApiClient>();

    try {
      final spendingRes = await api.dio.get('/api/analytics/spending', queryParameters: {
        'period': _period,
      });
      final storeRes = await api.dio.get('/api/analytics/by-store');

      final periods = (spendingRes.data['periods'] as List).map((p) {
        return _SpendingPeriod(
          label: p['label'] ?? '',
          total: p['total'] != null ? double.tryParse(p['total'].toString()) ?? 0 : 0,
        );
      }).toList();

      final stores = (storeRes.data['stores'] as List).map((s) {
        return _StoreSpending(
          name: s['name'] ?? 'Unknown',
          total: s['total'] != null ? double.tryParse(s['total'].toString()) ?? 0 : 0,
          count: s['count'] ?? 0,
        );
      }).toList();

      setState(() {
        _spending = periods;
        _stores = stores;
      });
    } catch (_) {
      // Silently fail for now
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_spending.isEmpty && _stores.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No data yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
            SizedBox(height: 8),
            Text('Scan some receipts to see analytics'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Period toggle
          Row(
            children: [
              Text('Spending by', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'week', label: Text('Week')),
                  ButtonSegment(value: 'month', label: Text('Month')),
                ],
                selected: {_period},
                onSelectionChanged: (v) {
                  setState(() => _period = v.first);
                  _loadData();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Spending bar chart
          if (_spending.isNotEmpty)
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${_spending[groupIndex].total.toStringAsFixed(0)} NOK',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= _spending.length) return const Text('');
                          final label = _spending[idx].label;
                          // Show shortened label
                          return Text(
                            label.length >= 7 ? label.substring(5, 7) : label,
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _spending.asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.total,
                          color: Colors.green,
                          width: 20,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),

          const SizedBox(height: 32),

          // Store breakdown
          Text('Spending by store', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_stores.isNotEmpty)
            ..._stores.map((store) {
              final maxTotal = _stores.first.total;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(store.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text('${store.total.toStringAsFixed(0)} NOK (${store.count} receipts)'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: maxTotal > 0 ? store.total / maxTotal : 0,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
