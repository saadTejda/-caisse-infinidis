import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/staff_user.dart';
import '../db/local_store.dart';
import '../services/order_queue.dart';
import '../services/print_service.dart';
import '../services/sync_service.dart';

final localStoreProvider = Provider<LocalStore>((_) => LocalStore());

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref.watch(dioProvider), ref.watch(localStoreProvider));
});

final orderQueueProvider = Provider<OrderQueue>((ref) {
  return OrderQueue(ref.watch(dioProvider), ref.watch(localStoreProvider));
});

final printServiceProvider = Provider<PrintService>((_) => PrintService());

final localeCodeProvider = StateProvider<String>((ref) => 'fr');

final staffUserProvider = StateProvider<StaffUser>((ref) => StaffUser.empty);

final onlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  Future<bool> map(List<ConnectivityResult> results) async {
    return results.any((r) => r != ConnectivityResult.none);
  }

  yield await map(await connectivity.checkConnectivity());
  await for (final event in connectivity.onConnectivityChanged) {
    yield await map(event);
  }
});
