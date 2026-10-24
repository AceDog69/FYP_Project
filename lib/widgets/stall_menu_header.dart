import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Only Stall Menu opts into this adaptive Back/title/Cart row.
class StallMenuHeader extends StatelessWidget {
  const StallMenuHeader({super.key, required this.itemCount, required this.onCart});
  final int itemCount;
  final VoidCallback onCart;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    decoration: const BoxDecoration(color: primaryOrange,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
    child: LayoutBuilder(builder: (context, constraints) {
      const titleStyle = TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700);
      const actionStyle = TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600);
      double width(String value, TextStyle style) {
        final painter = TextPainter(text: TextSpan(text: value, style: DefaultTextStyle.of(context).style.merge(style)),
          textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context), maxLines: 1)..layout();
        final result = painter.width; painter.dispose(); return result;
      }
      final cartLabel = 'Cart ($itemCount)', actionWidth = width('Cart ($itemCount)', actionStyle) + 24;
      final inline = 48 + 12 + width('Stall Menu', titleStyle) + 12 + (actionWidth < 48 ? 48 : actionWidth) <= constraints.maxWidth;
      final cart = TextButton(key: const ValueKey('stall-menu-cart'), onPressed: onCart,
        style: TextButton.styleFrom(foregroundColor: Colors.white, textStyle: actionStyle,
          minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 12)), child: Text(cartLabel));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(tooltip: 'Back', onPressed: Navigator.canPop(context) ? () => Navigator.maybePop(context) : null,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48), icon: const Icon(Icons.arrow_back, color: Colors.white)),
          const SizedBox(width: 12), const Expanded(child: Text('Stall Menu', style: titleStyle)),
          if (inline) ...[const SizedBox(width: 12), cart],
        ]),
        if (!inline) ...[const SizedBox(height: 8), Align(alignment: Alignment.centerRight, child: cart)],
      ]);
    }),
  );
}
