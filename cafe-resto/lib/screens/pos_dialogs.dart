import 'package:flutter/material.dart';

import '../theme/pos_theme.dart';

class PosModifier {
  const PosModifier({required this.id, required this.name, required this.priceDelta});

  final int id;
  final String name;
  final double priceDelta;
}

class PosModifierGroup {
  const PosModifierGroup({
    required this.id,
    required this.name,
    required this.required,
    required this.minSelect,
    required this.maxSelect,
    required this.modifiers,
  });

  final int id;
  final String name;
  final bool required;
  final int minSelect;
  final int maxSelect;
  final List<PosModifier> modifiers;

  int get minimum => required ? (minSelect < 1 ? 1 : minSelect) : minSelect;
}

class PosPayChoice {
  const PosPayChoice({required this.method, this.tendered});

  final String method;
  final double? tendered;
}

class PosWeightChoice {
  const PosWeightChoice({required this.quantity, required this.lineTotal});

  final double quantity;
  final double lineTotal;
}

String posMoney(num value) {
  final negative = value < 0;
  final parts = value.abs().toStringAsFixed(2).split('.');
  return '${negative ? '-' : ''}${parts[0]},${parts[1]} DH';
}

List<PosModifierGroup> posModifierGroups(Map<String, dynamic> product) {
  final raw = product['modifier_groups'];
  if (raw is! List) return const [];
  final groups = <PosModifierGroup>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    final modifiersRaw = map['modifiers'];
    final modifiers = <PosModifier>[];
    if (modifiersRaw is List) {
      for (final modifier in modifiersRaw) {
        if (modifier is! Map) continue;
        final data = Map<String, dynamic>.from(modifier);
        final id = int.tryParse('${data['id']}');
        if (id == null) continue;
        modifiers.add(
          PosModifier(
            id: id,
            name: '${data['name'] ?? ''}',
            priceDelta: double.tryParse('${data['price_delta']}'.replaceAll(',', '.')) ?? 0,
          ),
        );
      }
    }
    final id = int.tryParse('${map['id']}');
    if (id == null || modifiers.isEmpty) continue;
    groups.add(
      PosModifierGroup(
        id: id,
        name: '${map['name'] ?? 'Suppléments'}',
        required: map['required'] == true || map['required'] == 1,
        minSelect: int.tryParse('${map['min_select']}') ?? 0,
        maxSelect: int.tryParse('${map['max_select']}') ?? 1,
        modifiers: modifiers,
      ),
    );
  }
  return groups;
}

bool posIsMeasured(String unit) => const ['g', 'kg', 'ml', 'l'].contains(unit);

Future<List<PosModifier>?> showPosExtrasDialog(
  BuildContext context, {
  required String productName,
  required List<PosModifierGroup> groups,
}) {
  return showDialog<List<PosModifier>>(
    context: context,
    builder: (context) => _ExtrasDialog(productName: productName, groups: groups),
  );
}

Future<PosPayChoice?> showPosPayDialog(
  BuildContext context, {
  required double total,
  double deliveryFee = 0,
  required String initialMethod,
  bool cashBlocked = false,
}) {
  return showDialog<PosPayChoice>(
    context: context,
    builder: (context) => _PayDialog(
      total: total,
      deliveryFee: deliveryFee,
      initialMethod: initialMethod,
      cashBlocked: cashBlocked,
    ),
  );
}

class DeliveryDraft {
  const DeliveryDraft({
    required this.name,
    required this.phone,
    required this.address,
    required this.notes,
    required this.zoneId,
  });

  final String name;
  final String phone;
  final String address;
  final String notes;
  final int? zoneId;
}

Future<DeliveryDraft?> showDeliveryWizard(
  BuildContext context, {
  required String name,
  required String phone,
  required String address,
  required String notes,
  required List<Map<String, dynamic>> zones,
  required int? zoneId,
  required bool requirePhone,
  required bool requireZone,
}) {
  return showDialog<DeliveryDraft>(
    context: context,
    builder: (context) => _DeliveryWizard(
      name: name,
      phone: phone,
      address: address,
      notes: notes,
      zones: zones,
      zoneId: zoneId,
      requirePhone: requirePhone,
      requireZone: requireZone,
    ),
  );
}

Future<String?> showPosTextPad(
  BuildContext context, {
  required String title,
  required String initial,
  String hint = '',
  bool phone = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextPad(title: title, initial: initial, hint: hint, phone: phone),
  );
}

Future<String?> showPosAmountPad(
  BuildContext context, {
  required String title,
  required String initial,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _AmountPad(title: title, initial: initial),
  );
}

Future<PosWeightChoice?> showPosWeightDialog(
  BuildContext context, {
  required String productName,
  required double unitPrice,
  required String unit,
}) {
  return showDialog<PosWeightChoice>(
    context: context,
    builder: (context) => _WeightDialog(productName: productName, unitPrice: unitPrice, unit: unit),
  );
}

class _DialogCard extends StatelessWidget {
  const _DialogCard({required this.child, this.width = 460});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: child,
        ),
      ),
    );
  }
}

class _ExtrasDialog extends StatefulWidget {
  const _ExtrasDialog({required this.productName, required this.groups});

  final String productName;
  final List<PosModifierGroup> groups;

  @override
  State<_ExtrasDialog> createState() => _ExtrasDialogState();
}

class _ExtrasDialogState extends State<_ExtrasDialog> {
  final Map<int, List<int>> _picked = {};

  bool get _ready {
    for (final group in widget.groups) {
      final count = _picked[group.id]?.length ?? 0;
      if (count < group.minimum || count > group.maxSelect) return false;
    }
    return true;
  }

  void _toggle(PosModifierGroup group, PosModifier modifier) {
    final current = List<int>.from(_picked[group.id] ?? const []);
    if (current.contains(modifier.id)) {
      current.remove(modifier.id);
    } else if (group.maxSelect <= 1) {
      current
        ..clear()
        ..add(modifier.id);
    } else if (current.length < group.maxSelect) {
      current.add(modifier.id);
    }
    setState(() => _picked[group.id] = current);
  }

  void _add() {
    if (!_ready) return;
    final selected = <PosModifier>[];
    for (final group in widget.groups) {
      final ids = _picked[group.id] ?? const <int>[];
      selected.addAll(group.modifiers.where((modifier) => ids.contains(modifier.id)));
    }
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    return _DialogCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.productName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Suppléments', style: TextStyle(color: PosColors.muted)),
          const SizedBox(height: 14),
          for (final group in widget.groups) ...[
            Text(group.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final modifier in group.modifiers)
                  _choiceChip(
                    label: '${modifier.name} · ${posMoney(modifier.priceDelta)}',
                    selected: _picked[group.id]?.contains(modifier.id) ?? false,
                    onTap: () => _toggle(group, modifier),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          _actions(
            confirmLabel: 'Ajouter',
            enabled: _ready,
            onCancel: () => Navigator.of(context).pop(),
            onConfirm: _add,
          ),
        ],
      ),
    );
  }
}

class _PayDialog extends StatefulWidget {
  const _PayDialog({
    required this.total,
    required this.deliveryFee,
    required this.initialMethod,
    required this.cashBlocked,
  });

  final double total;
  final double deliveryFee;
  final String initialMethod;
  final bool cashBlocked;

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  late String _method = widget.cashBlocked || widget.initialMethod == 'card' ? 'card' : 'cash';
  late String _buffer = (widget.total + widget.deliveryFee).toStringAsFixed(2);
  bool _fresh = true;

  double get _due => widget.total + widget.deliveryFee;

  int get _totalCents => (_due * 100).round();

  int get _receivedCents {
    final parsed = double.tryParse(_buffer.replaceAll(',', '.'));
    if (parsed == null) return 0;
    return (parsed * 100).round();
  }

  List<int> get _quickAmounts {
    const notes = [2000, 5000, 10000, 20000, 50000];
    return [_totalCents, ...notes.where((note) => note > _totalCents).take(3)];
  }

  bool get _canConfirm => _method == 'card' || _receivedCents >= _totalCents;

  void _press(String key) {
    if (key == 'back') {
      if (_fresh) {
        setState(() {
          _buffer = '0';
          _fresh = false;
        });
        return;
      }
      final trimmed = _buffer.substring(0, _buffer.length - 1).replaceAll(RegExp(r'[.,]$'), '');
      setState(() => _buffer = trimmed.isEmpty ? '0' : trimmed);
      return;
    }
    final digit = key == ',' ? '.' : key;
    String next;
    if (digit == '.') {
      next = _fresh || _buffer == '0'
          ? '0.'
          : _buffer.contains('.')
              ? _buffer
              : '$_buffer.';
    } else if (_fresh || _buffer == '0') {
      next = digit;
    } else {
      next = _buffer + digit;
    }
    final parts = next.split('.');
    if (parts.first.length > 6 || (parts.length > 1 && parts[1].length > 2)) return;
    setState(() {
      _buffer = next;
      _fresh = false;
    });
  }

  void _setAmount(int cents) {
    setState(() {
      _buffer = (cents / 100).toStringAsFixed(2);
      _fresh = true;
    });
  }

  String _shown(String raw) {
    return raw.replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final change = _method == 'cash' ? (_receivedCents - _totalCents) / 100 : 0.0;
    return _DialogCard(
      width: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Encaisser', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (widget.deliveryFee > 0) ...[
            _moneyRow('Commande', widget.total),
            _moneyRow('Livraison', widget.deliveryFee),
          ],
          _moneyRow('Total', _due, strong: true),
          const SizedBox(height: 14),
          Row(
            children: [
              _segment('cash', 'Espèces'),
              const SizedBox(width: 8),
              _segment('card', 'Carte'),
            ],
          ),
          if (widget.cashBlocked)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Ouvrez le tiroir pour encaisser en espèces. La carte reste possible.', style: TextStyle(color: PosColors.muted)),
            ),
          if (_method == 'cash') ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Text('Reçu', style: TextStyle(color: PosColors.muted, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${_shown(_buffer)} DH', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _quickAmounts.length; i++)
                  _choiceChip(
                    label: i == 0 ? 'Juste' : '${_quickAmounts[i] ~/ 100} DH',
                    selected: _receivedCents == _quickAmounts[i],
                    onTap: () => _setAmount(_quickAmounts[i]),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _keypad(onKey: _press, aspect: 2.6, keyHeight: 40),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Monnaie', style: TextStyle(color: PosColors.muted, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(posMoney(change < 0 ? 0 : change), style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _actions(
            confirmLabel: 'Confirmer',
            enabled: _canConfirm,
            onCancel: () => Navigator.of(context).pop(),
            onConfirm: () {
              if (_method == 'card') {
                Navigator.of(context).pop(const PosPayChoice(method: 'card'));
                return;
              }
              final amount = _receivedCents / 100;
              Navigator.of(context).pop(PosPayChoice(method: 'cash', tendered: amount));
            },
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(String label, double amount, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: strong ? PosColors.ink : PosColors.muted, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(posMoney(amount), style: TextStyle(fontSize: strong ? 22 : 15, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _segment(String value, String label) {
    final selected = _method == value;
    return Expanded(
      child: Material(
        color: selected ? const Color(0xFF111827) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: value == 'cash' && widget.cashBlocked ? null : () => setState(() => _method = value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: selected ? Colors.white : PosColors.ink, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmountPad extends StatefulWidget {
  const _AmountPad({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_AmountPad> createState() => _AmountPadState();
}

class _AmountPadState extends State<_AmountPad> {
  late String _buffer = widget.initial.replaceAll(',', '.').isEmpty ? '0' : widget.initial.replaceAll(',', '.');
  bool _fresh = true;

  void _press(String key) {
    if (key == 'back') {
      if (_fresh) {
        setState(() {
          _buffer = '0';
          _fresh = false;
        });
        return;
      }
      final trimmed = _buffer.substring(0, _buffer.length - 1).replaceAll(RegExp(r'[.,]$'), '');
      setState(() => _buffer = trimmed.isEmpty ? '0' : trimmed);
      return;
    }
    final digit = key == ',' ? '.' : key;
    String next;
    if (digit == '.') {
      next = _fresh || _buffer == '0' ? '0.' : _buffer.contains('.') ? _buffer : '$_buffer.';
    } else if (_fresh || _buffer == '0') {
      next = digit;
    } else {
      next = _buffer + digit;
    }
    final parts = next.split('.');
    if (parts.first.length > 6 || (parts.length > 1 && parts[1].length > 2)) return;
    setState(() {
      _buffer = next;
      _fresh = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _DialogCard(
      width: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(14)),
            child: Text(
              '${_buffer.replaceAll('.', ',')} DH',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          _keypad(onKey: _press),
          const SizedBox(height: 16),
          _actions(
            confirmLabel: 'OK',
            enabled: true,
            onCancel: () => Navigator.of(context).pop(),
            onConfirm: () => Navigator.of(context).pop(_buffer),
          ),
        ],
      ),
    );
  }
}

class _WeightDialog extends StatefulWidget {
  const _WeightDialog({required this.productName, required this.unitPrice, required this.unit});

  final String productName;
  final double unitPrice;
  final String unit;

  @override
  State<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends State<_WeightDialog> {
  String _mode = 'weight';
  String _buffer = '0';
  bool _fresh = true;

  bool get _volume => widget.unit == 'ml' || widget.unit == 'l';
  String get _inputUnit => _volume ? 'ml' : 'g';
  int get _factor => widget.unit == 'kg' || widget.unit == 'l' ? 1000 : 1;

  double? get _entered => double.tryParse(_buffer.replaceAll(',', '.'));

  PosWeightChoice? get _preview {
    final entered = _entered;
    if (entered == null || entered <= 0 || widget.unitPrice <= 0) return null;
    late final double quantity;
    late final double lineTotal;
    if (_mode == 'money') {
      lineTotal = double.parse(entered.toStringAsFixed(2));
      quantity = entered / widget.unitPrice;
    } else {
      quantity = entered / _factor;
      lineTotal = double.parse((widget.unitPrice * quantity).toStringAsFixed(2));
    }
    if (quantity <= 0 || lineTotal <= 0) return null;
    return PosWeightChoice(quantity: quantity, lineTotal: lineTotal);
  }

  void _press(String key) {
    if (key == 'back') {
      if (_fresh) {
        setState(() {
          _buffer = '0';
          _fresh = false;
        });
        return;
      }
      final trimmed = _buffer.substring(0, _buffer.length - 1).replaceAll(RegExp(r'[.,]$'), '');
      setState(() => _buffer = trimmed.isEmpty ? '0' : trimmed);
      return;
    }
    final digit = key == ',' ? '.' : key;
    final maxFraction = _mode == 'money' ? 2 : 3;
    String next;
    if (digit == '.') {
      next = _fresh || _buffer == '0' ? '0.' : _buffer.contains('.') ? _buffer : '$_buffer.';
    } else if (_fresh || _buffer == '0') {
      next = digit;
    } else {
      next = _buffer + digit;
    }
    final parts = next.split('.');
    if (parts.first.length > 6 || (parts.length > 1 && parts[1].length > maxFraction)) return;
    setState(() {
      _buffer = next;
      _fresh = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return _DialogCard(
      width: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.productName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${posMoney(widget.unitPrice)} / ${widget.unit}', style: const TextStyle(color: PosColors.muted)),
          const SizedBox(height: 12),
          Row(
            children: [
              _modeChip('weight', _volume ? 'Volume' : 'Poids'),
              const SizedBox(width: 8),
              _modeChip('money', 'Montant'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Text(_mode == 'money' ? 'DH' : _inputUnit, style: const TextStyle(color: PosColors.muted, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(_buffer.replaceAll('.', ','), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in _mode == 'money' ? const ['20', '50', '100'] : const ['100', '250', '500', '1000'])
                _choiceChip(
                  label: _mode == 'money' ? '$value DH' : '$value $_inputUnit',
                  selected: _buffer == value,
                  onTap: () => setState(() {
                    _buffer = value;
                    _fresh = true;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _keypad(onKey: _press),
          if (preview != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(_quantityLabel(preview.quantity), style: const TextStyle(color: PosColors.muted)),
                const Spacer(),
                Text(posMoney(preview.lineTotal), style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _actions(
            confirmLabel: 'Ajouter',
            enabled: preview != null,
            onCancel: () => Navigator.of(context).pop(),
            onConfirm: () => Navigator.of(context).pop(preview),
          ),
        ],
      ),
    );
  }

  String _quantityLabel(double quantity) {
    final shown = quantity.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '${shown.replaceAll('.', ',')} ${widget.unit}';
  }

  Widget _modeChip(String value, String label) {
    final selected = _mode == value;
    return Expanded(
      child: Material(
        color: selected ? const Color(0xFF111827) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _mode = value;
            _buffer = '0';
            _fresh = true;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: selected ? Colors.white : PosColors.ink, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextPad extends StatefulWidget {
  const _TextPad({required this.title, required this.initial, required this.hint, required this.phone});

  final String title;
  final String initial;
  final String hint;
  final bool phone;

  @override
  State<_TextPad> createState() => _TextPadState();
}

class _TextPadState extends State<_TextPad> {
  late String _value = widget.initial;
  bool _shift = false;

  static const _rows = [
    ['a', 'z', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['q', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'm'],
    ['w', 'x', 'c', 'v', 'b', 'n'],
  ];
  static const _digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
  static const _phoneKeys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '0', 'back'];

  void _press(String key) {
    if (key == 'back') {
      if (_value.isEmpty) return;
      setState(() => _value = _value.substring(0, _value.length - 1));
      return;
    }
    if (key == 'space') {
      if (_value.length >= 500) return;
      setState(() => _value = '$_value ');
      return;
    }
    if (key == 'shift') {
      setState(() => _shift = !_shift);
      return;
    }
    if (_value.length >= (widget.phone ? 30 : 500)) return;
    final char = _shift ? key.toUpperCase() : key;
    setState(() {
      _value = '$_value$char';
      if (_shift && key.length == 1) _shift = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).width;
    return _DialogCard(
      width: widget.phone ? (screen - 32).clamp(280, 380) : (screen - 32).clamp(320, 560),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PosColors.line),
            ),
            child: Text(
              _value.isEmpty ? widget.hint : _value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _value.isEmpty ? PosColors.muted : PosColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.phone)
            _keypad(keys: _phoneKeys, onKey: _press, aspect: 3.2, keyHeight: 36)
          else ...[
            for (final row in _rows) ...[
              _letterRow(row),
              const SizedBox(height: 6),
            ],
            _letterRow(_digits),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(flex: 2, child: _keyButton('Maj', onTap: () => _press('shift'), active: _shift)),
                const SizedBox(width: 6),
                Expanded(flex: 5, child: _keyButton('Espace', onTap: () => _press('space'))),
                const SizedBox(width: 6),
                Expanded(flex: 2, child: _keyButton('⌫', onTap: () => _press('back'))),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
              TextButton(onPressed: () => setState(() => _value = ''), child: const Text('Effacer')),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_value.trim()),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  minimumSize: const Size(120, 46),
                ),
                child: const Text('OK'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _letterRow(List<String> keys) {
    return Row(
      children: [
        for (final key in keys) ...[
          if (key != keys.first) const SizedBox(width: 6),
          Expanded(
            child: _keyButton(
              _shift ? key.toUpperCase() : key,
              onTap: () => _press(key),
            ),
          ),
        ],
      ],
    );
  }
}

Widget _keypad({
  List<String> keys = const ['1', '2', '3', '4', '5', '6', '7', '8', '9', ',', '0', 'back'],
  required void Function(String key) onKey,
  double aspect = 2.4,
  double keyHeight = 42,
}) {
  return GridView.count(
    crossAxisCount: 3,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 6,
    crossAxisSpacing: 6,
    childAspectRatio: aspect,
    children: [
      for (final key in keys)
        _keyButton(key == 'back' ? '⌫' : key, onTap: () => onKey(key), height: keyHeight),
    ],
  );
}

Widget _keyButton(String label, {required VoidCallback onTap, bool flex = true, bool wide = false, bool active = false, double height = 42}) {
  final button = Material(
    color: active ? const Color(0xFF111827) : const Color(0xFFF3F4F6),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: height,
        width: wide ? 180 : null,
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: active ? Colors.white : PosColors.ink),
        ),
      ),
    ),
  );
  return flex ? button : button;
}

Widget _choiceChip({required String label, required bool selected, required VoidCallback onTap}) {
  return Material(
    color: selected ? const Color(0xFF111827) : Colors.white,
    borderRadius: BorderRadius.circular(999),
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? const Color(0xFF111827) : PosColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(color: selected ? Colors.white : PosColors.ink, fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}

Widget _actions({
  required String confirmLabel,
  required bool enabled,
  required VoidCallback onCancel,
  required VoidCallback onConfirm,
}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      OutlinedButton(
        onPressed: onCancel,
        style: OutlinedButton.styleFrom(minimumSize: const Size(110, 46), foregroundColor: PosColors.ink),
        child: const Text('Annuler'),
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: enabled ? onConfirm : null,
        style: FilledButton.styleFrom(
          backgroundColor: confirmLabel == 'Confirmer' ? PosColors.accent : const Color(0xFF111827),
          disabledBackgroundColor: const Color(0xFFE5E7EB),
          foregroundColor: Colors.white,
          minimumSize: const Size(120, 46),
        ),
        child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    ],
  );
}

class _DeliveryWizard extends StatefulWidget {
  const _DeliveryWizard({
    required this.name,
    required this.phone,
    required this.address,
    required this.notes,
    required this.zones,
    required this.zoneId,
    required this.requirePhone,
    required this.requireZone,
  });

  final String name;
  final String phone;
  final String address;
  final String notes;
  final List<Map<String, dynamic>> zones;
  final int? zoneId;
  final bool requirePhone;
  final bool requireZone;

  @override
  State<_DeliveryWizard> createState() => _DeliveryWizardState();
}

class _DeliveryWizardState extends State<_DeliveryWizard> {
  late String _name = widget.name;
  late String _phone = widget.phone;
  late String _address = widget.address;
  late final String _notes = widget.notes;
  late int? _zoneId = widget.zoneId;
  int _step = 0;
  bool _shift = false;

  static const _steps = ['Client', 'Téléphone', 'Adresse', 'Zone'];
  static const _letters = [
    ['a', 'z', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['q', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'm'],
    ['w', 'x', 'c', 'v', 'b', 'n'],
  ];

  String get _current {
    switch (_step) {
      case 0:
        return _name;
      case 1:
        return _phone;
      case 2:
        return _address;
      default:
        return '';
    }
  }

  set _current(String value) {
    switch (_step) {
      case 0:
        _name = value;
      case 1:
        _phone = value;
      case 2:
        _address = value;
    }
  }

  bool get _stepReady {
    switch (_step) {
      case 0:
        return _name.trim().isNotEmpty;
      case 1:
        return !widget.requirePhone || _phone.trim().isNotEmpty;
      case 2:
        return _address.trim().isNotEmpty;
      default:
        return !widget.requireZone || _zoneId != null;
    }
  }

  void _type(String key) {
    if (key == 'back') {
      if (_current.isEmpty) return;
      setState(() => _current = _current.substring(0, _current.length - 1));
      return;
    }
    if (key == 'space') {
      setState(() => _current = '$_current ');
      return;
    }
    if (key == 'shift') {
      setState(() => _shift = !_shift);
      return;
    }
    final char = _shift ? key.toUpperCase() : key;
    setState(() {
      _current = '$_current$char';
      if (_shift) _shift = false;
    });
  }

  void _next() {
    if (!_stepReady) return;
    if (_step < _steps.length - 1) {
      setState(() {
        _step += 1;
        _shift = false;
      });
      return;
    }
    Navigator.of(context).pop(
      DeliveryDraft(name: _name.trim(), phone: _phone.trim(), address: _address.trim(), notes: _notes.trim(), zoneId: _zoneId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return _DialogCard(
      width: (width - 24).clamp(300, _step == 1 ? 420 : 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Livraison · ${_steps[_step]}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Étape ${_step + 1} / ${_steps.length}', style: const TextStyle(color: PosColors.muted)),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PosColors.line),
            ),
            child: Text(
              _step == 3 ? (_zoneId == null ? 'Choisir la zone' : 'Zone choisie') : (_current.isEmpty ? _steps[_step] : _current),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _current.isEmpty && _step != 3 ? PosColors.muted : PosColors.ink),
            ),
          ),
          const SizedBox(height: 10),
          if (_step == 1)
            _keypad(keys: const ['1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '0', 'back'], onKey: _type, aspect: 3.2, keyHeight: 36)
          else if (_step == 3)
            _zones()
          else
            _lettersPad(),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_step > 0)
                OutlinedButton(
                  onPressed: () => setState(() => _step -= 1),
                  child: const Text('Retour'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _stepReady ? _next : null,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF111827), minimumSize: const Size(120, 44)),
                child: Text(_step == _steps.length - 1 ? 'Terminer' : 'Suivant'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lettersPad() {
    return Column(
      children: [
        for (final row in _letters) ...[
          _letterRow(row),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Expanded(flex: 2, child: _keyButton('Maj', onTap: () => _type('shift'), active: _shift, height: 40)),
            const SizedBox(width: 6),
            Expanded(flex: 5, child: _keyButton('Espace', onTap: () => _type('space'), height: 40)),
            const SizedBox(width: 6),
            Expanded(flex: 2, child: _keyButton('⌫', onTap: () => _type('back'), height: 40)),
          ],
        ),
      ],
    );
  }

  Widget _letterRow(List<String> keys) {
    return Row(
      children: [
        for (final key in keys) ...[
          if (key != keys.first) const SizedBox(width: 4),
          Expanded(child: _keyButton(_shift ? key.toUpperCase() : key, onTap: () => _type(key), height: 40)),
        ],
      ],
    );
  }

  Widget _zones() {
    if (widget.zones.isEmpty) {
      return const Text('Aucune zone active.', style: TextStyle(color: PosColors.muted));
    }
    return Column(
      children: [
        for (final zone in widget.zones)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: _zoneId == int.tryParse('${zone['id']}') ? const Color(0xFF111827) : const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _zoneId = int.tryParse('${zone['id']}')),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${zone['name']}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _zoneId == int.tryParse('${zone['id']}') ? Colors.white : PosColors.ink,
                          ),
                        ),
                      ),
                      Text(
                        posMoney(double.tryParse('${zone['fee']}') ?? 0),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _zoneId == int.tryParse('${zone['id']}') ? Colors.white : PosColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
