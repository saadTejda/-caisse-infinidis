import 'package:cafe_resto_caisse/db/list_cache.dart';
import 'package:cafe_resto_caisse/services/order_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la file retire les champs locaux et vise la bonne adresse', () {
    expect(queuePath('sale'), '/api/v1/orders');
    expect(queuePath('sale_update', orderId: 10), '/api/v1/orders/10/changes');
    expect(queuePath('sale_cancel', orderId: 10), '/api/v1/orders/10/cancel');
    expect(queuePath('delivery_assign', deliveryId: 4), '/api/v1/deliveries/4/assign');
    expect(queuePath('delivery_status', deliveryId: 4), '/api/v1/deliveries/4/status');
    expect(queuePath('driver_payment', deliveryId: 4), '/api/v1/deliveries/4/driver-payment');
    final sent = stripPrivate({
      '_op': 'sale',
      '_local_total': 12.5,
      'payment_method': 'cash',
    });
    expect(sent.containsKey('_local_total'), isFalse);
    expect(sent['payment_method'], 'cash');
  });

  test('la recherche commande lit le code, le client et le téléphone', () {
    const row = {
      'public_ref': 'T-10',
      'customer_name': 'Amina',
      'customer_phone': '0612',
    };
    expect(rowMatches(row, 't-10', const ['public_ref', 'customer_name', 'customer_phone']), isTrue);
    expect(rowMatches(row, 'amina', const ['public_ref', 'customer_name', 'customer_phone']), isTrue);
    expect(rowMatches(row, '0612', const ['public_ref', 'customer_name', 'customer_phone']), isTrue);
    expect(rowMatches(row, 'karim', const ['public_ref', 'customer_name', 'customer_phone']), isFalse);
  });
}
