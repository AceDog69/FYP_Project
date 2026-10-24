import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/ready_notifications.dart';
import '../theme/app_theme.dart';
import '../widgets/student_workspace_widgets.dart';
import '../widgets/vendor_workspace_widgets.dart';
import 'orders_screen.dart';

String readyTime(Timestamp timestamp) {
  final t = timestamp.toDate().toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class ReadyNotificationButton extends StatelessWidget {
  const ReadyNotificationButton({super.key, required this.unread, required this.onPressed});
  final int unread;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Tooltip(message: 'Notifications, $unread unread', child: OutlinedButton(
    key: const ValueKey('ready-notifications-button'), onPressed: onPressed,
    style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
    child: Row(children: [const Icon(Icons.notifications_outlined), const SizedBox(width: 12),
      const Expanded(child: Text('Notifications')),
      if (unread > 0) Badge(backgroundColor: primaryOrange, label: Text(unread > 99 ? '99+' : '$unread')),
      const SizedBox(width: 12), const Icon(Icons.chevron_right),
    ])));
}

class ReadyNotificationsScreen extends StatefulWidget {
  const ReadyNotificationsScreen({super.key, required this.notifications, required this.onOpen});
  final ReadyNotifications notifications;
  final ValueChanged<String> onOpen;
  @override
  State<ReadyNotificationsScreen> createState() => _ReadyNotificationsScreenState();
}
class _ReadyNotificationsScreenState extends State<ReadyNotificationsScreen> {
  bool _history = false;
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: AnimatedBuilder(
    animation: widget.notifications, builder: (context, _) {
      final controller = widget.notifications;
      final notices = controller.notices.where((n) => (n.order.status == 'Completed') == _history).toList();
      return VendorWorkspacePage(header: const StudentWorkspaceHeader('Notifications', icon: Icons.notifications_outlined,
        subtitle: 'Updates for your confirmed orders', back: true), children: [
        StudentFilterBar(labels: const ['Ready', 'History'], selected: _history ? 'History' : 'Ready',
          onSelected: (label) => setState(() => _history = label == 'History')),
        const SizedBox(height: 12),
        if (controller.connection == ReadyConnection.loading) ...[
          const LinearProgressIndicator(), const SizedBox(height: 12),
          const Text('Checking for confirmed Ready updates…'), const SizedBox(height: 12),
        ],
        if (controller.connection == ReadyConnection.cached)
          const StudentNotice('Offline or cached orders — showing only previously confirmed notifications. Connect and refresh to verify current status.'),
        if (controller.connection == ReadyConnection.error)
          const StudentNotice('Ready updates could not be verified. Previously confirmed notifications may be out of date. Please retry.'),
        if (controller.connection == ReadyConnection.unavailable)
          const StudentNotice('Notifications are unavailable for this session.'),
        if (notices.isEmpty && controller.connection == ReadyConnection.server)
          Padding(padding: const EdgeInsets.all(24), child: Text(_history ? 'No completed Ready notifications yet' : 'No Ready notifications yet',
            textAlign: TextAlign.center)),
        for (final notice in notices) VendorWorkspaceCard(key: ValueKey('notice-${notice.order.id}'), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(notice.order.stallName, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
              children: [Text('Ticket #${notice.order.ticket}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                OrderStatusBadge(notice.order.status)]),
            const SizedBox(height: 12),
            Text(notice.order.status == 'Ready' ? 'Ready for pickup' : 'Completed — this order has been collected.',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF176B35))),
            const SizedBox(height: 8), Text('Ready at ${readyTime(notice.order.readyAt!)}', style: const TextStyle(color: mutedText)),
            const SizedBox(height: 12),
            Row(children: [Icon(notice.viewed ? Icons.drafts_outlined : Icons.mark_email_unread_outlined,
              size: 20, color: notice.viewed ? mutedText : primaryOrange), const SizedBox(width: 8),
              Text(notice.viewed ? 'Viewed' : 'Unread', style: TextStyle(color: notice.viewed ? mutedText : const Color(0xFF9B4500),
                fontWeight: FontWeight.w600))]),
            const SizedBox(height: 12),
            OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              onPressed: controller.sessionIsCurrent ? () => widget.onOpen(notice.order.id) : null, child: const Text('View Order Details')),
          ])),
        const SizedBox(height: 4),
        TextButton(style: TextButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
          onPressed: controller.sessionIsCurrent && controller.repository != null && controller.connection != ReadyConnection.loading
            ? () => controller.refresh() : null,
          child: Text(controller.connection == ReadyConnection.error ? 'Retry Notifications' : 'Refresh Notifications')),
        const SizedBox(height: 12),
        const Text('Existing Ready orders appear here without replaying an alert. Viewed status lasts until you sign out or restart this app.',
          style: TextStyle(color: mutedText)),
      ]);
    })));
}
