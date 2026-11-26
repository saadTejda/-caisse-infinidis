import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
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
  final dio = ref.watch(dioProvider);
  final connectivity = Connectivity();

  Future<bool> probe() async {
    try {
      final results = await connectivity.checkConnectivity();
      if (!results.any((result) => result != ConnectivityResult.none)) return false;
    } catch (_) {
      return false;
    }
    try {
      await dio.get(
        '/api/v1/pos/cash-status',
        options: Options(
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          validateStatus: (code) => code != null && code < 500,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  yield await probe();
  final ticks = StreamController<void>();
  final timer = Timer.periodic(const Duration(seconds: 20), (_) => ticks.add(null));
  final subscription = connectivity.onConnectivityChanged.listen((_) => ticks.add(null));
  ref.onDispose(() {
    timer.cancel();
    subscription.cancel();
    ticks.close();
  });
  await for (final _ in ticks.stream) {
    yield await probe();
  }
});
