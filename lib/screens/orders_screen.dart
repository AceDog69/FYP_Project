import 'package:flutter/material.dart';
import '../models/confirmed_order.dart';
import '../models/vendor_menu.dart';
import '../services/order_repository.dart';
import '../widgets/stall_picture_picker.dart';

String orderTime(ConfirmedOrder order) {
  final t = order.createdAt.toDate().toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.repository, required this.vendor, this.onResume});
  final OrderRepository? repository;
  final bool vendor;
  final ValueChanged<CheckoutRequest>? onResume;
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}
class _OrdersScreenState extends State<OrdersScreen> {
  late Stream<MenuData<ConfirmedOrder>>? _orders;
  late Stream<MenuData<CheckoutRequest>>? _requests;
  @override
  void initState() { super.initState(); _load(); }
  void _load() {
    _orders = widget.repository?.orders(vendor: widget.vendor);
    _requests = widget.vendor ? null : widget.repository?.pendingRequests();
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<MenuData<ConfirmedOrder>>(stream: _orders, builder: (context, s) {
    if (widget.repository == null || s.hasError) {
      return Center(child: TextButton(onPressed: () => setState(_load), child: const Text('Unable to load orders. Retry')));
    }
    if (!s.hasData || s.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    final orders = s.data!.items.toList()..sort((a, b) => widget.vendor
      ? a.ticket.compareTo(b.ticket) : b.createdAt.compareTo(a.createdAt));
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(widget.vendor ? 'Vendor Orders' : 'My Orders', style: Theme.of(context).textTheme.headlineSmall),
      if (s.data!.cached) const Text('Cached orders — connect to verify current server data.'),
      if (!widget.vendor) StreamBuilder<MenuData<CheckoutRequest>>(stream: _requests, builder: (context, pending) {
        if (pending.hasError) return TextButton(onPressed: () => setState(_load), child: const Text('Unable to recover checkouts. Retry'));
        if (!pending.hasData) return const Text('Checking for unconfirmed requests…');
        return Column(children: [for (final request in pending.data!.items) Card(child: ListTile(
          title: Text('Unconfirmed checkout: ${request.stallName}'), subtitle: Text(pending.data!.cached
            ? 'Cached request — status may be out of date.' : 'Not a confirmed order or ticket.'),
          trailing: TextButton(onPressed: pending.data!.cached ? null : () => widget.onResume?.call(request), child: const Text('Resume')),
        ))]);
      }),
      if (orders.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Text('No orders yet', textAlign: TextAlign.center)),
      for (final order in orders) Card(key: ValueKey(order.id), child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Ticket #${order.ticket}', style: Theme.of(context).textTheme.titleLarge),
          if (!widget.vendor) Text(order.stallName),
          Text('${order.status} • ${orderTime(order)}'),
          _OrderItems(order: order, repository: widget.repository!),
          Text('Confirmed total: ${rm(order.totalSen)}'),
          OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetails(
            order: order, repository: widget.repository!))), child: const Text('View Details')),
        ]))),
      if (widget.vendor) const Text('Read-only inbox. Preparation and queue transitions will be added in Stage 3.'),
    ]);
  });
}

class _OrderItems extends StatefulWidget {
  const _OrderItems({required this.order, required this.repository});
  final ConfirmedOrder order;
  final OrderRepository repository;
  @override
  State<_OrderItems> createState() => _OrderItemsState();
}
class _OrderItemsState extends State<_OrderItems> {
  late Stream<MenuData<OrderItem>> _items = widget.repository.items(widget.order);
  @override
  void didUpdateWidget(covariant _OrderItems oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.id != widget.order.id || oldWidget.repository != widget.repository) {
      _items = widget.repository.items(widget.order);
    }
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<MenuData<OrderItem>>(stream: _items, builder: (context, s) {
    if (s.hasError) return TextButton(onPressed: () => setState(() => _items = widget.repository.items(widget.order)),
      child: const Text('Unable to load items. Retry'));
    if (!s.hasData) return const Text('Loading order items…');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s.data!.cached) const Text('Cached item snapshots'),
      for (final item in s.data!.items) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
        StallPicture(item.pictureId, width: 48, height: 48), const SizedBox(width: 10),
        Expanded(child: Text('${item.quantity} × ${item.name}\n${item.categoryName} • ${rm(item.priceSen)} each')),
        Text(rm(item.subtotalSen)),
      ])),
    ]);
  });
}

class OrderDetails extends StatelessWidget {
  const OrderDetails({super.key, required this.order, required this.repository});
  final ConfirmedOrder order;
  final OrderRepository repository;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Order Details')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Ticket #${order.ticket}', style: Theme.of(context).textTheme.headlineSmall),
      Text(order.stallName), Text(order.status), Text(orderTime(order)),
      _OrderItems(order: order, repository: repository), Text('Confirmed total: ${rm(order.totalSen)}'),
      Text('${simulatedPaymentMethods[order.paymentMethod]} — simulated, no money charged.'),
      const Text('Item snapshots are fixed at confirmation. Live queue position and ETA are not available yet.'),
    ]));
}
