import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Student presentation uses the same spacing and colors as the accepted Vendor workspace.
class StudentWorkspaceHeader extends StatelessWidget {
  const StudentWorkspaceHeader(this.title, {super.key, required this.icon, this.subtitle,
    this.back = false, this.action});
  final String title;
  final IconData icon;
  final String? subtitle;
  final bool back;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    decoration: const BoxDecoration(color: primaryOrange,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        if (back)
          IconButton(tooltip: 'Back', onPressed: Navigator.canPop(context) ? () => Navigator.maybePop(context) : null,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48))
        else
          CircleAvatar(radius: 25, backgroundColor: Colors.white, child: Icon(icon, color: primaryOrange)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 4), Text(subtitle!, style: const TextStyle(color: Colors.white)),
          ],
        ])),
      ]),
      if (action != null) ...[const SizedBox(height: 8), Align(alignment: Alignment.centerRight, child: action)],
    ]),
  );
}

/// A visible scrollbar makes additional categories discoverable on narrow phones.
class StudentFilterBar extends StatefulWidget {
  const StudentFilterBar({super.key, required this.labels, this.values, required this.selected, required this.onSelected});
  final List<String> labels;
  final List<String>? values;
  final String selected;
  final ValueChanged<String> onSelected;
  @override
  State<StudentFilterBar> createState() => _StudentFilterBarState();
}
class _StudentFilterBarState extends State<StudentFilterBar> {
  final _scroll = ScrollController();
  @override
  void dispose() { _scroll.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scrollbar(controller: _scroll, thumbVisibility: true,
    child: SingleChildScrollView(controller: _scroll, scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
        for (var i = 0; i < widget.labels.length; i++) Padding(padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(label: Text(widget.labels[i]), selected: (widget.values?[i] ?? widget.labels[i]) == widget.selected,
            showCheckmark: false, selectedColor: primaryOrange, backgroundColor: const Color(0xFFF0F1F4),
            labelStyle: TextStyle(color: (widget.values?[i] ?? widget.labels[i]) == widget.selected ? Colors.white : const Color(0xFF343A46),
              fontWeight: FontWeight.w600), materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) => widget.onSelected(widget.values?[i] ?? widget.labels[i]))),
      ])));
}

class StallStatusBadge extends StatelessWidget {
  const StallStatusBadge(this.open, {super.key});
  final bool open;
  @override
  Widget build(BuildContext context) {
    final color = open ? const Color(0xFF176B35) : const Color(0xFF596273);
    return Align(alignment: Alignment.centerLeft, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(20)),
      child: Text(open ? 'Open' : 'Closed', style: TextStyle(color: color, fontWeight: FontWeight.w700))));
  }
}

class StudentNotice extends StatelessWidget {
  const StudentNotice(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: lightOrange, borderRadius: BorderRadius.circular(12)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline, size: 20, color: Color(0xFF9B4500)), const SizedBox(width: 10),
      Expanded(child: Text(message, style: const TextStyle(color: Color(0xFF76400B)))),
    ]));
}
