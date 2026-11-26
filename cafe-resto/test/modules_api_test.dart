import 'package:cafe_resto_caisse/api/api_client.dart';
import 'package:cafe_resto_caisse/api/api_error.dart';
import 'package:cafe_resto_caisse/auth/staff_user.dart';
import 'package:cafe_resto_caisse/providers/app_providers.dart';
import 'package:cafe_resto_caisse/screens/business_settings_screen.dart';
import 'package:cafe_resto_caisse/screens/cash_screen.dart';
import 'package:cafe_resto_caisse/screens/catalog_screen.dart';
import 'package:cafe_resto_caisse/screens/dashboard_screen.dart';
import 'package:cafe_resto_caisse/screens/deliveries_screen.dart';
import 'package:cafe_resto_caisse/screens/orders_screen.dart';
import 'package:cafe_resto_caisse/screens/users_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('les permissions masquent une action hors rôle, un admin passe', () {
    const cashier = StaffUser(
      id: 1,
      name: 'Caisse',
      email: 'c@cafe.test',
      phone: '',
      locale: 'fr',
      isActive: true,
      roles: ['cashier'],
      permissions: ['dashboard.view', 'pos.access', 'orders.view', 'cash.operate'],
    );
    expect(cashier.can('pos.access'), isTrue);
    expect(cashier.can('catalog.manage'), isFalse);
    expect(cashier.can('delivery.manage'), isFalse);
    const admin = StaffUser(
      id: 2,
      name: 'Admin',
      email: 'a@cafe.test',
      phone: '',
      locale: 'ar',
      isActive: true,
      roles: ['admin'],
      permissions: [],
    );
    expect(admin.can('users.manage'), isTrue);
    expect(admin.locale, 'ar');
  });

  test('un compte inactif et une 404 générique sont lisibles', () {
    final inactive = StaffUser.fromJson({'is_active': false, 'roles': ['cashier']});
    expect(inactive.isActive, isFalse);
    final missing = DioException(
      requestOptions: RequestOptions(path: '/api/v1/orders'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/v1/orders'),
        statusCode: 404,
        data: {'message': 'not found'},
      ),
    );
    expect(apiMessage(missing), 'Introuvable.');
  });

  testWidgets('commandes, tableau, tiroir, catalogue, équipe, livraisons et réglages lisent l’API', (tester) async {
    final calls = <String>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        calls.add('${options.method} ${options.path}');
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: _payload(options.path, options.queryParameters),
        ));
      },
    ));

    Future<void> open(Widget screen) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          onlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(home: Scaffold(body: screen)),
      ));
      await tester.pumpAndSettle();
    }

    await open(const OrdersScreen());
    expect(find.text('T-1'), findsOneWidget);
    expect(find.textContaining('dine_in'), findsOneWidget);

    await open(const DashboardScreen());
    expect(find.text('Aujourd’hui'), findsOneWidget);
    expect(find.text('Chiffre d’affaires'), findsWidgets);
    expect(find.textContaining('10'), findsWidgets);

    await open(const CashScreen());
    expect(find.text('Session ouverte'), findsOneWidget);
    expect(find.textContaining('Espèces attendues'), findsOneWidget);
    expect(find.text('La carte ne rentre pas dans le tiroir.'), findsOneWidget);

    await open(const CatalogScreen());
    expect(find.text('Espresso'), findsOneWidget);
    expect(find.text('Cafés'), findsOneWidget);

    await open(const UsersScreen());
    expect(find.text('Sara'), findsOneWidget);

    const manager = StaffUser(
      id: 3,
      name: 'Gérant',
      email: 'g@cafe.test',
      phone: '',
      locale: 'fr',
      isActive: true,
      roles: ['manager'],
      permissions: ['delivery.view', 'delivery.manage'],
    );
    await open(const DeliveriesScreen(user: manager));
    expect(find.textContaining('Amina'), findsOneWidget);
    expect(find.text('Appeler'), findsOneWidget);
    await tester.tap(find.text('Zones'));
    await tester.pumpAndSettle();
    expect(find.text('Zone'), findsOneWidget);

    const driver = StaffUser(
      id: 4,
      name: 'Livreur',
      email: 'd@cafe.test',
      phone: '',
      locale: 'fr',
      isActive: true,
      roles: ['driver'],
      permissions: ['delivery.view'],
    );
    await open(DeliveriesScreen(user: driver));
    expect(find.text('Zone'), findsNothing);
    expect(find.text('Assigner'), findsNothing);
    expect(find.text('Appeler'), findsOneWidget);

    await open(const BusinessSettingsScreen());
    expect(find.text('business.name'), findsOneWidget);
    expect(find.text('Café Test'), findsOneWidget);
    expect(find.text('Logo'), findsOneWidget);

    expect(calls, contains('GET /api/v1/orders'));
    expect(calls, contains('GET /api/v1/dashboard'));
    expect(calls, contains('GET /api/v1/cash/session'));
    expect(calls, contains('GET /api/v1/cash/sessions'));
    expect(calls, contains('GET /api/v1/categories'));
    expect(calls, contains('GET /api/v1/products'));
    expect(calls, contains('GET /api/v1/users'));
    expect(calls, contains('GET /api/v1/deliveries'));
    expect(calls, contains('GET /api/v1/delivery-zones'));
    expect(calls, contains('GET /api/v1/settings'));
  });
}

dynamic _payload(String path, Map<String, dynamic> query) {
  switch (path) {
    case '/api/v1/orders':
      return {
        'data': [
          {
            'public_ref': 'T-1',
            'sold_at': '12:00',
            'type': 'dine_in',
            'payment_method': 'cash',
            'total': '10.00',
            'currency': 'DH',
          },
        ],
      };
    case '/api/v1/dashboard':
      return {
        'data': {
          'period': query['period'],
          'sales_total': 10,
          'orders_count': 1,
          'average_order_value': 10,
          'cash_total': 10,
          'card_total': 0,
          'delivery_count': 0,
          'expenses_total': 0,
          'estimated_gross_profit': 4,
          'net_operating_result': 4,
          'cash_session': {'open': true, 'expected': 80},
          'best_sellers': [
            {'name': 'Espresso', 'quantity_sum': 2, 'total_sum': 24},
          ],
        },
      };
    case '/api/v1/cash/session':
      return {
        'data': {
          'id': 7,
          'status': 'open',
          'totals': {
            'expected': 80,
            'cash_sales': 50,
            'cash_in': 20,
            'cash_out': 0,
            'expenses': 0,
          },
        },
      };
    case '/api/v1/cash/sessions':
      return {'data': []};
    case '/api/v1/pos/cash-status':
      return {'data': {'require_open_session': true, 'session_open': true, 'session_id': 7}};
    case '/api/v1/categories':
      return {
        'data': [
          {'id': 1, 'name': 'Cafés', 'is_active': true},
        ],
      };
    case '/api/v1/products':
      return {
        'data': [
          {'id': 2, 'name': 'Espresso', 'type': 'sellable', 'unit': 'piece', 'sale_price': 12},
        ],
      };
    case '/api/v1/users':
      return {
        'data': [
          {
            'id': 1,
            'name': 'Sara',
            'email': 'sara@cafe.test',
            'roles': ['cashier'],
            'locale': 'fr',
            'is_active': true,
          },
        ],
        'assignable_roles': ['cashier', 'waiter'],
      };
    case '/api/v1/deliveries':
      return {
        'data': [
          {
            'id': 4,
            'customer_name': 'Amina',
            'status': 'pending',
            'address': 'Rue 1',
            'customer_phone': '0612345678',
          },
        ],
      };
    case '/api/v1/delivery-zones':
      return {
        'data': [
          {'id': 1, 'name': 'Centre', 'fee': 10, 'min_order': 0, 'is_active': true},
        ],
      };
    case '/api/v1/settings':
      return {
        'values': {'business.name': 'Café Test'},
        'definitions': {
          'business.name': {'group': 'business', 'type': 'string', 'label': 'Nom'},
        },
      };
    default:
      return {'data': {}};
  }
}
