import 'package:flutter/material.dart';
import '../models/preparation_stats.dart';
import '../models/vendor_stall.dart';
import '../models/vendor_menu.dart';
import '../services/auth_repository.dart';
import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/stall_picture_picker.dart';

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
  late Stream<MenuData<PreparationStats>> _preparationStats;
  bool _busy = false;
  String? _error;

  Future<void> _setOpen(VendorStall stall) async {
    if (_busy || stall.isCached) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.repository.setStallOpen(!stall.isOpen);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(stall.isOpen ? 'Stall closed.' : 'Stall opened.')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _watchDashboard();
  }

  void _watchDashboard() {
    _stall = widget.repository.watchVendorStall();
    _preparationStats = widget.repository.watchPreparationStats();
  }

  @override
  void didUpdateWidget(covariant VendorDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _watchDashboard();
    }
  }

  Widget _preparationOverview(VendorStall? stall) => StreamBuilder<MenuData<PreparationStats>>(
    stream: _preparationStats,
    builder: (context, snapshot) {
      final current = snapshot.hasData ? snapshot.data! : null;
      final initialMinutes = stall?.preparationMinutes;
      final history = current != null && !snapshot.hasError && !current.cached &&
          stall != null && !stall.isCached ? current.items.firstOrNull : null;
      final verified = current != null && !snapshot.hasError && !current.cached &&
          stall != null && initialMinutes != null && !stall.isCached;
      final initial = initialMinutes == null ? 'Unavailable'
          : '$initialMinutes min${stall!.isCached ? ' (cached)' : ''}';
      final estimateMillis = history?.averageDurationMillis ??
          (initialMinutes == null ? null : initialMinutes * 60000);
      final estimate = !verified || estimateMillis == null ? 'Unavailable'
          : '${(estimateMillis + 59999) ~/ 60000} min';
      final samples = verified
          ? '${history?.sampleCount ?? 0} ${history?.sampleCount == 1 ? 'order' : 'orders'}'
          : 'Unavailable';
      return _card('Preparation Time Overview', [
        _preparationMetric('Initial Preparation Time', initial),
        const SizedBox(height: 10),
        _preparationMetric('Current Estimated Preparation Time', estimate,
          highlighted: true),
        const SizedBox(height: 10),
        _preparationMetric('Historical Samples Recorded', samples),
      ], key: const ValueKey('preparation-time-overview'));
    },
  );

  Widget _preparationMetric(String label, String value,
      {bool highlighted = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: highlighted ? lightOrange : const Color(0xFFF8F9FB),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: highlighted
          ? const Color(0xFFFFD8B8) : const Color(0xFFE7E9EE)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
          color: mutedText, fontSize: 13, fontWeight: FontWeight.w500,
        )),
        const SizedBox(height: 5),
        Text(value, style: TextStyle(
          color: highlighted ? primaryOrange : const Color(0xFF202124),
          fontSize: highlighted ? 20 : 17,
          fontWeight: FontWeight.w700,
        )),
      ],
    ),
  );

  Widget _card(String title, List<Widget> children, {Key? key}) => Container(
    key: key,
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
    Align(alignment: Alignment.centerLeft,
      child: StallPicture(stall.displayPictureId)),
    const SizedBox(height: 12),
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
    OutlinedButton(
      onPressed: _busy || stall.isCached ? null : () => _setOpen(stall),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (_busy) ...[
          const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
        ],
        Text(stall.isOpen ? 'Close Stall' : 'Open Stall'),
      ]),
    ),
    const SizedBox(height: 8),
    ErrorMessage(_error),
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
                    _preparationOverview(stall),
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
