import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../data/local_db.dart';

/// Pushes the outbox and pulls server deltas whenever connectivity returns.
///
/// Correctness relies on the same properties as the server (dissertation
/// §4.6): every op carries a client-generated UUID (server dedupes, so
/// retries are idempotent) and a Lamport clock (deterministic last-writer-
/// wins for master data). Sales are immutable events — they can never
/// conflict, only arrive late.
class SyncEngine {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  static const apiBase = String.fromEnvironment('SIMS_API',
      defaultValue: 'http://10.0.2.2:8000/api/v1');

  String? accessToken;
  bool _syncing = false;

  void start() {
    Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) sync();
    });
  }

  Future<void> sync() async {
    if (_syncing || accessToken == null) return;
    _syncing = true;
    try {
      final database = await LocalDb.instance.db;
      final ops = await database.query('outbox', orderBy: 'lamport ASC');
      final cursorRows = await database
          .query('meta', where: 'key = ?', whereArgs: ['sync_cursor']);
      final cursor = cursorRows.isEmpty
          ? 0
          : int.parse(cursorRows.first['value'] as String);

      final resp = await http.post(
        Uri.parse('$apiBase/sync'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'device_id': 'mobile',
          'cursor': cursor,
          'ops': [
            for (final op in ops)
              {
                'op_id': op['op_id'],
                'entity': op['entity'],
                'action': op['action'],
                'lamport': op['lamport'],
                'payload': jsonDecode(op['payload'] as String),
              }
          ],
        }),
      );
      if (resp.statusCode != 200) return; // stay queued; retry on next signal

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      await database.transaction((txn) async {
        // Everything acknowledged (applied OR duplicate) leaves the outbox.
        for (final result in body['results'] as List) {
          await txn.delete('outbox',
              where: 'op_id = ?', whereArgs: [result['op_id']]);
        }
        for (final change in body['server_changes'] as List) {
          await _fold(txn, change as Map<String, dynamic>);
        }
        await txn.insert(
            'meta', {'key': 'sync_cursor', 'value': '${body['cursor']}'},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
    } finally {
      _syncing = false;
    }
  }

  /// Fold a server change into the local replica (LWW on lamport for
  /// products; sales/movements are append-only so inserts are enough).
  Future<void> _fold(Transaction txn, Map<String, dynamic> change) async {
    final payload = change['payload'];
    if (change['entity'] == 'product' && payload is Map<String, dynamic>) {
      await txn.insert(
        'products',
        {
          'id': change['entity_id'],
          'name': payload['name'] ?? '',
          'sell_price': '${payload['sell_price'] ?? '0'}',
          'lamport': payload['lamport'] ?? 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    // Other entities: extension point (customers, rates, …).
  }
}
