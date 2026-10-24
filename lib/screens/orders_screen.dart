import 'package:flutter/material.dart';
import '../models/confirmed_order.dart';
import '../models/vendor_menu.dart';
import '../models/vendor_queue.dart';
import '../services/auth_repository.dart';
import '../services/order_repository.dart';
import '../widgets/stall_picture_picker.dart';
import '../widgets/vendor_workspace_widgets.dart';
import '../widgets/student_workspace_widgets.dart';
import '../theme/app_theme.dart';

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
  final _filters = ScrollController();
  @override
  void dispose() { _filters.dispose(); super.dispose(); }
  @override
  void initState() { super.initState(); _load(); }
  @override
  void didUpdateWidget(covariant OrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository || oldWidget.vendor != widget.vendor) {
      _load();
    }
  }
  void _load() {
    _orders = widget.repository?.orders(vendor: widget.vendor);
    _requests = widget.vendor ? null : widget.repository?.pendingRequests();
    _queue = widget.vendor && widget.repository?.canProcessOrders == true ? widget.repository?.queue() : null;
  }
  Future<void> _advance(ConfirmedOrder order) async {
    if (_busy != null) {
      return;
    }
    setState(() { _busy = order.id; _error = null; });
    try {
      await widget.repository!.advance(order);
      // Status is supplied by confirmed stream snapshots, never an optimistic
      // local replacement. A lost acknowledgement requires review, not replay.
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is AccountException ? error.message
          : 'Status update was not confirmed. Refresh, review the current status and retry.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = null);
      }
    }
  }
  Widget _vendorPage(List<Widget> children) => VendorWorkspacePage(
    header: const VendorWorkspaceHeader('Vendor Orders', subtitle: 'Your stall’s order inbox'), children: children);
  Widget _studentPage(List<Widget> children) => VendorWorkspacePage(
    header: const StudentWorkspaceHeader('My Orders', icon: Icons.receipt_long_outlined,
      subtitle: 'Your confirmed orders and tickets'), children: children);
  @override
  Widget build(BuildContext context) => StreamBuilder<MenuData<ConfirmedOrder>>(stream: _orders, builder: (context, s) {
    if (widget.repository == null || s.hasError) {
      final retry = TextButton(onPressed: () => setState(_load), child: const Text('Unable to load orders. Retry'));
      return widget.vendor ? _vendorPage([VendorWorkspaceCard(child: retry)]) : _studentPage([VendorWorkspaceCard(child: retry)]);
    }
    if (!s.hasData || s.connectionState == ConnectionState.waiting) {
      const loading = Center(child: CircularProgressIndicator());
      return widget.vendor ? _vendorPage([const Padding(padding: EdgeInsets.all(32), child: loading)]) : _studentPage([const Padding(padding: EdgeInsets.all(32), child: loading)]);
    }
    final orders = s.data!.items.toList()..sort((a, b) => widget.vendor
      ? a.ticket.compareTo(b.ticket) : b.createdAt.compareTo(a.createdAt));
    return StreamBuilder<VendorQueue>(stream: _queue, builder: (context, cursor) {
      final children = <Widget>[
        if (widget.vendor) ...[
          Scrollbar(controller: _filters, thumbVisibility: true, child: SingleChildScrollView(
            key: const ValueKey('order-status-filters'), controller: _filters,
            scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              for (final label in ['All', ...orderStatuses]) Padding(padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(label == 'Completed' ? 'History' : label), selected: _filter == label,
                  showCheckmark: false, selectedColor: primaryOrange, backgroundColor: const Color(0xFFF0F1F4),
                  labelStyle: TextStyle(color: _filter == label ? Colors.white : const Color(0xFF343A46),
                    fontWeight: FontWeight.w600),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => setState(() => _filter = label))),
            ]))),
          const SizedBox(height: 12),
          Text(_filter == 'All' ? 'All Orders' : _filter == 'Completed' ? 'Order History' : '$_filter Orders',
            style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 6),
          const Text('Prepare tickets in order. One order may be Preparing at a time.', style: TextStyle(color: mutedText)),
          const SizedBox(height: 16),
          if (!widget.repository!.canProcessOrders) const Text('Order processing is disabled outside the local emulator demo.'),
          if (widget.repository!.canProcessOrders && !cursor.hasData && !cursor.hasError) const Text('Verifying preparation queue…'),
          if (cursor.hasError) TextButton(onPressed: _busy == null ? () => setState(_load) : null,
            child: const Text('Unable to verify preparation queue. Retry')),
          if (cursor.data?.cached == true) const Text('Cached queue — connect before changing an order.'),
        ],
        if (s.data!.cached) const Text('Cached orders — connect to verify current server data.'),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextButton(onPressed: _busy == null ? () => setState(() { _error = null; _load(); }) : null,
            child: const Text('Refresh orders before retrying')),
        ],
        if (!widget.vendor) StreamBuilder<MenuData<CheckoutRequest>>(stream: _requests, builder: (context, pending) {
          if (pending.hasError) {
            return TextButton(onPressed: () => setState(_load), child: const Text('Unable to recover checkouts. Retry'));
          }
          if (!pending.hasData) {
            return const Text('Checking for unconfirmed requests…');
          }
          return Column(children: [for (final request in pending.data!.items) VendorWorkspaceCard(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Unconfirmed checkout: ${request.stallName}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8), Text(pending.data!.cached
                ? 'Cached request — status may be out of date.' : 'Not a confirmed order or ticket.'),
              const SizedBox(height: 12),
              TextButton(style: TextButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                onPressed: pending.data!.cached ? null : () => widget.onResume?.call(request), child: const Text('Resume')),
            ]))]);
        }),
        if (orders.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Text('No orders yet', textAlign: TextAlign.center)),
        if (widget.vendor && orders.isNotEmpty && _filter != 'All' && !orders.any((o) => o.status == _filter))
          const Padding(padding: EdgeInsets.all(24), child: Text('No orders with this status')),
        for (final order in orders.where((o) => !widget.vendor || _filter == 'All' || o.status == _filter))
          _orderCard(context, order, s, cursor),
      ];
      return widget.vendor ? _vendorPage(children) : _studentPage(children);
    });
  });

  Widget _orderCard(BuildContext context, ConfirmedOrder order, AsyncSnapshot<MenuData<ConfirmedOrder>> s,
      AsyncSnapshot<VendorQueue> cursor) {
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8,
        children: [Text('Ticket #${order.ticket}', style: Theme.of(context).textTheme.headlineSmall), OrderStatusBadge(order.status)]),
      if (!widget.vendor) ...[const SizedBox(height: 10), Text(order.stallName,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))],
      const SizedBox(height: 6), Text('Placed at ${orderTime(order)}', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      _OrderItems(order: order, repository: widget.repository!, polished: true),
      const Divider(),
      Text('Confirmed total: ${rm(order.totalSen)}', style: const TextStyle(fontWeight: FontWeight.w700,
        fontSize: 20, color: primaryOrange)),
      if (widget.vendor && widget.repository!.canProcessOrders && order.nextStatus != null) ...[
        const SizedBox(height: 12),
        FilledButton(key: ValueKey('advance-${order.id}'),
          onPressed: _busy == null && _error == null && !s.data!.cached && !cursor.hasError && cursor.hasData &&
            cursor.connectionState != ConnectionState.waiting && cursor.data!.permits(order) ? () => _advance(order) : null,
          child: Text(_busy == order.id ? 'Confirming with server…' : switch (order.status) {
            'Pending' => 'Start Preparing', 'Preparing' => 'Mark as Ready', _ => 'Mark Completed after collection',
          })),
        if (order.status == 'Pending' && cursor.hasData && !cursor.data!.permits(order))
          const Text('Wait for the earlier ticket and an empty preparation slot.'),
      ],
      const SizedBox(height: 8),
      OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetails(
          order: order, repository: widget.repository!, vendor: widget.vendor))), child: const Text('View Details')),
    ]);
    return VendorWorkspaceCard(key: ValueKey(order.id), child: content);
  }
}

class _OrderItems extends StatefulWidget {
  const _OrderItems({required this.order, required this.repository, this.polished = false});
  final ConfirmedOrder order;
  final OrderRepository repository;
  final bool polished;
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
    if (!s.hasData) {
      return const Text('Loading order items…');
    }
    if (widget.polished) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (s.data!.cached) const Text('Cached item snapshots'),
        for (final item in s.data!.items) Padding(padding: const EdgeInsets.symmetric(vertical: 10),
          child: LayoutBuilder(builder: (context, constraints) {
            final stackedPrice = constraints.maxWidth < 300 || MediaQuery.textScalerOf(context).scale(14) > 18;
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StallPicture(item.pictureId, width: 56, height: 56), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${item.quantity} × ${item.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4), Text(item.categoryName, style: const TextStyle(color: mutedText)),
                Text('${rm(item.priceSen)} each', style: const TextStyle(color: mutedText, fontSize: 13)),
                if (stackedPrice) ...[const SizedBox(height: 6), Text(rm(item.subtotalSen),
                  style: const TextStyle(fontWeight: FontWeight.w700))],
              ])),
              if (!stackedPrice) ...[const SizedBox(width: 8), Text(rm(item.subtotalSen),
                style: const TextStyle(fontWeight: FontWeight.w700))],
            ]);
          })),
      ]);
    }
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
  Widget _page(List<Widget> children, {String? stallName}) => Scaffold(body: SafeArea(bottom: false,
    child: VendorWorkspacePage(header: VendorWorkspaceHeader('Order Details', subtitle: stallName, back: true), children: children)));
  Widget _section(BuildContext context, String title, List<Widget> children) => VendorWorkspaceCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 14), ...children,
    ]));
  String _progressText(ConfirmedOrder order) => switch (order.status) {
    'Pending' => 'Waiting for the stall to begin preparation.',
    'Preparing' => 'The stall is preparing this order.',
    'Ready' => 'Ready for pickup. Collect this order at the stall.',
    'Completed' => 'This order has been collected and completed.',
    _ => order.status,
  };
  @override
  Widget build(BuildContext context) => StreamBuilder<MenuData<ConfirmedOrder>>(stream: _orders, builder: (context, s) {
    if (s.hasError) {
      return _page([VendorWorkspaceCard(child: TextButton(onPressed: () => setState(() =>
        _orders = widget.repository.orders(vendor: widget.vendor)), child: const Text('Unable to load order. Retry')))]);
    }
    if (!s.hasData || s.connectionState == ConnectionState.waiting) {
      return _page([const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))]);
    }
    final matches = s.data!.items.where((o) => o.id == widget.order.id);
    if (matches.isEmpty) {
      return _page([const VendorWorkspaceCard(child: Text('Order is unavailable for this account.'))]);
    }
    final order = matches.single;
    final placed = orderTime(order);
    String stamp(DateTime t) {
      String two(int n) => n.toString().padLeft(2, '0');
      return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
    }
    return _page([
      if (s.data!.cached) const Padding(padding: EdgeInsets.only(bottom: 12),
        child: Text('Cached order — reconnect to verify current status.')),
      _section(context, 'Order Overview', [
        Text(order.stallName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)), const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8,
          children: [Text('Ticket #${order.ticket}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: primaryOrange)),
            OrderStatusBadge(order.status)]),
        const SizedBox(height: 12), Text(_progressText(order), style: const TextStyle(color: mutedText)),
      ]),
      _section(context, 'Order Information', [
        OrderInformationRow('Order Date', placed.substring(0, 10)), const Divider(height: 1),
        OrderInformationRow('Order Time', placed.substring(11)), const Divider(height: 1),
        OrderInformationRow('Stall', order.stallName), const Divider(height: 1),
        OrderInformationRow('Queue Ticket', '#${order.ticket}'),
        if (order.preparingAt != null) OrderInformationRow('Preparing since', stamp(order.preparingAt!.toDate().toLocal())),
        if (order.readyAt != null) OrderInformationRow('Ready at', stamp(order.readyAt!.toDate().toLocal())),
        if (order.completedAt != null) OrderInformationRow('Completed at', stamp(order.completedAt!.toDate().toLocal())),
      ]),
      _section(context, 'Ordered Items', [
        _OrderItems(order: order, repository: widget.repository, polished: true),
        const SizedBox(height: 8), const Text('Item snapshots are fixed at confirmation.', style: TextStyle(color: mutedText, fontSize: 12)),
      ]),
      _section(context, 'Payment Summary', [
        OrderInformationRow('Payment Method', simulatedPaymentMethods[order.paymentMethod]!), const Divider(height: 1),
        const OrderInformationRow('Payment Status', 'Confirmed (simulated)'), const Divider(height: 1),
        OrderInformationRow('Subtotal', rm(order.totalSen)), const Divider(height: 24),
        Text('Confirmed total: ${rm(order.totalSen)}', style: const TextStyle(color: primaryOrange, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12), Text('${simulatedPaymentMethods[order.paymentMethod]} — simulated, no money charged.',
          style: const TextStyle(color: mutedText)),
      ]),
      if (widget.vendor) const Text('Status changes are available in Vendor Orders.', style: TextStyle(color: mutedText)),
    ], stallName: order.stallName);
  });
}
