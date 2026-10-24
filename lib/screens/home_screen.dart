import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_repository.dart';
import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/student_workspace_widgets.dart';
import '../widgets/vendor_workspace_widgets.dart';
import '../widgets/vendor_profile_widgets.dart';
import 'vendor_dashboard.dart';
import 'vendor_profile.dart';
import 'vendor_menu_screen.dart';
import 'student_home.dart';
import 'student_stall_menu.dart';
import 'student_cart_screen.dart';
import '../services/student_cart.dart';
import '../services/checkout_controller.dart';
import '../models/confirmed_order.dart';
import 'checkout_screen.dart';
import 'orders_screen.dart';
import 'student_queue_screen.dart';
import '../services/ready_notifications.dart';
import 'ready_notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.profile,
    required this.repository,
  });
  final UserProfile profile;
  final AuthRepository repository;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final _cart = StudentCart(widget.profile.uid, widget.repository.catalogRepository);
  late final _checkout = CheckoutController(_cart, widget.repository.orderRepository);
  int _index = 0;
  bool _busy = false;
  String? _error;
  bool get _vendor => widget.profile.role == AccountRole.vendor;
  ReadyNotifications? _ready;
  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this); _listenForReady();
  }
  void _listenForReady() {
    _ready?.removeListener(_readyChanged); _ready?.dispose();
    _ready = _vendor ? null : ReadyNotifications(studentUid: widget.profile.uid,
      repository: widget.repository.orderRepository, currentUid: () => widget.repository.uid,
      foreground: WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
    _ready?.addListener(_readyChanged);
  }
  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid || oldWidget.profile.role != widget.profile.role ||
        oldWidget.repository != widget.repository) { _listenForReady(); }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { _ready?.setForeground(state == AppLifecycleState.resumed); }
  void _readyChanged() {
    if (!mounted) return;
    setState(() {});
    final source = _ready, ids = _ready?.takeAlerts() ?? [];
    if (ids.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || source != _ready || source?.sessionIsCurrent != true || source?.foreground != true ||
          source?.connection != ReadyConnection.server) { return; }
      final entries = ids.map((id) => source!.notice(id)).whereType<ReadyNotice>()
        .where((n) => !n.viewed && n.order.status == 'Ready').toList();
      if (entries.isEmpty) { return; }
      final text = entries.take(3).map((n) => '${n.order.stallName} • Ticket #${n.order.ticket}: Ready for pickup').join('\n');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(entries.length > 3 ? '$text\nMore Ready updates in Notifications.' : text),
        action: SnackBarAction(label: 'View', onPressed: () {
          if (!mounted || source != _ready || source?.sessionIsCurrent != true) return;
          if (entries.length == 1) { _openReady(entries.single.order.id); } else { _openNotifications(); }
        }),
      ));
    });
  }
  void _openReady(String orderId) {
    final notice = _ready?.notice(orderId), repository = widget.repository.orderRepository;
    if (notice == null || repository == null || _ready?.sessionIsCurrent != true) return;
    _ready!.markViewed(orderId);
    Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetails(order: notice.order, repository: repository)));
  }
  void _openNotifications() {
    final source = _ready;
    if (source?.sessionIsCurrent != true) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReadyNotificationsScreen(notifications: source!, onOpen: _openReady)));
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ready?.removeListener(_readyChanged); _ready?.dispose();
    _checkout.dispose(); _cart.dispose(); super.dispose();
  }
  void _openCheckout([CheckoutRequest? request]) {
    if (request != null) {
      try { _checkout.resume(request); }
      catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resolve the open checkout first.')));
        return;
      }
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => CheckoutScreen(controller: _checkout,
      onOrders: () { Navigator.pop(context); setState(() => _index = 1); },
      onNavigate: (index) { Navigator.pop(context); setState(() => _index = index); })));
  }
  List<String> get _labels => _vendor
      ? ['Dashboard', 'Orders', 'Menu', 'Profile']
      : ['Home', 'Orders', 'Cart', 'Queue', 'Profile'];
  List<IconData> get _icons => _vendor
      ? [
          Icons.storefront_outlined,
          Icons.receipt_long_outlined,
          Icons.restaurant_menu_outlined,
          Icons.person_outline,
        ]
      : [
          Icons.home_outlined,
          Icons.receipt_long_outlined,
          Icons.shopping_cart_outlined,
          Icons.people_outline,
          Icons.person_outline,
        ];
  Future<void> _logout() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.logout();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _profile() => VendorWorkspacePage(
    header: const StudentWorkspaceHeader('Profile & Settings', icon: Icons.person_outline),
    children: [
      VendorSection(title: 'Account Information', children: [
        VendorInformation('Full Name', widget.profile.fullName), const Divider(height: 1),
        VendorInformation('Email Address', widget.profile.email), const Divider(height: 1),
        VendorInformation('Phone Number', widget.profile.phoneNumber), const Divider(height: 1),
        const VendorInformation('Role', 'Student'),
      ]),
      ReadyNotificationButton(unread: _ready?.unreadCount ?? 0, onPressed: _busy ? null : _openNotifications),
      const SizedBox(height: 16),
      ErrorMessage(_error),
      OutlinedButton.icon(onPressed: _busy ? null : _logout,
        icon: const Icon(Icons.logout), label: Text(_busy ? 'Logging out…' : 'Logout'),
        style: OutlinedButton.styleFrom(foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red), minimumSize: const Size(double.infinity, 48))),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: _vendor && _index == 0
          ? VendorDashboard(
              repository: widget.repository,
              onOrders: () => setState(() => _index = 1),
              onMenu: () => setState(() => _index = 2),
            )
          : _vendor && _index == 2
          ? VendorMenuScreen(auth: widget.repository)
          : _vendor && _index == 3
          ? VendorProfile(profile: widget.profile, repository: widget.repository)
          : _index == _labels.length - 1
          ? _profile()
          : _index == 1
          ? OrdersScreen(repository: widget.repository.orderRepository, vendor: _vendor,
              onResume: _vendor ? null : _openCheckout)
          : !_vendor && _index == 2
          ? StudentCartScreen(cart: _cart, onBrowse: () => setState(() => _index = 0),
              onCheckout: _openCheckout, checkoutAvailable: widget.repository.orderRepository != null)
          : !_vendor && _index == 3
          ? StudentQueueScreen(repository: widget.repository.orderRepository, studentUid: widget.profile.uid)
          : !_vendor && _index == 0
          ? StudentHome(repository: widget.repository.catalogRepository,
              onStall: (stall) => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentStallMenu(
                vendorId: stall.id, repository: widget.repository.catalogRepository!, cart: _cart,
                onCart: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  Navigator.pop(context);
                  setState(() => _index = 2);
                }))))
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconTile(icon: _icons[_index]),
                    const SizedBox(height: 24),
                    Text(
                      _index == 0
                          ? 'Welcome, ${_vendor ? 'Vendor' : 'Student'}'
                          : _labels[_index],
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    if (_index != 0) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Coming soon',
                        style: TextStyle(color: mutedText),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    ),
    bottomNavigationBar: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 16),
        ],
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _index,
        selectedItemColor: primaryOrange,
        unselectedItemColor: mutedText,
        backgroundColor: Colors.white,
        elevation: 0,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        onTap: (index) => setState(() => _index = index),
        items: List.generate(
          _labels.length,
          (i) => BottomNavigationBarItem(
            tooltip: !_vendor && i == 4 ? 'Profile, ${_ready?.unreadCount ?? 0} unread notifications' : null,
            icon: !_vendor && i == 4 ? Badge(key: const ValueKey('student-notification-indicator'),
              isLabelVisible: (_ready?.unreadCount ?? 0) > 0,
              label: Text((_ready?.unreadCount ?? 0) > 99 ? '99+' : '${_ready?.unreadCount ?? 0}'),
              backgroundColor: primaryOrange, child: Icon(_icons[i], size: 23)) : Icon(_icons[i], size: 23),
            label: _labels[i],
          ),
        ),
      ),
    ),
  );
}
