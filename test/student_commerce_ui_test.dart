import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/screens/checkout_screen.dart';
import 'package:my_fyp_app/screens/student_cart_screen.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/services/checkout_controller.dart';
import 'package:my_fyp_app/services/student_cart.dart';
import 'package:my_fyp_app/widgets/student_commerce_widgets.dart';
import 'package:my_fyp_app/theme/app_theme.dart';
import 'support/catalog_fixtures.dart';
import 'support/fake_catalog_repository.dart';
import 'support/fake_order_repository.dart';

void main() {
  Future<StudentCart> cart() async {
    final catalog = FakeCatalogRepository(); addTearDown(catalog.dispose); populate(catalog);
    final result = StudentCart('student', catalog); addTearDown(result.dispose);
    result.add(await catalog.selection('alpha', 'bowl'), 2); return result;
  }
  Future<void> pixel(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(412, 915)); addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: smartCanteenTheme(), home: screen)); await tester.pumpAndSettle();
  }
  Future<void> press(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target); await tester.tap(target); await tester.pumpAndSettle();
  }
  testWidgets('reference Cart header, summary and 48px steppers retain precise money and quantity bounds', (tester) async {
    final selection = await cart(); var reviews = 0;
    await pixel(tester, Scaffold(body: StudentCartScreen(cart: selection, onBrowse: () {},
      onCheckout: () => reviews++, checkoutAvailable: true)));
    expect(find.widgetWithText(CommerceHeader, 'My Cart'), findsOneWidget);
    expect(find.text('Order Summary'), findsOneWidget); expect(find.text('RM 8.50 each'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('commerce-total'))).data, 'RM 17.00');
    expect(tester.getSize(find.byTooltip('Increase bowl')).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byTooltip('Decrease bowl')).width, greaterThanOrEqualTo(48));
    selection.quantity('bowl', 20); await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(find.byTooltip('Increase bowl')).onPressed, isNull);
    expect(tester.widget<Text>(find.byKey(const ValueKey('commerce-total'))).data, 'RM 170.00');
    selection.quantity('bowl', 1); await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(find.byTooltip('Decrease bowl')).onPressed, isNull);
    await press(tester, find.text('Review Checkout')); expect(reviews, 1); expect(tester.takeException(), isNull);
  });
  testWidgets('small Android Cart layout scrolls and Remove Cancel preserves the unpaid item', (tester) async {
    final selection = await cart();
    await pixel(tester, Scaffold(body: StudentCartScreen(cart: selection, onBrowse: () {})));
    await tester.binding.setSurfaceSize(const Size(320, 640)); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); await press(tester, find.byTooltip('Remove bowl'));
    await press(tester, find.text('Cancel')); expect(selection.lines.length, 1); expect(selection.totalSen, 1700);
    expect(find.text('Your cart is empty'), findsNothing);
  });
  testWidgets('full-width payment cards select one simulated method and send its stable ID', (tester) async {
    final selection = await cart(), orders = FakeOrderRepository(() => 'student')..enabled = true; addTearDown(orders.dispose);
    final controller = CheckoutController(selection, orders); addTearDown(controller.dispose);
    await pixel(tester, CheckoutScreen(controller: controller, onOrders: () {}));
    expect(find.widgetWithText(CommerceHeader, 'Checkout & Payment'), findsOneWidget);
    expect(find.byType(PaymentMethodCard), findsNWidgets(3));
    final bank = find.byKey(const ValueKey('payment-onlineBanking'));
    expect(tester.getSize(bank).width, greaterThan(300)); await press(tester, bank);
    expect(tester.widget<PaymentMethodCard>(bank).selected, true);
    expect(tester.widget<PaymentMethodCard>(find.byKey(const ValueKey('payment-ewallet'))).selected, false);
    expect(find.textContaining('no money is charged'), findsOneWidget);
    await press(tester, find.text('Confirm Order'));
    expect(orders.requests.values.single.paymentMethod, 'onlineBanking'); expect(find.text('Order Confirmed'), findsOneWidget);
    expect(selection.lines, isEmpty); expect(orders.receipts.values.single.order.totalSen, 1700);
  });
  testWidgets('pending confirmation locks payment/navigation and cannot display a success prematurely', (tester) async {
    final selection = await cart(), orders = FakeOrderRepository(() => 'student')..enabled = true;
    orders.pending = Completer<void>(); addTearDown(orders.dispose);
    final controller = CheckoutController(selection, orders); addTearDown(controller.dispose); var navigation = -1;
    await pixel(tester, CheckoutScreen(controller: controller, onOrders: () {}, onNavigate: (i) => navigation = i));
    await press(tester, find.text('Confirm Order'));
    expect(find.text('Order Confirmed'), findsNothing); expect(selection.checkoutLocked, true);
    expect(tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).onTap, isNull);
    expect(tester.widget<PaymentMethodCard>(find.byKey(const ValueKey('payment-card'))).onSelect, isNull);
    expect(orders.submitCalls, 1); expect(navigation, -1);
    orders.pending!.complete(); await tester.pumpAndSettle(); expect(find.text('Order Confirmed'), findsOneWidget);
    expect(selection.lines, isEmpty);
  });
  testWidgets('failed checkout preserves draft, selected payment and exact retry identity', (tester) async {
    final selection = await cart(), orders = FakeOrderRepository(() => 'student')..enabled = true;
    orders.submitError = const AccountException('Connection interrupted.'); addTearDown(orders.dispose);
    final controller = CheckoutController(selection, orders); addTearDown(controller.dispose);
    await pixel(tester, CheckoutScreen(controller: controller, onOrders: () {}));
    await press(tester, find.byKey(const ValueKey('payment-card'))); await press(tester, find.text('Confirm Order'));
    expect(find.text('Connection interrupted.'), findsOneWidget); expect(selection.totalSen, 1700); expect(selection.checkoutLocked, true);
    final id = orders.submittedIds.single;
    expect(tester.widget<PaymentMethodCard>(find.byKey(const ValueKey('payment-card'))).selected, true);
    expect(tester.widget<PaymentMethodCard>(find.byKey(const ValueKey('payment-ewallet'))).onSelect, isNull);
    orders.submitError = null; await press(tester, find.text('Retry Same Checkout'));
    expect(orders.submittedIds.toSet(), {id}); expect(find.text('Order Confirmed'), findsOneWidget);
  });
}
