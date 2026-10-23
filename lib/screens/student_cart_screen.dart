import 'package:flutter/material.dart';
import '../constants/checkout_limits.dart';
import '../models/confirmed_order.dart';
import '../models/vendor_menu.dart';
import '../services/catalog_repository.dart';
import '../services/student_cart.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/stall_picture_picker.dart';
import '../widgets/student_commerce_widgets.dart';

Future<bool> confirmCartAction(BuildContext context, String title, String message, String confirm) async =>
  await showDialog<bool>(context: context, useRootNavigator: false, builder: (context) => AlertDialog(
    title: Text(title), content: Text(message), actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, true), child: Text(confirm)),
    ])) ?? false;

class StudentCartScreen extends StatefulWidget {
  const StudentCartScreen({super.key, required this.cart, required this.onBrowse,
    this.onCheckout, this.checkoutAvailable = false});
  final StudentCart cart;
  final VoidCallback onBrowse;
  final VoidCallback? onCheckout;
  final bool checkoutAvailable;
  @override
  State<StudentCartScreen> createState() => _StudentCartScreenState();
}
class _StudentCartScreenState extends State<StudentCartScreen> {
  String? _error;
  bool _busy = false;
  Future<void> _action(Future<void> Function() body) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try { await body(); }
    catch (e) { if (mounted) setState(() => _error = catalogError(e)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _clear() => _action(() async {
    final confirmed = await confirmCartAction(context, 'Clear Cart?',
      'Remove all unpaid selections from your cart?', 'Clear Cart');
    if (mounted && confirmed) widget.cart.clear();
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.cart, builder: (context, _) {
    final cart = widget.cart;
    final items = cart.lines.map((l) => OrderItem(foodId: l.food.id, name: l.food.draft.name,
      description: l.food.draft.description, categoryId: l.food.draft.categoryId, pictureId: l.food.draft.pictureId,
      priceSen: l.food.draft.priceSen, quantity: l.quantity, foodRevision: l.food.revision)).toList();
    return Column(children: [
      CommerceHeader('My Cart', onBack: widget.onBrowse, actions: [
        const Icon(Icons.shopping_cart_outlined, color: Colors.white),
        IconButton(tooltip: 'Clear Cart', onPressed: _busy || cart.checkoutLocked || cart.lines.isEmpty ? null : _clear,
          icon: const Icon(Icons.delete_outline, color: Colors.white)),
      ]),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ErrorMessage(_error),
        if (cart.checkoutLocked) CommerceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('An unconfirmed checkout is retained. Resolve it before editing your cart.'),
          OutlinedButton(onPressed: widget.onCheckout, child: const Text('Resolve Checkout')),
        ])),
        if (cart.lines.isEmpty) ...[
          const Padding(padding: EdgeInsets.all(32), child: Text('Your cart is empty', textAlign: TextAlign.center)),
          FilledButton(onPressed: widget.onBrowse, child: const Text('Browse Stalls')),
        ] else ...[
          StallOrderContext(name: cart.stallName, products: cart.lines.length, units: cart.itemCount),
          if (cart.warning != null) CommerceCard(child: Text(cart.warning!, style: const TextStyle(color: mutedText))),
          const Text(checkoutLimitsLabel, style: TextStyle(color: mutedText, fontSize: 12)),
          TextButton(onPressed: _busy ? null : cart.refresh, child: const Text('Refresh Cart')),
          for (final line in cart.lines) CommerceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StallPicture(line.food.draft.pictureId, width: MediaQuery.sizeOf(context).width < 360 ? 76 : 96, height: 110),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(line.food.draft.name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                  SizedBox(width: 36, height: 36, child: IconButton(
                    key: ValueKey('cart-remove-${line.food.id}'), tooltip: 'Remove ${line.food.id}',
                    icon: const Icon(Icons.delete_outline, color: mutedText), padding: EdgeInsets.zero,
                    onPressed: _busy || cart.checkoutLocked ? null : () => _action(() async {
                      final confirmed = await confirmCartAction(context, 'Remove item?',
                        'Remove ${line.food.draft.name} from this unpaid cart?', 'Remove');
                      if (mounted && confirmed) cart.remove(line.food.id);
                    }))),
                ]),
                const SizedBox(height: 6), Text('${rm(line.food.draft.priceSen)} each',
                  style: const TextStyle(color: primaryOrange, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Container(decoration: BoxDecoration(color: const Color(0xFFF7F7F9), borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE9EAF0))), child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(key: ValueKey('cart-decrease-${line.food.id}'), tooltip: 'Decrease ${line.food.id}', icon: const Icon(Icons.remove),
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: _busy || cart.checkoutLocked || line.quantity <= 1 ? null : () => _action(() async =>
                      cart.quantity(line.food.id, line.quantity - 1))),
                  Semantics(label: 'Quantity ${line.quantity}', child: Text('${line.quantity}',
                    key: ValueKey('quantity-${line.food.id}'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                  IconButton(key: ValueKey('cart-increase-${line.food.id}'), tooltip: 'Increase ${line.food.id}', icon: const Icon(Icons.add, color: primaryOrange),
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: _busy || cart.checkoutLocked || line.quantity >= StudentCart.maxQuantity || cart.warning != null || cart.issue(line) != null
                      ? null : () => _action(() async => cart.quantity(line.food.id, line.quantity + 1))),
                ])),
              ])),
            ]),
            const SizedBox(height: 8), Text('Subtotal: ${rm(line.subtotalSen)}', style: const TextStyle(color: mutedText)),
            if (cart.issue(line) != null) ...[
              const SizedBox(height: 8), Text(cart.issue(line)!, style: const TextStyle(color: mutedText)),
              if (cart.confirmed && cart.currentFood(line.food.id) != null)
                TextButton(onPressed: _busy || cart.checkoutLocked ? null : () => _action(() async {
                  final current = cart.currentFood(line.food.id)!;
                  final confirmed = await confirmCartAction(context, 'Review menu changes',
                    'Update ${line.food.draft.name} (${rm(line.food.draft.priceSen)}) to '
                    '${current.draft.name} (${rm(current.draft.priceSen)})? Quantity stays the same.', 'Apply Latest');
                  if (mounted && confirmed) await cart.review(line.food.id, current.revision);
                }), child: const Text('Review Changes')),
            ],
          ])),
          CommerceSummary(items: items, totalSen: cart.totalSen),
          const Text('Unpaid selections — no order has been placed. Checkout verifies authoritative menu data and prices again.',
            style: TextStyle(color: mutedText, fontSize: 12)),
          TextButton(onPressed: _busy || cart.checkoutLocked ? null : _clear, child: const Text('Clear Cart')),
          TextButton(onPressed: widget.onBrowse, child: const Text('Continue Browsing')),
        ],
      ]))),
      if (cart.lines.isNotEmpty) Container(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE9EAF0)))),
        child: FilledButton(key: const ValueKey('cart-review-checkout'), onPressed: !widget.checkoutAvailable || !cart.checkoutEligible || cart.checkoutLocked
          ? null : widget.onCheckout, child: const Text('Review Checkout'))),
    ]);
  });
}
