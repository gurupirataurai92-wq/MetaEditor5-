import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/local_db.dart';
import '../sync/sync_engine.dart';

/// Offline-first POS: the sale commits to SQLite *first* (instant, works
/// with the network off), is queued in the outbox, and reaches the server
/// whenever connectivity allows.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _uuid = const Uuid();
  final Map<String, int> _cart = {}; // product id → qty
  List<Map<String, Object?>> _products = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final db = await LocalDb.instance.db;
    final rows = await db.query('products', orderBy: 'name');
    setState(() => _products = rows);
  }

  double get _total => _cart.entries.fold(0, (sum, entry) {
        final product = _products.firstWhere((p) => p['id'] == entry.key);
        return sum + double.parse(product['sell_price'] as String) * entry.value;
      });

  Future<void> _checkout() async {
    final db = await LocalDb.instance.db;
    final lamport = await LocalDb.instance.nextLamport();
    final saleId = _uuid.v4();
    final payload = {
      'id': saleId,
      'currency': 'USD',
      'lamport': lamport,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'lines': [
        for (final entry in _cart.entries)
          {'product_id': entry.key, 'qty': entry.value}
      ],
    };

    await db.transaction((txn) async {
      await txn.insert('sales', {
        'id': saleId,
        'total': _total.toStringAsFixed(2),
        'currency': 'USD',
        'exchange_rate': '1',
        'captured_at': payload['captured_at'] as String,
        'payload': jsonEncode(payload),
      });
      for (final entry in _cart.entries) {
        await txn.insert('stock_movements', {
          'id': _uuid.v4(),
          'product_id': entry.key,
          'qty': -entry.value,
          'movement_type': 'sale',
          'reference': saleId,
        });
      }
      await txn.insert('outbox', {
        'op_id': _uuid.v4(),
        'entity': 'sale',
        'action': 'create',
        'lamport': lamport,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });

    setState(_cart.clear);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sale saved — will sync when online')),
      );
    }
    SyncEngine.instance.sync(); // opportunistic; a no-op offline
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SIMS AI — Point of Sale')),
      body: _products.isEmpty
          ? const Center(child: Text('No products yet — sync or add stock.'))
          : ListView(
              children: [
                for (final product in _products)
                  ListTile(
                    title: Text(product['name'] as String),
                    subtitle: Text('\$${product['sell_price']}'),
                    trailing: Text('×${_cart[product['id']] ?? 0}'),
                    onTap: () => setState(() => _cart.update(
                        product['id'] as String, (q) => q + 1,
                        ifAbsent: () => 1)),
                  ),
              ],
            ),
      bottomNavigationBar: _cart.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _checkout,
                child: Text('Charge \$${_total.toStringAsFixed(2)}'),
              ),
            ),
    );
  }
}
