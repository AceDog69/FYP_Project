import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/confirmed_order.dart';
import '../models/queue_progress.dart';
import '../models/vendor_menu.dart';
import '../services/order_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/student_workspace_widgets.dart';
import '../widgets/vendor_workspace_widgets.dart';
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
  Widget _page(List<Widget> children) => VendorWorkspacePage(
    header: const StudentWorkspaceHeader('My Queue', icon: Icons.people_outline,
      subtitle: 'Follow your confirmed tickets. Each stall has its own queue.'), children: children);
  @override
  Widget build(BuildContext context) => StreamBuilder<MenuData<ConfirmedOrder>>(stream: _orders, builder: (context, s) {
    if (widget.repository == null || s.hasError) {
      return _page([VendorWorkspaceCard(child: TextButton(onPressed: () => setState(_load), child: const Text('Unable to load your queue. Retry')))]);
    }
    if (!s.hasData || s.connectionState == ConnectionState.waiting) {
      return _page([const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))]);
    }
    final own = s.data!.items.where((o) => o.studentUid == widget.studentUid).toList()
      ..sort((a, b) => a.vendorUid == b.vendorUid ? a.ticket.compareTo(b.ticket) : a.stallName.compareTo(b.stallName));
    final orders = own.where((o) => (o.status == 'Completed') == _history).toList();
    return _page([
      StudentFilterBar(key: const ValueKey('queue-filters'), labels: const ['Active', 'History'],
        selected: _history ? 'History' : 'Active', onSelected: (label) => setState(() => _history = label == 'History')),
      const SizedBox(height: 12),
      if (s.data!.cached) const StudentNotice('Cached orders — last known status only. Connect to verify current progress.'),
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
    final hasEstimate = verified && estimate.minutes != null;
    final ahead = verified && estimate.ahead != null ? '${estimate.ahead}' : 'Unavailable';
    final readyText = terminal ? '${widget.cachedOrder ? 'Last known: ' : ''}${order.status == 'Ready' ? 'Ready for pickup' : 'Completed'}'
      : hasEstimate ? 'Approx. ${estimate.minutes} min until Ready'
      : estimate.overdue ? 'Initial estimate elapsed' : 'Waiting time unavailable';
    return VendorWorkspaceCard(key: ValueKey('queue-${order.id}'), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(order.stallName, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8,
          children: [Text('Ticket #${order.ticket}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            OrderStatusBadge(order.status)]),
        const SizedBox(height: 16),
        if (widget.cachedOrder) const StudentNotice('Cached ticket — position and ETA are unverified.'),
        if (!terminal && !s.hasData && !s.hasError) const StudentNotice('Loading queue progress…'),
        if (s.hasError && !terminal) const StudentNotice('Unable to verify this stall’s queue progress.'),
        if (s.data?.cached == true) const StudentNotice('Cached queue — connect to verify progress.'),
        Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: lightOrange, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Orders ahead: ', style: TextStyle(fontSize: 15, color: Color(0xFF343A46))),
              TextSpan(text: ahead, style: TextStyle(fontSize: estimate.ahead == null || !verified ? 18 : 32,
                fontWeight: FontWeight.w800, color: const Color(0xFF151515))),
            ]), key: ValueKey('queue-ahead-${order.id}')),
            const Divider(height: 24),
            Text(readyText, key: ValueKey('queue-eta-${order.id}'), style: TextStyle(fontSize: 24,
              fontWeight: FontWeight.w800, color: hasEstimate || terminal ? primaryOrange : const Color(0xFF596273))),
          ])),
        if (!terminal && !hasEstimate) ...[const SizedBox(height: 12), Text(estimate.message)],
        const SizedBox(height: 12),
        ExpansionTile(key: ValueKey('queue-explanation-${order.id}'), tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12), title: const Text('How this estimate works',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          children: [Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (terminal || hasEstimate) Text(estimate.message),
            if (!terminal && hasEstimate) ...[const SizedBox(height: 8), Text(
              'Estimate checked: ${queueTime(Timestamp.fromDate(checkedAt))}', style: Theme.of(context).textTheme.bodySmall)],
            const SizedBox(height: 8),
            Text('Initial preparation allowance: ${order.preparationMinutes} min (recorded at confirmation).',
              style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text('Order updated: ${queueTime(order.statusUpdatedAt ?? order.createdAt)}', style: Theme.of(context).textTheme.bodySmall),
            if (s.data?.updatedAt != null) Text('Queue updated: ${queueTime(s.data!.updatedAt!)}', style: Theme.of(context).textTheme.bodySmall),
          ])]),
        TextButton(style: TextButton.styleFrom(minimumSize: const Size(double.infinity, 48)), onPressed: widget.onRefresh,
          child: const Text('Refresh Queue')),
        OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
          OrderDetails(order: order, repository: widget.repository))), child: const Text('View Order Details')),
      ]));
  });
}
