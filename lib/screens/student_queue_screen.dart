import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/confirmed_order.dart';
import '../models/queue_progress.dart';
import '../models/vendor_menu.dart';
import '../services/order_repository.dart';
import '../theme/app_theme.dart';
import 'orders_screen.dart';

String queueTime(Timestamp timestamp) {
  final t = timestamp.toDate().toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class StudentQueueScreen extends StatefulWidget {
  const StudentQueueScreen({super.key, required this.repository, required this.studentUid, this.clock});
  final OrderRepository? repository;
  final String studentUid;
  final DateTime Function()? clock;
  @override
  State<StudentQueueScreen> createState() => _StudentQueueScreenState();
}
class _StudentQueueScreenState extends State<StudentQueueScreen> {
  late Stream<MenuData<ConfirmedOrder>>? _orders;
  bool _history = false;
  @override
  void initState() { super.initState(); _load(); }
  void _load() { _orders = widget.repository?.orders(vendor: false); }
  @override
  void didUpdateWidget(covariant StudentQueueScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentUid != widget.studentUid || oldWidget.repository != widget.repository) {
      _history = false;
      _load();
    }
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<MenuData<ConfirmedOrder>>(stream: _orders, builder: (context, s) {
    if (widget.repository == null || s.hasError) {
      return Center(child: TextButton(onPressed: () => setState(_load), child: const Text('Unable to load your queue. Retry')));
    }
    if (!s.hasData || s.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    final own = s.data!.items.where((o) => o.studentUid == widget.studentUid).toList()
      ..sort((a, b) => a.vendorUid == b.vendorUid ? a.ticket.compareTo(b.ticket) : a.stallName.compareTo(b.stallName));
    final orders = own.where((o) => (o.status == 'Completed') == _history).toList();
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('My Queue', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('Follow your confirmed tickets. Each stall has its own queue.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('Active'), selected: !_history, onSelected: (_) => setState(() => _history = false)),
        ChoiceChip(label: const Text('History'), selected: _history, onSelected: (_) => setState(() => _history = true)),
      ]),
      if (s.data!.cached) const Text('Cached orders — last known status only. Connect to verify current progress.'),
      if (orders.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Text(
        _history ? 'No completed tickets yet' : 'No active tickets yet', textAlign: TextAlign.center)),
      for (final order in orders) _QueueCard(key: ValueKey('${widget.studentUid}/${order.id}'),
        order: order, repository: widget.repository!, cachedOrder: s.data!.cached, clock: widget.clock ?? DateTime.now, onRefresh: () => setState(_load)),
    ]);
  });
}

class _QueueCard extends StatefulWidget {
  const _QueueCard({super.key, required this.order, required this.repository, required this.cachedOrder, required this.clock, required this.onRefresh});
  final ConfirmedOrder order;
  final OrderRepository repository;
  final bool cachedOrder;
  final DateTime Function() clock;
  final VoidCallback onRefresh;
  @override
  State<_QueueCard> createState() => _QueueCardState();
}
class _QueueCardState extends State<_QueueCard> {
  bool _terminal(ConfirmedOrder order) => order.status == 'Ready' || order.status == 'Completed';
  Stream<QueueProgress> _stream() => _terminal(widget.order)
    ? Stream.value(QueueProgress.unavailable(widget.order.vendorUid))
    : widget.repository.queueProgress(widget.order.vendorUid);
  late Stream<QueueProgress> _progress = _stream();
  @override
  void didUpdateWidget(covariant _QueueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.vendorUid != widget.order.vendorUid || oldWidget.repository != widget.repository ||
        _terminal(oldWidget.order) != _terminal(widget.order)) {
      _progress = _stream();
    }
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<QueueProgress>(stream: _progress, builder: (context, s) {
    final order = widget.order, terminal = order.status == 'Ready' || order.status == 'Completed';
    final checkedAt = widget.clock();
    final estimate = estimateQueue(order, widget.cachedOrder ? QueueProgress.unavailable(order.vendorUid, cached: true)
      : s.data, checkedAt);
    final verified = !widget.cachedOrder && (terminal || (!s.hasError && s.hasData && s.connectionState != ConnectionState.waiting));
    return Card(key: ValueKey('queue-${order.id}'), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFE8E8ED))), child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(order.stallName, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8,
          children: [Text('Ticket #${order.ticket}', style: Theme.of(context).textTheme.headlineSmall), OrderStatusBadge(order.status)]),
        const SizedBox(height: 16),
        if (widget.cachedOrder) const Text('Cached ticket — position and ETA are unverified.'),
        if (!terminal && !s.hasData && !s.hasError) const Text('Loading queue progress…'),
        if (s.hasError && !terminal) const Text('Unable to verify this stall’s queue progress.'),
        if (s.data?.cached == true) const Text('Cached queue — connect to verify progress.'),
        Text('Orders ahead: ${verified && estimate.ahead != null ? estimate.ahead : 'Unavailable'}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(terminal ? '${widget.cachedOrder ? 'Last known: ' : ''}${order.status == 'Ready' ? 'Ready for pickup' : 'Completed'}'
          : verified && estimate.minutes != null ? 'Approx. ${estimate.minutes} min until Ready'
          : estimate.overdue ? 'Initial estimate elapsed' : 'Waiting time unavailable',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: primaryOrange)),
        const SizedBox(height: 8), Text(estimate.message),
        if (!terminal && verified && estimate.minutes != null) Text(
          'Estimate checked: ${queueTime(Timestamp.fromDate(checkedAt))}', style: Theme.of(context).textTheme.bodySmall),
        Text('Initial preparation allowance: ${order.preparationMinutes} min (recorded at confirmation).',
          style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Text('Order updated: ${queueTime(order.statusUpdatedAt ?? order.createdAt)}', style: Theme.of(context).textTheme.bodySmall),
        if (s.data?.updatedAt != null) Text('Queue updated: ${queueTime(s.data!.updatedAt!)}', style: Theme.of(context).textTheme.bodySmall),
        TextButton(onPressed: widget.onRefresh,
          child: const Text('Refresh Queue')),
        OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
          OrderDetails(order: order, repository: widget.repository))), child: const Text('View Order Details')),
      ])));
  });
}
