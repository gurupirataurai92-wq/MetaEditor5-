import 'package:sqflite/sqflite.dart';

/// Local replica + outbox. Mirrors the server's event-sourced design:
/// sales and stock movements are immutable rows; stock-on-hand is a fold.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    return openDatabase(
      'sims_ai.db',
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, sku TEXT, barcode TEXT,
            sell_price TEXT NOT NULL, currency TEXT NOT NULL DEFAULT 'USD',
            lamport INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE sales (
            id TEXT PRIMARY KEY, total TEXT NOT NULL, currency TEXT NOT NULL,
            exchange_rate TEXT NOT NULL, captured_at TEXT NOT NULL,
            payload TEXT NOT NULL,            -- full JSON for sync replay
            synced INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE stock_movements (
            id TEXT PRIMARY KEY, product_id TEXT NOT NULL, qty INTEGER NOT NULL,
            movement_type TEXT NOT NULL, reference TEXT
          )''');
        await db.execute('''
          CREATE TABLE outbox (
            op_id TEXT PRIMARY KEY, entity TEXT NOT NULL, action TEXT NOT NULL,
            lamport INTEGER NOT NULL, payload TEXT NOT NULL,
            created_at TEXT NOT NULL
          )''');
        await db.execute(
            'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      },
    );
  }

  /// Lamport clock: monotonically increasing, survives restarts.
  Future<int> nextLamport() async {
    final database = await db;
    return database.transaction((txn) async {
      final rows = await txn
          .query('meta', where: 'key = ?', whereArgs: ['lamport'], limit: 1);
      final current =
          rows.isEmpty ? 0 : int.parse(rows.first['value'] as String);
      final next = current + 1;
      await txn.insert('meta', {'key': 'lamport', 'value': '$next'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      return next;
    });
  }

  Future<int> onHand(String productId) async {
    final database = await db;
    final rows = await database.rawQuery(
        'SELECT COALESCE(SUM(qty), 0) AS total FROM stock_movements '
        'WHERE product_id = ?',
        [productId]);
    return (rows.first['total'] as int?) ?? 0;
  }
}
