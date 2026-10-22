import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_repository.dart';
import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  late final _cart = StudentCart(widget.profile.uid, widget.repository.catalogRepository);
  late final _checkout = CheckoutController(_cart, widget.repository.orderRepository);
  int _index = 0;
  bool _busy = false;
  String? _error;
  bool get _vendor => widget.profile.role == AccountRole.vendor;
  @override
  void dispose() { _checkout.dispose(); _cart.dispose(); super.dispose(); }
  void _openCheckout([CheckoutRequest? request]) {
    if (request != null) {
      try { _checkout.resume(request); }
      catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resolve the open checkout first.')));
        return;
      }
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => CheckoutScreen(controller: _checkout,
      onOrders: () { Navigator.pop(context); setState(() => _index = 1); })));
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

  Widget _profile() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(child: IconTile(icon: Icons.person_outline)),
            const SizedBox(height: 24),
            Text('Profile', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            for (final entry in <String, String>{
              'Full Name': widget.profile.fullName,
              'Email Address': widget.profile.email,
              'Phone Number': widget.profile.phoneNumber,
              'Role': _vendor ? 'Vendor' : 'Student',
            }.entries) ...[
              Text(
                entry.key,
                style: const TextStyle(color: mutedText, fontSize: 12),
              ),
              const SizedBox(height: 6),
              SelectableText(entry.value),
              const SizedBox(height: 20),
            ],
            ErrorMessage(_error),
            PrimaryButton('Logout', onPressed: _logout, loading: _busy),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _vendor && (_index == 0 || _index == 2 || _index == 3) ? null : AppBar(
      automaticallyImplyLeading: false,
      title: const Brand(),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: Color(0xFFF0F0F0)),
      ),
    ),
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
          : !_vendor && _index == 0
          ? StudentHome(repository: widget.repository.catalogRepository,
              onStall: (stall) => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentStallMenu(
                vendorId: stall.id, repository: widget.repository.catalogRepository!, cart: _cart,
                onCart: () { Navigator.pop(context); setState(() => _index = 2); }))))
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
            icon: Icon(_icons[i], size: 23),
            label: _labels[i],
          ),
        ),
      ),
    ),
  );
}
