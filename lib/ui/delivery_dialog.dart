import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';

/// Destinataire d'une vente à livrer (nom, téléphone, adresse, ville, frais d'expédition).
Future<DeliveryInfo?> showDeliveryForm(BuildContext context, {DeliveryInfo? initial, Contact? contact}) =>
    showDialog<DeliveryInfo>(context: context, barrierDismissible: false, builder: (_) => _DeliveryDialog(initial: initial, contact: contact));

class _DeliveryDialog extends StatefulWidget {
  const _DeliveryDialog({this.initial, this.contact});

  final DeliveryInfo? initial;
  final Contact? contact;

  @override
  State<_DeliveryDialog> createState() => _DeliveryDialogState();
}

class _DeliveryDialogState extends State<_DeliveryDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _shipping = TextEditingController();
  int? _cityId;
  String _cityName = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name.text = i?.fullName ?? widget.contact?.name ?? '';
    _phone.text = i?.phone ?? widget.contact?.phone ?? '';
    _address.text = i?.address ?? '';
    _notes.text = i?.notes ?? '';
    _shipping.text = i != null && i.shipping > 0 ? i.shipping.toStringAsFixed(2) : '';
    _cityId = i?.cityId;
    _cityName = i?.cityName ?? '';
  }

  void _save() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final address = _address.text.trim();
    final shipping = toNum(_shipping.text.trim());
    String? error;
    if (name.isEmpty) error = 'Le nom du destinataire est obligatoire.';
    if (error == null && !RegExp(r'^[0-9 +\-().]{6,22}$').hasMatch(phone)) error = 'Téléphone du destinataire invalide.';
    if (error == null && address.isEmpty) error = 'L’adresse de livraison est obligatoire.';
    if (error == null && _cityId == null) error = 'Choisissez la ville de livraison dans la liste.';
    if (error == null && shipping < 0) error = 'Frais d’expédition invalides.';
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      DeliveryInfo(fullName: name, phone: phone, address: address, cityId: _cityId!, cityName: _cityName, notes: _notes.text.trim(), shipping: shipping),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final cities = app.cities;
    return AlertDialog(
      title: const Row(children: [Icon(Icons.local_shipping_outlined), SizedBox(width: 8), Text('Livraison')]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Destinataire *')),
            const SizedBox(height: 10),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone *', prefixIcon: Icon(Icons.phone_outlined))),
            const SizedBox(height: 10),
            Autocomplete<Map<String, dynamic>>(
              initialValue: TextEditingValue(text: _cityName),
              displayStringForOption: (c) => c['name'].toString(),
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.isEmpty) return cities.take(30);
                return cities.where((c) => c['name'].toString().toLowerCase().contains(q)).take(30);
              },
              onSelected: (c) => setState(() {
                _cityId = (c['id'] as num).toInt();
                _cityName = c['name'].toString();
              }),
              fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
                controller: controller,
                focusNode: focus,
                decoration: InputDecoration(
                  labelText: 'Ville *',
                  prefixIcon: const Icon(Icons.location_city_outlined),
                  suffixIcon: _cityId != null ? const Icon(Icons.check_circle, color: Colors.green) : null,
                ),
                onChanged: (v) {
                  if (_cityId != null && v != _cityName) setState(() => _cityId = null);
                },
              ),
            ),
            if (cities.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 4), child: Text('Aucune ville : synchronisez la caisse.', style: TextStyle(color: Colors.red, fontSize: 12))),
            const SizedBox(height: 10),
            TextField(controller: _address, maxLines: 2, decoration: const InputDecoration(labelText: 'Adresse *')),
            const SizedBox(height: 10),
            TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Note pour le livreur')),
            const SizedBox(height: 10),
            TextField(
              controller: _shipping,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Frais d’expédition (${app.currency})', hintText: '0 = offerts', prefixIcon: const Icon(Icons.add)),
            ),
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('Valider')),
      ],
    );
  }
}
