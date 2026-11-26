import 'local_store.dart';

Future<void> saveList(LocalStore store, String key, List<Map<String, dynamic>> rows) async {
  try {
    await store.putJson(key, rows);
  } catch (_) {}
}

Future<List<Map<String, dynamic>>> loadList(LocalStore store, String key) async {
  try {
    final raw = await store.getJson(key);
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }
  } catch (_) {}
  return const [];
}

bool rowMatches(Map<String, dynamic> row, String query, List<String> keys) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  final order = row['order'];
  final extra = order is Map ? Map<String, dynamic>.from(order) : const <String, dynamic>{};
  for (final key in keys) {
    final value = '${row[key] ?? extra[key] ?? ''}'.toLowerCase();
    if (value.contains(needle)) return true;
  }
  return false;
}
