import 'package:flutter/material.dart';
import '../constants/checkout_limits.dart';
import '../models/confirmed_order.dart';
import '../models/vendor_menu.dart';
import '../services/checkout_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/student_commerce_widgets.dart';
import 'student_cart_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.controller, required this.onOrders, this.onNavigate});
  final CheckoutController controller;
  final VoidCallback onOrders;
  final ValueChanged<int>? onNavigate;
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}
class _CheckoutScreenState extends State<CheckoutScreen> {
  String _payment = 'ewallet';
  OrderReceipt? _receipt;
  Future<void> _discard() async {
    final controller = widget.controller;
    final confirmed = await confirmCartAction(context, 'Discard unconfirmed request?',
      'This checks the server first. A confirmed order cannot be cancelled; it will be recovered instead.', 'Check and Discard');
    if (!mounted || !confirmed) return;
    final result = await controller.discard();
    if (!mounted) return;
    if (result != null) { setState(() => _receipt = result); }
    else if (controller.request == null) { Navigator.pop(context); }
  }
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, widget.controller.cart]), builder: (context, _) {
      final controller = widget.controller, cart = controller.cart, saved = controller.request;
      final receipt = _receipt;
      final items = saved?.items ?? cart.lines.map((l) => OrderItem(foodId: l.food.id,
        name: l.food.draft.name, description: l.food.draft.description, categoryId: l.food.draft.categoryId,
        pictureId: l.food.draft.pictureId, priceSen: l.food.draft.priceSen, quantity: l.quantity, foodRevision: l.food.revision)).toList();
      final total = saved?.totalSen ?? cart.totalSen;
      return PopScope(canPop: !controller.busy, child: Scaffold(
        body: SafeArea(bottom: false, child: Column(children: [
          CommerceHeader(receipt == null ? 'Checkout & Payment' : 'Order Confirmed',
            onBack: controller.busy || !Navigator.canPop(context) ? null : () => Navigator.maybePop(context)),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: receipt != null ? [
            CommerceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.check_circle_outline, color: primaryOrange, size: 64), const SizedBox(height: 20),
              Text('Ticket #${receipt.order.ticket}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              Text(receipt.order.stallName, textAlign: TextAlign.center),
              Text('${receipt.order.status} — confirmed by the server', textAlign: TextAlign.center), const SizedBox(height: 16),
              Text('Confirmed total: ${rm(receipt.order.totalSen)}', textAlign: TextAlign.center,
                style: const TextStyle(color: primaryOrange, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12), const Text('Simulated payment only. No money was charged.', textAlign: TextAlign.center),
              const SizedBox(height: 24), FilledButton(onPressed: widget.onOrders, child: const Text('View My Orders')),
            ])),
          ] : [
            StallOrderContext(name: saved?.stallName ?? cart.stallName, products: items.length,
              units: items.fold(0, (sum, item) => sum + item.quantity)),
            const Text('Checkout Review', style: TextStyle(color: mutedText, fontSize: 12)),
            const Text(checkoutLimitsLabel, style: TextStyle(color: mutedText, fontSize: 12)), const SizedBox(height: 12),
            CommerceSummary(items: items, totalSen: total, pictures: true, payment: true),
            CommerceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Select Payment Method', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12),
              for (final method in simulatedPaymentMethods.keys) PaymentMethodCard(key: ValueKey('payment-$method'),
                method: method, selected: (saved?.paymentMethod ?? _payment) == method,
                onSelect: controller.busy || saved != null ? null : () => setState(() => _payment = method)),
            ])),
            Container(padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: lightOrange, borderRadius: BorderRadius.circular(12)),
              child: const Row(children: [Icon(Icons.info_outline, color: primaryOrange), SizedBox(width: 12),
                Expanded(child: Text('Simulated payment only — no money is charged.', style: TextStyle(color: mutedText)))])),
            if (saved != null) ...[
              Text('Method: ${simulatedPaymentMethods[saved.paymentMethod]} (simulated)'),
              const Text('A request identity is retained. Retry confirms at most this one order; safely discard it to edit the cart.'),
            ],
            if (!controller.enabled) const Text('Order confirmation is disabled until checkout security tests have passed and been reviewed.'),
            if (saved == null && !cart.checkoutEligible) const Text('Refresh/review the cart and select an Open stall before confirming.'),
            ErrorMessage(controller.error),
            if (saved != null) TextButton(onPressed: controller.busy || !controller.enabled ? null : _discard,
              child: const Text('Safely Discard Request')),
          ]))),
          if (receipt == null) Container(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE9EAF0)))),
            child: FilledButton(onPressed: controller.busy || !controller.enabled || (saved == null && !cart.checkoutEligible) ? null : () async {
              final result = await controller.confirm(_payment);
              if (mounted && result != null) setState(() => _receipt = result);
            }, child: Wrap(alignment: WrapAlignment.center, children: [
              Text(controller.busy ? 'Confirming with server…' : saved == null ? 'Confirm Order' : 'Retry Same Checkout'),
              if (!controller.busy && saved == null) Text(' · ${rm(total)}'),
            ]))),
        ])),
        bottomNavigationBar: widget.onNavigate == null ? null : BottomNavigationBar(currentIndex: 2,
          type: BottomNavigationBarType.fixed, selectedItemColor: primaryOrange, unselectedItemColor: mutedText,
          onTap: controller.busy ? null : widget.onNavigate, items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
            BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined), label: 'Cart'),
            BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: 'Queue'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
          ]),
      ));
    });
}
