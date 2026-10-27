import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/confirmed_order.dart';
import 'package:my_fyp_app/screens/orders_screen.dart';
import 'package:my_fyp_app/theme/app_theme.dart';
import 'package:my_fyp_app/widgets/student_workspace_widgets.dart';
import 'package:my_fyp_app/widgets/vendor_workspace_widgets.dart';
import 'student_queue_test.dart' as queue;
import 'support/fake_order_repository.dart';

OrderReceipt _receiptAt(int ticket, int createdAtMs) {
  final receipt = receiptFor(queue.queueRequest('$ticket'), ticket);
  final order = receipt.order;
  return OrderReceipt(ConfirmedOrder(
    id: order.id,
    studentUid: order.studentUid,
    vendorUid: order.vendorUid,
    stallName: order.stallName,
    ticket: order.ticket,
    totalSen: order.totalSen,
    itemCount: order.itemCount,
    preparationMinutes: order.preparationMinutes,
    paymentMethod: order.paymentMethod,
    createdAt: Timestamp.fromMillisecondsSinceEpoch(createdAtMs),
    firstItem: order.firstItem,
  ), receipt.items);
}

void main() {
  testWidgets(
    'Student Orders has no settled blank gap after fast flings and live inserts/status updates',
    (tester) async {
      const viewport = Size(320, 640);
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = FakeOrderRepository(() => 'student');
      addTearDown(repository.dispose);
      final baseTime = DateTime(2026, 10, 27).millisecondsSinceEpoch;
      for (var ticket = 1; ticket <= 12; ticket++) {
        final receipt = _receiptAt(ticket, baseTime + ticket * 60000);
        repository.receipts[receipt.order.id] = receipt;
      }

      await tester.pumpWidget(MaterialApp(
        theme: smartCanteenTheme().copyWith(platform: TargetPlatform.android),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(body: OrdersScreen(repository: repository, vendor: false)),
      ));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString().contains('StretchingOverscrollIndicator'),
        ),
        findsNothing,
        reason: 'Student Orders should not expose Android stretch overscroll.',
      );

      final list = find.byType(ListView).first;
      final scrollable = find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ).first;
      ScrollPosition position() => tester.state<ScrollableState>(scrollable).position;

      Future<void> assertNoSettledGap() async {
        await tester.pumpAndSettle();
        final viewportRect = tester.getRect(list);
        final cardRects = find.byType(VendorWorkspaceCard).evaluate()
            .map((element) => tester.getRect(find.byWidget(element.widget)))
            .where((rect) => rect.overlaps(viewportRect))
            .toList()
          ..sort((a, b) => a.top.compareTo(b.top));
        expect(cardRects, isNotEmpty, reason: 'At least one order card should occupy the viewport.');
        expect(cardRects.first.top - viewportRect.top, lessThan(90),
            reason: 'After scrolling settles, the visible order content must not leave a large blank band.');
        expect(position().pixels, inInclusiveRange(0, position().maxScrollExtent));
        expect(tester.takeException(), isNull);
      }

      // Repeated opposite-direction flings exercise Android's stretch boundary.
      for (var i = 0; i < 4; i++) {
        await tester.fling(scrollable, const Offset(0, -1000), 1000);
        await tester.pump(const Duration(milliseconds: 90));
        await tester.fling(scrollable, const Offset(0, 850), 1000);
        await tester.pump(const Duration(milliseconds: 90));
      }
      await assertNoSettledGap();

      // Apply status changes and insert a newest order while the list is in motion.
      await tester.fling(scrollable, const Offset(0, -1200), 1200);
      await tester.pump(const Duration(milliseconds: 70));
      for (final id in repository.receipts.keys.take(4).toList()) {
        final receipt = repository.receipts[id]!;
        repository.receipts[id] = OrderReceipt(progressed(receipt.order), receipt.items);
      }
      final newest = _receiptAt(99, baseTime + 99 * 60000);
      repository.receipts[newest.order.id] = newest;
      repository.emit();
      await tester.pump(const Duration(milliseconds: 90));

      // Reverse direction repeatedly while a second snapshot updates statuses.
      for (var i = 0; i < 3; i++) {
        await tester.fling(scrollable, const Offset(0, 900), 1000);
        await tester.pump(const Duration(milliseconds: 70));
        await tester.fling(scrollable, const Offset(0, -950), 1000);
        await tester.pump(const Duration(milliseconds: 70));
      }
      final latest = repository.receipts[newest.order.id]!;
      repository.receipts[newest.order.id] = OrderReceipt(progressed(latest.order), latest.items);
      repository.emit();
      await assertNoSettledGap();

      // Exercise the real Details push/pop path and ensure the list restores cleanly.
      final details = find.widgetWithText(OutlinedButton, 'View Details').first;
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.byType(OrderDetails), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(OrdersScreen), findsOneWidget);
      await assertNoSettledGap();

      // Explicitly verify both ends of the list after all live updates.
      position().jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(StudentWorkspaceHeader, 'My Orders'), findsOneWidget);
      expect(find.text('Ticket #99'), findsOneWidget);

      final firstCard = find.ancestor(
        of: find.text('Ticket #99'),
        matching: find.byType(VendorWorkspaceCard),
      );
      final firstCardAtRest = tester.getRect(firstCard);
      final topOverscroll = await tester.startGesture(const Offset(160, 300));
      await topOverscroll.moveBy(const Offset(0, 260));
      await tester.pump(const Duration(milliseconds: 80));
      await topOverscroll.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(firstCard), firstCardAtRest,
          reason: 'Android overscroll stretch should return to the original card geometry.');

      position().jumpTo(position().maxScrollExtent);
      await assertNoSettledGap();
      await tester.scrollUntilVisible(find.text('Ticket #1'), 300, scrollable: scrollable);
      await tester.pumpAndSettle();
      position().jumpTo(position().maxScrollExtent);
      await tester.pumpAndSettle();
      final lastCard = find.ancestor(
        of: find.text('Ticket #1'),
        matching: find.byType(VendorWorkspaceCard),
      );
      final lastCardAtRest = tester.getRect(lastCard);
      final bottomOverscroll = await tester.startGesture(const Offset(160, 300));
      await bottomOverscroll.moveBy(const Offset(0, -260));
      await tester.pump(const Duration(milliseconds: 80));
      await bottomOverscroll.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(lastCard), lastCardAtRest,
          reason: 'Bottom overscroll stretch should return to the original card geometry.');
      await assertNoSettledGap();
    },
  );
}
