import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Base locale : catalogue, contacts, ventes à envoyer et réglages (clé → JSON).
class LocalDb {
  LocalDb._(this._db);

  final Database _db;

  static Future<LocalDb> open() async {
    final path = p.join(await getDatabasesPath(), 'infinidis_pos.db');
    final db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT NOT NULL)');
      await db.execute('CREATE TABLE products (variant_id INTEGER PRIMARY KEY, sku TEXT, barcode TEXT, name TEXT, json TEXT NOT NULL)');
      await db.execute('CREATE INDEX products_codes ON products (barcode, sku)');
      await db.execute('CREATE TABLE contacts (id INTEGER PRIMARY KEY, name TEXT, phone TEXT, json TEXT NOT NULL)');
      await db.execute('CREATE TABLE outbox (uuid TEXT PRIMARY KEY, local_number TEXT NOT NULL, payload TEXT NOT NULL, ticket TEXT NOT NULL, '
          'status TEXT NOT NULL, message TEXT, number TEXT, tries INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, synced_at TEXT)');
    });
    return LocalDb._(db);
  }

  Future<void> setValue(String key, Object? value) async {
    await _db.insert('kv', {'k': key, 'v': jsonEncode(value)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<dynamic> getValue(String key) async {
    final rows = await _db.query('kv', where: 'k = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : jsonDecode(rows.first['v'] as String);
  }

  Future<void> replaceProducts(List<Product> items) async {
    await _db.transaction((txn) async {
      await txn.delete('products');
      final batch = txn.batch();
      for (final item in items) {
        batch.insert('products', {'variant_id': item.variantId, 'sku': item.sku, 'barcode': item.barcode, 'name': item.label.toLowerCase(), 'json': jsonEncode(item.toJson())});
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> saveProduct(Product item) async {
    await _db.update('products', {'json': jsonEncode(item.toJson())}, where: 'variant_id = ?', whereArgs: [item.variantId]);
  }

  Future<List<Product>> products({String query = ''}) async {
    final q = query.trim().toLowerCase();
    final rows = q.isEmpty
        ? await _db.query('products', orderBy: 'name', limit: 400)
        : await _db.query('products', where: 'name LIKE ? OR sku LIKE ? OR barcode LIKE ?', whereArgs: ['%$q%', '%$q%', '%$q%'], orderBy: 'name', limit: 200);
    return rows.map((r) => Product.fromJson(jsonDecode(r['json'] as String) as Map<String, dynamic>)).toList();
  }

  Future<Product?> productByCode(String code) async {
    final c = code.trim();
    final rows = await _db.query('products', where: 'barcode = ? OR sku = ?', whereArgs: [c, c], limit: 1);
    return rows.isEmpty ? null : Product.fromJson(jsonDecode(rows.first['json'] as String) as Map<String, dynamic>);
  }

  Future<int> productCount() async => Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM products')) ?? 0;

  Future<void> replaceContacts(List<Contact> items) async {
    await _db.transaction((txn) async {
      await txn.delete('contacts');
      final batch = txn.batch();
      for (final item in items) {
        batch.insert('contacts', {'id': item.id, 'name': item.name.toLowerCase(), 'phone': item.phone, 'json': jsonEncode(item.toJson())});
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Contact>> contacts({String query = ''}) async {
    final q = query.trim().toLowerCase();
    final rows = q.isEmpty
        ? await _db.query('contacts', orderBy: 'name', limit: 100)
        : await _db.query('contacts', where: 'name LIKE ? OR phone LIKE ?', whereArgs: ['%$q%', '%$q%'], orderBy: 'name', limit: 100);
    return rows.map((r) => Contact.fromJson(jsonDecode(r['json'] as String) as Map<String, dynamic>)).toList();
  }

  Future<void> saveContact(Contact item) async {
    await _db.insert('contacts', {'id': item.id, 'name': item.name.toLowerCase(), 'phone': item.phone, 'json': jsonEncode(item.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> contactCount() async => Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM contacts')) ?? 0;

  Future<void> enqueue({required String uuid, required String localNumber, required Map<String, dynamic> payload, required Map<String, dynamic> ticket}) async {
    await _db.insert('outbox', {
      'uuid': uuid,
      'local_number': localNumber,
      'payload': jsonEncode(payload),
      'ticket': jsonEncode(ticket),
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> outbox({List<String> statuses = const ['pending', 'error']}) async {
    final rows = await _db.query('outbox', where: 'status IN (${List.filled(statuses.length, '?').join(',')})', whereArgs: statuses, orderBy: 'created_at');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> markSent(String uuid, String number) async {
    await _db.update('outbox', {'status': 'sent', 'number': number, 'message': null, 'synced_at': DateTime.now().toIso8601String()}, where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<void> markError(String uuid, String message, {required bool retry}) async {
    await _db.rawUpdate('UPDATE outbox SET status = ?, message = ?, tries = tries + 1 WHERE uuid = ?', [retry ? 'pending' : 'error', message, uuid]);
  }

  Future<void> retry(String uuid) async {
    await _db.update('outbox', {'status': 'pending', 'message': null}, where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<void> deleteOutbox(String uuid) async {
    await _db.delete('outbox', where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<int> pendingCount() async => Sqflite.firstIntValue(await _db.rawQuery("SELECT COUNT(*) FROM outbox WHERE status = 'pending'")) ?? 0;

  Future<int> errorCount() async => Sqflite.firstIntValue(await _db.rawQuery("SELECT COUNT(*) FROM outbox WHERE status = 'error'")) ?? 0;

  /// Tout effacer (changement de serveur ou de compte).
  Future<void> wipe() async {
    await _db.delete('kv');
    await _db.delete('products');
    await _db.delete('contacts');
    await _db.delete('outbox');
  }
}
