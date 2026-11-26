import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalStore {
  Database? _db;

  Future<Database> get db async {
    if (_db != null) {
      return _db!;
    }
    final path = p.join(await getDatabasesPath(), 'caisse_local.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE kv (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE pending_orders (
            id TEXT PRIMARY KEY NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> putJson(String key, Object value) async {
    final database = await db;
    await database.insert(
      'kv',
      {'key': key, 'value': jsonEncode(value)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> getJson(String key) async {
    final database = await db;
    final rows = await database.query('kv', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) {
      return null;
    }
    return jsonDecode(rows.first['value'] as String);
  }

  Future<void> enqueueOrder(String id, Map<String, dynamic> payload, String createdAt) async {
    final database = await db;
    await database.insert(
      'pending_orders',
      {
        'id': id,
        'payload': jsonEncode(payload),
        'created_at': createdAt,
        'attempts': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> pendingOrders() async {
    final database = await db;
    final rows = await database.query('pending_orders', orderBy: 'created_at ASC');
    return rows
        .map(
          (row) => {
            'id': row['id'],
            'payload': jsonDecode(row['payload'] as String) as Map<String, dynamic>,
            'created_at': row['created_at'],
            'attempts': row['attempts'],
            'last_error': row['last_error'],
          },
        )
        .toList();
  }

  Future<void> removePending(String id) async {
    final database = await db;
    await database.delete('pending_orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> nextOfflineNumber() async {
    final current = await getJson('offline_seq');
    final next = (current is int ? current : int.tryParse('$current') ?? 0) + 1;
    await putJson('offline_seq', next);
    return next;
  }

  Future<void> updatePending(String id, Map<String, dynamic> payload) async {
    final database = await db;
    await database.update(
      'pending_orders',
      {
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'last_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> bumpPending(String id, String error) async {
    final database = await db;
    await database.rawUpdate(
      'UPDATE pending_orders SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }
}
