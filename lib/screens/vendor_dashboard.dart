import 'package:flutter/material.dart';
import '../models/vendor_stall.dart';
import '../services/auth_repository.dart';
import '../services/error_messages.dart';
import '../theme/app_theme.dart';

class VendorDashboard extends StatefulWidget {
  const VendorDashboard({
    super.key,
    required this.repository,
    required this.onOrders,
    required this.onMenu,
  });

  final AuthRepository repository;
  final VoidCallback onOrders, onMenu;

  @override
  State<VendorDashboard> createState() => _VendorDashboardState();
}

class _VendorDashboardState extends State<VendorDashboard> {
  late Stream<VendorStall> _stall;

  @override
  void initState() {
    super.initState();
    _stall = widget.repository.watchVendorStall();
  }

  @override
  void didUpdateWidget(covariant VendorDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _stall = widget.repository.watchVendorStall();
    }
  }

  Widget _card(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE8E8EC)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );

  Widget _information(VendorStall stall) => _card('My Stall', [
    Text(stall.name, style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 6),
    Text(stall.category, style: const TextStyle(color: mutedText)),
    const Divider(height: 28),
    const Text('Stall Availability'),
    const SizedBox(height: 8),
    Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: stall.isOpen ? const Color(0xFFECFAEC) : const Color(0xFFF0F1F4),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          stall.isOpen ? 'Open' : 'Closed',
          style: TextStyle(color: stall.isOpen ? const Color(0xFF198A25) : mutedText),
        ),
      ),
    ),
    const SizedBox(height: 16),
    const Text('Initial Preparation Time'),
    const SizedBox(height: 6),
    Text('${stall.preparationMinutes} minutes'),
    const SizedBox(height: 16),
    OutlinedButton(
      onPressed: null,
      child: Text(stall.isOpen ? 'Close Stall' : 'Open Stall'),
    ),
    const SizedBox(height: 8),
    const Text(
      'Stall status changes are unavailable in this version. '
      'Open/Close will be enabled in Stage 2A-02.',
      style: TextStyle(color: mutedText, fontSize: 12),
    ),
  ]);

  @override
  Widget build(BuildContext context) => StreamBuilder<VendorStall>(
    stream: _stall,
    builder: (context, snapshot) {
      // A retry/error never displays retained data from a previous stream.
      final stall = snapshot.hasError ||
              snapshot.connectionState == ConnectionState.waiting
          ? null : snapshot.data;
      return ColoredBox(
        color: const Color(0xFFFAFAFC),
        child: ListView(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: const BoxDecoration(
                color: primaryOrange,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Row(children: [
                const CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.storefront_outlined, color: primaryOrange),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Vendor Dashboard', style: TextStyle(
                      color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                    if (stall != null) ...[
                      const SizedBox(height: 4),
                      Text(stall.name, style: const TextStyle(color: Colors.white)),
                    ],
                  ],
                )),
              ]),
            ),
            Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator(
                          semanticsLabel: 'Loading stall information')),
                      )
                    else if (stall == null)
                      _card('Unable to Load Stall', [
                        Text(snapshot.error is AccountException
                            ? friendlyError(snapshot.error!)
                            : 'Stall information could not be loaded. Check your connection and retry.'),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => setState(() {
                            _stall = widget.repository.watchVendorStall();
                          }),
                          child: const Text('Retry'),
                        ),
                      ])
                    else ...[
                      if (stall.isCached)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text('Cached stall information — may be out of date.',
                            style: TextStyle(color: mutedText)),
                        ),
                      _information(stall),
                    ],
                    _card('Order Overview', [
                      const Text('Order information is not available yet.',
                        style: TextStyle(color: mutedText)),
                    ]),
                    _card('Quick Actions', [
                      Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.receipt_long_outlined,
                            color: primaryOrange,
                          ),
                          title: const Text('View Orders'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: widget.onOrders,
                        ),
                      ),
                      Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.restaurant_menu_outlined,
                            color: primaryOrange,
                          ),
                          title: const Text('Manage Menu'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: widget.onMenu,
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            )),
          ],
        ),
      );
    },
  );
}
