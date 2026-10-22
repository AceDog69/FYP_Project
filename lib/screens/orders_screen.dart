import 'package:flutter/material.dart';
import '../models/confirmed_order.dart';
import '../models/vendor_menu.dart';
import '../models/vendor_queue.dart';
import '../services/auth_repository.dart';
import '../services/order_repository.dart';
import '../widgets/stall_picture_picker.dart';

String orderTime(ConfirmedOrder order) {
  final t = order.createdAt.toDate().toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Preparing' => const Color(0xFF1558A6),
      'Ready' => const Color(0xFF176B35),
      'Completed' => const Color(0xFF4E6557),
      _ => const Color(0xFF9B4500),
    };
    return Semantics(label: 'Order status: $status', child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
    ));
  }
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
  late Stream<VendorQueue>? _queue;
  String? _busy, _error;
  String _filter = 'All';
  @override
  void initState() { super.initState(); _load(); }
  @override
  void didUpdateWidget(covariant OrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository || oldWidget.vendor != widget.vendor) _load();
  }
  void _load() {
    _orders = widget.repository?.orders(vendor: widget.vendor);
    _requests = widget.vendor ? null : widget.repository?.pendingRequests();
    _queue = widget.vendor && widget.repository?.canProcessOrders == true ? widget.repository?.queue() : null;
  }
  Future<void> _advance(ConfirmedOrder order) async {
    if (_busy != null) return;
    setState(() { _busy = order.id; _error = null; });
    try {
      await widget.repository!.advance(order);
      // Status is supplied by confirmed stream snapshots, never an optimistic
      // local replacement. A lost acknowledgement requires review, not replay.
    } catch (error) {
      if (mounted) setState(() => _error = error is AccountException ? error.message
        : 'Status update was not confirmed. Refresh, review the current status and retry.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<MenuData<ConfirmedOrder>>(stream: _orders, builder: (context, s) {
    if (widget.repository == null || s.hasError) {
      return Center(child: TextButton(onPressed: () => setState(_load), child: const Text('Unable to load orders. Retry')));
    }
    if (!s.hasData || s.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    final orders = s.data!.items.toList()..sort((a, b) => widget.vendor
      ? a.ticket.compareTo(b.ticket) : b.createdAt.compareTo(a.createdAt));
    return StreamBuilder<VendorQueue>(stream: _queue, builder: (context, cursor) => ListView(
      padding: const EdgeInsets.all(20), children: [
      Text(widget.vendor ? 'Vendor Orders' : 'My Orders', style: Theme.of(context).textTheme.headlineSmall),
      if (widget.vendor) ...[
        const SizedBox(height: 8),
        const Text('Prepare tickets in order. One order may be Preparing at a time.'),
        if (!widget.repository!.canProcessOrders) const Text('Order processing is disabled outside the local emulator demo.'),
        if (widget.repository!.canProcessOrders && !cursor.hasData && !cursor.hasError) const Text('Verifying preparation queue…'),
        if (cursor.hasError) TextButton(onPressed: _busy == null ? () => setState(_load) : null,
          child: const Text('Unable to verify preparation queue. Retry')),
        if (cursor.data?.cached == true) const Text('Cached queue — connect before changing an order.'),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          for (final label in ['All', ...orderStatuses]) Padding(padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: Text(label == 'Completed' ? 'History' : label), selected: _filter == label,
              onSelected: (_) => setState(() => _filter = label))),
        ])),
      ],
      if (s.data!.cached) const Text('Cached orders — connect to verify current server data.'),
      if (_error != null) ...[
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton(onPressed: _busy == null ? () => setState(() { _error = null; _load(); }) : null,
          child: const Text('Refresh orders before retrying')),
      ],
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
      if (widget.vendor && orders.isNotEmpty && _filter != 'All' && !orders.any((o) => o.status == _filter))
        const Padding(padding: EdgeInsets.all(24), child: Text('No orders with this status')),
      for (final order in orders.where((o) => !widget.vendor || _filter == 'All' || o.status == _filter))
        Card(key: ValueKey(order.id), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE8E8ED))), child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8,
              children: [Text('Ticket #${order.ticket}', style: Theme.of(context).textTheme.headlineSmall), OrderStatusBadge(order.status)]),
            if (!widget.vendor) Text(order.stallName),
            const SizedBox(height: 6), Text('Placed at ${orderTime(order)}', style: Theme.of(context).textTheme.bodySmall),
            _OrderItems(order: order, repository: widget.repository!),
            const Divider(),
            Text('Confirmed total: ${rm(order.totalSen)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (widget.vendor && widget.repository!.canProcessOrders && order.nextStatus != null) ...[
              const SizedBox(height: 12),
              FilledButton(key: ValueKey('advance-${order.id}'),
                onPressed: _busy == null && !s.data!.cached && !cursor.hasError && cursor.hasData &&
                  cursor.connectionState != ConnectionState.waiting && cursor.data!.permits(order) ? () => _advance(order) : null,
                child: Text(_busy == order.id ? 'Confirming with server…' : switch (order.status) {
                  'Pending' => 'Start Preparing', 'Preparing' => 'Mark as Ready', _ => 'Mark Completed after collection',
                })),
              if (order.status == 'Pending' && cursor.hasData && !cursor.data!.permits(order))
                const Text('Wait for the earlier ticket and an empty preparation slot.'),
            ],
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetails(
              order: order, repository: widget.repository!, vendor: widget.vendor))), child: const Text('View Details')),
          ]))),
    ]));
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
    if (s.hasError) {
      return TextButton(onPressed: () => setState(() => _items = widget.repository.items(widget.order)),
        child: const Text('Unable to load items. Retry'));
    }
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

class OrderDetails extends StatefulWidget {
  const OrderDetails({super.key, required this.order, required this.repository, this.vendor = false});
  final ConfirmedOrder order;
  final OrderRepository repository;
  final bool vendor;
  @override
  State<OrderDetails> createState() => _OrderDetailsState();
}
class _OrderDetailsState extends State<OrderDetails> {
  late Stream<MenuData<ConfirmedOrder>> _orders = widget.repository.orders(vendor: widget.vendor);
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Order Details')),
    body: StreamBuilder<MenuData<ConfirmedOrder>>(stream: _orders, builder: (context, s) {
      if (s.hasError) return Center(child: TextButton(onPressed: () => setState(() =>
        _orders = widget.repository.orders(vendor: widget.vendor)), child: const Text('Unable to load order. Retry')));
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final matches = s.data!.items.where((o) => o.id == widget.order.id);
      if (matches.isEmpty) return const Center(child: Text('Order is unavailable for this account.'));
      final order = matches.single;
      return ListView(padding: const EdgeInsets.all(20), children: [
        Text('Ticket #${order.ticket}', style: Theme.of(context).textTheme.headlineSmall),
        Text(order.stallName), const SizedBox(height: 8), Align(alignment: Alignment.centerLeft, child: OrderStatusBadge(order.status)),
        if (s.data!.cached) const Text('Cached order — reconnect to verify current status.'),
        Text('Placed at ${orderTime(order)}'),
        _OrderItems(order: order, repository: widget.repository), Text('Confirmed total: ${rm(order.totalSen)}'),
        Text('${simulatedPaymentMethods[order.paymentMethod]} — simulated, no money charged.'),
        const Text('Item snapshots are fixed at confirmation. Live queue position and ETA are not available yet.'),
      ]);
    }));
}
