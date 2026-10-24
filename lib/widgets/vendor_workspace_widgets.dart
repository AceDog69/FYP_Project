import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Matches the accepted Dashboard/Profile without changing either screen.
class VendorWorkspaceHeader extends StatelessWidget {
  const VendorWorkspaceHeader(this.title, {super.key, this.subtitle, this.back = false});
  final String title;
  final String? subtitle;
  final bool back;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    decoration: const BoxDecoration(color: primaryOrange,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
    child: Row(children: [
      if (back)
        IconButton(tooltip: 'Back', onPressed: Navigator.canPop(context) ? () => Navigator.maybePop(context) : null,
          icon: Icon(Icons.arrow_back, color: Navigator.canPop(context) ? Colors.white : Colors.white54))
      else
        const CircleAvatar(radius: 25, backgroundColor: Colors.white,
          child: Icon(Icons.storefront_outlined, color: primaryOrange)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        if (subtitle != null) ...[
          const SizedBox(height: 4), Text(subtitle!, style: const TextStyle(color: Colors.white)),
        ],
      ])),
    ]),
  );
}

class VendorWorkspacePage extends StatelessWidget {
  const VendorWorkspacePage({super.key, required this.header, required this.children});
  final Widget header;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Material(color: const Color(0xFFFAFAFC), child: ListView(children: [
    header, const SizedBox(height: 20),
    for (final child in children) Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: SizedBox(width: double.infinity, child: child)))),
    const SizedBox(height: 20),
  ]));
}

class VendorWorkspaceCard extends StatelessWidget {
  const VendorWorkspaceCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE8E8EC))),
    child: child,
  );
}

class OrderInformationRow extends StatelessWidget {
  const OrderInformationRow(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(label, style: const TextStyle(color: mutedText))), const SizedBox(width: 16),
      Expanded(flex: 2, child: Text(value, textAlign: TextAlign.right)),
    ]));
}
