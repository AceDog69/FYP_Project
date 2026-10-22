import 'package:flutter/material.dart';
import '../models/vendor_menu.dart';
import '../services/catalog_repository.dart';
import '../services/student_cart.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/stall_picture_picker.dart';

Future<bool> confirmCartAction(BuildContext context, String title, String message, String confirm) async =>
  await showDialog<bool>(context: context, useRootNavigator: false, builder: (context) => AlertDialog(
    title: Text(title), content: Text(message), actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, true), child: Text(confirm)),
    ])) ?? false;

class StudentCartScreen extends StatefulWidget {
  const StudentCartScreen({super.key, required this.cart, required this.onBrowse});
  final StudentCart cart;
  final VoidCallback onBrowse;
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
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.cart, builder: (context, _) {
    final cart = widget.cart;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Your Cart', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8), const Text('Unpaid selections — no order has been placed.'),
      ErrorMessage(_error),
      if (cart.lines.isEmpty) ...[
        const Padding(padding: EdgeInsets.all(32), child: Text('Your cart is empty', textAlign: TextAlign.center)),
        FilledButton(onPressed: widget.onBrowse, child: const Text('Browse Stalls')),
      ] else ...[
        const SizedBox(height: 16), Text(cart.stallName, style: Theme.of(context).textTheme.titleLarge),
        if (cart.warning != null) Text(cart.warning!, style: const TextStyle(color: mutedText)),
        TextButton(onPressed: _busy ? null : cart.refresh, child: const Text('Refresh Cart')),
        for (final line in cart.lines) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StallPicture(line.food.draft.pictureId, width: 80, height: 80), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(line.food.draft.name, style: Theme.of(context).textTheme.titleMedium),
                Text('${rm(line.food.draft.priceSen)} each'),
                Text('Subtotal: ${rm(line.subtotalSen)}'),
              ])),
            ]),
            if (cart.issue(line) != null) ...[
              const SizedBox(height: 8), Text(cart.issue(line)!, style: const TextStyle(color: mutedText)),
              if (cart.confirmed && cart.currentFood(line.food.id) != null)
                TextButton(onPressed: _busy ? null : () => _action(() async {
                  final current = cart.currentFood(line.food.id)!;
                  final confirmed = await confirmCartAction(context, 'Review menu changes',
                    'Update ${line.food.draft.name} (${rm(line.food.draft.priceSen)}) to '
                    '${current.draft.name} (${rm(current.draft.priceSen)})? Quantity stays the same.', 'Apply Latest');
                  if (mounted && confirmed) await cart.review(line.food.id, current.revision);
                }), child: const Text('Review Changes')),
            ],
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
              IconButton(tooltip: 'Decrease ${line.food.id}', icon: const Icon(Icons.remove_circle_outline),
                onPressed: _busy || line.quantity <= 1 ? null : () => _action(() async =>
                  cart.quantity(line.food.id, line.quantity - 1))),
              Text('${line.quantity}', key: ValueKey('quantity-${line.food.id}')),
              IconButton(tooltip: 'Increase ${line.food.id}', icon: const Icon(Icons.add_circle_outline),
                onPressed: _busy || line.quantity >= StudentCart.maxQuantity || cart.warning != null || cart.issue(line) != null
                  ? null : () => _action(() async => cart.quantity(line.food.id, line.quantity + 1))),
              TextButton(onPressed: _busy ? null : () => _action(() async {
                final confirmed = await confirmCartAction(context, 'Remove item?',
                  'Remove ${line.food.draft.name} from this unpaid cart?', 'Remove');
                if (mounted && confirmed) cart.remove(line.food.id);
              }), child: const Text('Remove')),
            ]),
          ]))),
        const SizedBox(height: 16), Text('Total: ${rm(cart.totalSen)}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: primaryOrange)),
        const Text('Display prices must be verified again during future checkout.'),
        const SizedBox(height: 16),
        const FilledButton(onPressed: null, child: Text('Checkout — available in Stage 2C')),
        TextButton(onPressed: _busy ? null : () => _action(() async {
          final confirmed = await confirmCartAction(context, 'Clear Cart?',
            'Remove all unpaid selections from your cart?', 'Clear Cart');
          if (mounted && confirmed) cart.clear();
        }), child: const Text('Clear Cart')),
        TextButton(onPressed: widget.onBrowse, child: const Text('Continue Browsing')),
      ],
    ]);
  });
}
