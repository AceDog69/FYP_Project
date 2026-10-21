import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class VendorProfileHeader extends StatelessWidget {
  const VendorProfileHeader(this.stallName, {super.key});
  final String? stallName;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    decoration: const BoxDecoration(color: primaryOrange,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
    child: Row(children: [
      const CircleAvatar(radius: 25, backgroundColor: Colors.white,
        child: Icon(Icons.storefront_outlined, color: primaryOrange)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Profile & Settings', style: TextStyle(color: Colors.white,
          fontSize: 22, fontWeight: FontWeight.w700)),
        if (stallName != null) ...[
          const SizedBox(height: 4),
          Text(stallName!, style: const TextStyle(color: Colors.white)),
        ],
      ])),
    ]),
  );
}

class VendorSection extends StatelessWidget {
  const VendorSection({super.key, required this.title, required this.children, this.action});
  final String title;
  final List<Widget> children;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE8E8EC))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (action != null) action!,
      ]),
      const SizedBox(height: 16), ...children,
    ]),
  );
}

class VendorInformation extends StatelessWidget {
  const VendorInformation(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Wrap(spacing: 16, runSpacing: 6, alignment: WrapAlignment.spaceBetween,
      children: [Text(label, style: const TextStyle(color: mutedText)), SelectableText(value)]),
  );
}
