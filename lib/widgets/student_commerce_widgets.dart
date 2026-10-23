import 'package:flutter/material.dart';
import '../models/confirmed_order.dart';
import '../models/vendor_menu.dart';
import '../theme/app_theme.dart';
import 'stall_picture_picker.dart';

class CommerceHeader extends StatelessWidget {
  const CommerceHeader(this.title, {super.key, this.onBack, this.actions = const []});
  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 22, 16, 22),
    decoration: const BoxDecoration(color: primaryOrange, borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
    child: Row(children: [
      IconButton(tooltip: 'Back', onPressed: onBack, icon: const Icon(Icons.arrow_back, color: Colors.white)),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w700))),
      ...actions,
    ]),
  );
}

class CommerceCard extends StatelessWidget {
  const CommerceCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, padding: padding, margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE9EAF0))),
    child: child,
  );
}

class StallOrderContext extends StatelessWidget {
  const StallOrderContext({super.key, required this.name, required this.products, required this.units});
  final String name;
  final int products, units;
  @override
  Widget build(BuildContext context) => CommerceCard(child: Row(children: [
    Container(width: 52, height: 52, decoration: const BoxDecoration(color: lightOrange, shape: BoxShape.circle),
      child: const Icon(Icons.storefront_outlined, color: primaryOrange, size: 29)),
    const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)), const SizedBox(height: 4),
      Text('$products ${products == 1 ? 'product' : 'products'} · $units ${units == 1 ? 'item' : 'items'} total',
        style: const TextStyle(color: mutedText)),
      const SizedBox(height: 4), const Text('Your order is from one stall', style: TextStyle(color: mutedText, fontSize: 12)),
    ])),
  ]));
}

class CommerceSummary extends StatelessWidget {
  const CommerceSummary({super.key, required this.items, required this.totalSen, this.pictures = false, this.payment = false});
  final List<OrderItem> items;
  final int totalSen;
  final bool pictures, payment;
  @override
  Widget build(BuildContext context) => CommerceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('Order Summary', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 14),
    for (final item in items) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
      if (pictures) ...[StallPicture(item.pictureId, width: 48, height: 48), const SizedBox(width: 10)],
      Expanded(child: Text('${item.name} × ${item.quantity}', style: const TextStyle(color: mutedText))),
      const SizedBox(width: 8), Text(rm(item.subtotalSen), style: const TextStyle(color: mutedText)),
    ])),
    const Divider(height: 24),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      const Text('Subtotal', style: TextStyle(color: mutedText)), Text(rm(totalSen), style: const TextStyle(color: mutedText)),
    ]),
    const SizedBox(height: 8),
    Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 4,
      children: [Text(payment ? 'Total Payment' : 'Total', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        Text(rm(totalSen), key: const ValueKey('commerce-total'),
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: primaryOrange))]),
  ]));
}

class PaymentMethodCard extends StatelessWidget {
  const PaymentMethodCard({super.key, required this.method, required this.selected, this.onSelect});
  final String method;
  final bool selected;
  final VoidCallback? onSelect;
  @override
  Widget build(BuildContext context) {
    final color = selected ? primaryOrange : mutedText;
    return Semantics(button: true, checked: selected, enabled: onSelect != null,
      label: '${simulatedPaymentMethods[method]}, simulated payment', child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4), child: Material(
        color: selected ? lightOrange : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? primaryOrange : const Color(0xFFE9EAF0), width: selected ? 1.5 : 1)),
        child: InkWell(onTap: onSelect, borderRadius: BorderRadius.circular(12), child: Padding(
          padding: const EdgeInsets.all(14), child: Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: .08), shape: BoxShape.circle),
              child: Icon(switch (method) {'ewallet' => Icons.account_balance_wallet_outlined,
                'onlineBanking' => Icons.account_balance_outlined, _ => Icons.credit_card}, color: color)),
            const SizedBox(width: 12),
            Expanded(child: Text(simulatedPaymentMethods[method]!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            const SizedBox(width: 8), Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: color, size: 27),
          ])),
        )),
    )));
  }
}
