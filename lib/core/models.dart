double toNum(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0;
}

class Product {
  Product({
    required this.variantId,
    required this.name,
    required this.variant,
    required this.sku,
    required this.barcode,
    required this.price,
    required this.taxRate,
    required this.color,
    required this.storeAvailable,
    required this.depotAvailable,
    this.imageKey,
  });

  final int variantId;
  final String name;
  final String variant;
  final String sku;
  final String barcode;
  final double? price;
  final double taxRate;
  final String color;
  int storeAvailable;
  final int depotAvailable;
  final String? imageKey;

  String get label => variant.isEmpty ? name : '$name · $variant';

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        variantId: (j['variant_id'] as num).toInt(),
        name: (j['name'] ?? '').toString(),
        variant: (j['variant'] ?? '').toString(),
        sku: (j['sku'] ?? '').toString(),
        barcode: (j['barcode'] ?? '').toString(),
        price: j['price'] == null ? null : toNum(j['price']),
        taxRate: toNum(j['tax_rate']),
        color: (j['color'] ?? '').toString(),
        storeAvailable: toNum(j['store_available']).toInt(),
        depotAvailable: toNum(j['depot_available']).toInt(),
        imageKey: (j['image_key'] ?? '').toString().isEmpty ? null : j['image_key'].toString(),
      );

  Map<String, dynamic> toJson() => {
        'variant_id': variantId,
        'name': name,
        'variant': variant,
        'sku': sku,
        'barcode': barcode,
        'price': price,
        'tax_rate': taxRate,
        'color': color,
        'store_available': storeAvailable,
        'depot_available': depotAvailable,
        'image_key': imageKey,
      };
}

class Contact {
  Contact({required this.id, required this.code, required this.name, required this.phone, required this.balance, this.available});

  final int id;
  final String code;
  final String name;
  final String phone;
  final double balance;
  final double? available;

  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        id: (j['id'] as num).toInt(),
        code: (j['code'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        balance: toNum(j['balance']),
        available: j['available'] == null ? null : toNum(j['available']),
      );

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'name': name, 'phone': phone, 'balance': balance, 'available': available};
}

class CartLine {
  CartLine(this.product, this.quantity);

  final Product product;
  int quantity;

  double get gross => (product.price ?? 0) * quantity;
}

/// Totaux affichés par l'application. Le serveur recalcule toujours la vente (il fait foi).
class Totals {
  Totals({required this.gross, required this.discount, required this.tax, required this.total});

  final double gross;
  final double discount;
  final double tax;
  final double total;

  static double round2(double v) => (v * 100).roundToDouble() / 100;

  static Totals compute(List<CartLine> lines, {required bool vat, required bool includesTax, String? discountType, double discountValue = 0}) {
    final gross = lines.fold<double>(0, (s, l) => s + l.gross);
    double discount = 0;
    if (discountType == 'percent') discount = gross * discountValue.clamp(0, 100) / 100;
    if (discountType == 'amount') discount = discountValue.clamp(0, gross).toDouble();
    discount = round2(discount);
    final ratio = gross > 0 ? (gross - discount) / gross : 0;
    double tax = 0;
    for (final l in lines) {
      final net = l.gross * ratio;
      final rate = vat ? l.product.taxRate : 0;
      if (rate <= 0) continue;
      tax += includesTax ? net - net / (1 + rate / 100) : net * rate / 100;
    }
    tax = round2(tax);
    final total = round2(includesTax || !vat ? gross - discount : gross - discount + tax);
    return Totals(gross: round2(gross), discount: discount, tax: tax, total: total);
  }
}
