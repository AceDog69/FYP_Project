import 'package:flutter/material.dart';
import '../models/confirmed_order.dart';
import '../models/vendor_menu.dart';
import '../services/checkout_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/stall_picture_picker.dart';
import 'student_cart_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.controller, required this.onOrders});
  final CheckoutController controller;
  final VoidCallback onOrders;
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}
class _CheckoutScreenState extends State<CheckoutScreen> {
  String _payment = 'ewallet';
  OrderReceipt? _receipt;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, widget.controller.cart]), builder: (context, _) {
      final controller = widget.controller, cart = controller.cart, saved = controller.request;
      final receipt = _receipt;
      return PopScope(canPop: !controller.busy, child: Scaffold(
        appBar: AppBar(title: Text(receipt == null ? 'Checkout Review' : 'Order Confirmed')),
        body: ListView(padding: const EdgeInsets.all(20), children: receipt != null ? [
          const Icon(Icons.check_circle_outline, color: primaryOrange, size: 64),
          const SizedBox(height: 20), Text('Ticket #${receipt.order.ticket}', style: Theme.of(context).textTheme.headlineSmall),
          Text(receipt.order.stallName), const Text('Pending — confirmed by the server'),
          Text('Confirmed total: ${rm(receipt.order.totalSen)}'),
          const Text('Simulated payment only. No money was charged.'),
          const SizedBox(height: 24), FilledButton(onPressed: widget.onOrders, child: const Text('View My Orders')),
        ] : [
          Text(saved?.stallName ?? cart.stallName, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text('Simulated payment only — no money is charged.', style: TextStyle(color: primaryOrange, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          for (final item in saved?.items ?? cart.lines.map((l) => OrderItem(foodId: l.food.id,
            name: l.food.draft.name, description: l.food.draft.description, categoryId: l.food.draft.categoryId,
            pictureId: l.food.draft.pictureId, priceSen: l.food.draft.priceSen, quantity: l.quantity, foodRevision: l.food.revision)))
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
              StallPicture(item.pictureId, width: 64, height: 64), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name), Text('${item.quantity} × ${rm(item.priceSen)}'), Text(rm(item.subtotalSen)),
              ])),
            ]))),
          Text('Total: ${rm(saved?.totalSen ?? cart.totalSen)}', style: Theme.of(context).textTheme.titleLarge),
          if (saved == null) ...[
            const SizedBox(height: 20), const Text('Simulated payment method'),
            for (final method in simulatedPaymentMethods.entries) Padding(padding: const EdgeInsets.symmetric(vertical: 4),
              child: ChoiceChip(label: Text(method.value), showCheckmark: false, selected: _payment == method.key,
                onSelected: controller.busy ? null : (_) => setState(() => _payment = method.key))),
          ] else ...[
            Text('Method: ${simulatedPaymentMethods[saved.paymentMethod]} (simulated)'),
            const Text('A request identity is retained. Retry confirms at most this one order; safely discard it to edit the cart.'),
          ],
          const SizedBox(height: 16),
          if (!controller.enabled) const Text('Order confirmation is disabled until checkout security tests have passed and been reviewed.'),
          if (saved == null && !cart.checkoutEligible) const Text('Refresh/review the cart and select an Open stall before confirming.'),
          ErrorMessage(controller.error),
          FilledButton(onPressed: controller.busy || !controller.enabled || (saved == null && !cart.checkoutEligible) ? null : () async {
            final result = await controller.confirm(_payment);
            if (mounted && result != null) setState(() => _receipt = result);
          }, child: Text(controller.busy ? 'Confirming with server…' : saved == null ? 'Confirm Order' : 'Retry Same Checkout')),
          if (saved != null) TextButton(onPressed: controller.busy || !controller.enabled ? null : () async {
            final confirmed = await confirmCartAction(context, 'Discard unconfirmed request?',
              'This checks the server first. A confirmed order cannot be cancelled; it will be recovered instead.', 'Check and Discard');
          if (!mounted || !context.mounted || !confirmed) return;

          final result = await controller.discard();

          if (!mounted || !context.mounted) return;

          if (result != null) {
            setState(() => _receipt = result);
          } else if (controller.request == null) {
            Navigator.pop(context);
          }
          }, child: const Text('Safely Discard Request')),
        ],
      )));
    });
}
