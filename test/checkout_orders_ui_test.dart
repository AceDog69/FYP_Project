import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/confirmed_order.dart';
import 'package:my_fyp_app/models/user_profile.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/services/student_cart.dart';
import 'package:my_fyp_app/screens/orders_screen.dart';
import 'package:my_fyp_app/screens/student_cart_screen.dart';
import 'package:my_fyp_app/widgets/student_commerce_widgets.dart';
import 'support/catalog_fixtures.dart';
import 'support/fake_order_repository.dart';
import 'stage_one_test.dart' as stage;

void main() {
  Future<void> openCheckout(WidgetTester tester, stage.TestRepository repo) async {
    populate(repo.catalogRepository); await stage.launch(tester, repo);
    await tester.binding.setSurfaceSize(const Size(412, 915));
    await tester.pumpAndSettle();
    await stage.tap(tester, 'Alpha Kitchen'); await stage.tap(tester, 'Select Food');
    await stage.tap(tester, 'Add to Cart'); await stage.tap(tester, 'Cart (1)');
    await tester.tap(find.byKey(const ValueKey('cart-review-checkout'))); await tester.pumpAndSettle();
  }
  CheckoutRequest draft(stage.TestRepository repo, {String student = 'test-user', String vendor = 'alpha'}) => CheckoutRequest(
    id: repo.orderRepository.newSubmissionId(), studentUid: student, vendorUid: vendor, stallName: 'Synthetic Kitchen',
    paymentMethod: 'ewallet', items: [const OrderItem(foodId: 'food', name: 'Rice Bowl', description: 'Fresh rice',
      categoryId: 'rice', pictureId: 'nasi_lemak', priceSen: 850, quantity: 2, foodRevision: 1)]);

  testWidgets('review displays exact RM and simulated methods; confirmation stays visibly gated', (tester) async {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.student)); addTearDown(repo.dispose);
    await openCheckout(tester, repo);
    expect(find.text('Checkout Review'), findsOneWidget); expect(tester.widget<Text>(find.byKey(const ValueKey('commerce-total'))).data, 'RM 8.50');
    expect(find.text('Up to two distinct foods per order, 1–20 units each.'), findsOneWidget);
    expect(find.textContaining('no money is charged'), findsOneWidget);
    expect(find.byType(PaymentMethodCard), findsNWidgets(3));
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('checkout-confirm'))).onPressed, isNull);
    expect(repo.orderRepository.submitCalls, 0);
  });

  testWidgets('Pixel 6 Cart displays the two-food limit and keeps forty units eligible for review', (tester) async {
    final repo = stage.TestRepository(); addTearDown(repo.dispose); populate(repo.catalogRepository);
    repo.catalogRepository.foodItems['alpha']!.add(food('drink', price: 905, category: 'drinks'));
    final cart = StudentCart('test-user', repo.catalogRepository); addTearDown(cart.dispose);
    cart.add(await repo.catalogRepository.selection('alpha','bowl'), 20);
    cart.add(await repo.catalogRepository.selection('alpha','drink'), 20);
    await tester.binding.setSurfaceSize(const Size(412,915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var reviews = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StudentCartScreen(cart: cart,
      onBrowse: () {}, checkoutAvailable: true, onCheckout: () => reviews++))));
    await tester.pumpAndSettle();
    expect(find.text('Up to two distinct foods per order, 1–20 units each.'), findsOneWidget);
    await tester.ensureVisible(find.text('Review Checkout'));
    expect(tester.widget<Text>(find.byKey(const ValueKey('commerce-total'))).data, 'RM 351.00');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Review Checkout')).onPressed, isNotNull);
    await tester.tap(find.text('Review Checkout')); expect(reviews, 1); expect(cart.itemCount, 40);
  });

  testWidgets('acknowledged checkout clears Cart; pending duplicate taps do not confirm twice; Orders/details work', (tester) async {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.student)); addTearDown(repo.dispose);
    repo.orderRepository.enabled = true; repo.orderRepository.pending = Completer<void>();
    await openCheckout(tester, repo);
    await tester.tap(find.byKey(const ValueKey('checkout-confirm'))); await tester.pumpAndSettle();
    expect(repo.orderRepository.submitCalls, 1); expect(find.text('Order Confirmed'), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('checkout-confirm'))).onPressed, isNull);
    repo.orderRepository.pending!.complete(); await tester.pumpAndSettle();
    expect(find.text('Order Confirmed'), findsOneWidget); expect(find.text('Ticket #1'), findsOneWidget);
    await stage.tap(tester, 'View My Orders'); expect(find.text('My Orders'), findsOneWidget);
    expect(find.textContaining('Rice Bowl'), findsOneWidget); expect(find.textContaining('Pending'), findsOneWidget);
    await stage.tap(tester, 'View Details'); expect(find.text('Order Details'), findsOneWidget);
    expect(find.textContaining('simulated, no money charged'), findsOneWidget);
    await tester.pageBack(); await tester.pumpAndSettle(); await stage.tap(tester, 'Cart');
    expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets('failure retains Cart and request; retry uses same ID before acknowledged success', (tester) async {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.student)); addTearDown(repo.dispose);
    repo.orderRepository.enabled = true; repo.orderRepository.submitError = const AccountException('Connection interrupted.');
    await openCheckout(tester, repo); await tester.tap(find.byKey(const ValueKey('checkout-confirm'))); await tester.pumpAndSettle();
    expect(find.text('Connection interrupted.'), findsOneWidget); expect(tester.widget<Text>(find.byKey(const ValueKey('commerce-total'))).data, 'RM 8.50');
    final id = repo.orderRepository.submittedIds.single;
    await tester.pageBack(); await tester.pumpAndSettle();
    expect(find.textContaining('unconfirmed checkout is retained'), findsOneWidget);
    await stage.tap(tester, 'Resolve Checkout'); repo.orderRepository.submitError = null;
    await stage.tap(tester, 'Retry Same Checkout'); expect(find.text('Order Confirmed'), findsOneWidget);
    expect(repo.orderRepository.submittedIds.toSet(), {id});
  });

  testWidgets('Student ownership, persistent request recovery, logout and cached/error/Retry states', (tester) async {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.student)); addTearDown(repo.dispose);
    final q = draft(repo); final r = receiptFor(q,1); repo.orderRepository.receipts[q.id] = r;
    final pending = draft(repo); repo.orderRepository.requests[pending.id] = pending;
    await stage.launch(tester, repo); await stage.tap(tester, 'Orders');
    expect(find.text('Ticket #1'), findsOneWidget); expect(find.text('Resume'), findsOneWidget);
    repo.orderRepository.cached = true; repo.orderRepository.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Cached orders'), findsOneWidget);
    repo.orderRepository.cached = false; repo.orderRepository.errorTarget = 'orders';
    repo.orderRepository.streamError = StateError('offline'); repo.orderRepository.emit(); await tester.pumpAndSettle();
    expect(find.text('Unable to load orders. Retry'), findsOneWidget);
    repo.orderRepository.streamError = null; repo.orderRepository.errorTarget = null;
    await stage.tap(tester,'Unable to load orders. Retry'); expect(find.text('Ticket #1'), findsOneWidget);
    await stage.tap(tester, 'Profile'); await stage.tap(tester, 'Logout'); expect(find.text('Welcome Back'), findsOneWidget);
    repo.session(const UserProfile(uid:'different-student',fullName:'Synthetic Student',email:'other@example.com',
      phoneNumber:'0123456789',role:AccountRole.student)); await tester.pumpAndSettle();
    await stage.tap(tester,'Orders'); expect(find.text('No orders yet'), findsOneWidget); expect(find.text('Resume'), findsNothing);
  });

  testWidgets('Vendor own inbox receives immutable snapshots in ticket order without Stage 3 controls', (tester) async {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.vendor,setup:true)); addTearDown(repo.dispose);
    final first = draft(repo,student:'student',vendor:'test-user');
    repo.orderRepository.receipts[first.id] = receiptFor(first,1);
    await stage.launch(tester, repo); await stage.tap(tester,'Orders');
    expect(find.text('Vendor Orders'), findsOneWidget); expect(find.text('Ticket #1'), findsOneWidget);
    final next = draft(repo,student:'other-student',vendor:'test-user');
    repo.orderRepository.receipts[next.id] = receiptFor(next,2); repo.orderRepository.emit(); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ticket #2')); expect(find.text('Ticket #2'), findsOneWidget);
    expect(find.text('Start Preparing'), findsNothing); expect(find.text('Mark as Ready'), findsNothing);
    expect(tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).items.length,4);
  });

  testWidgets('Orders loading, empty, cached and targeted error states retry clearly', (tester) async {
    final orders = FakeOrderRepository(() => 'student')..loading = true; addTearDown(orders.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OrdersScreen(repository: orders,vendor:false))));
    await tester.pump(); expect(find.byType(CircularProgressIndicator), findsOneWidget);
    orders.loading = false; orders.emit(); await tester.pumpAndSettle();
    expect(find.text('No orders yet'), findsOneWidget);
    orders.cached = true; orders.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Cached orders'), findsOneWidget);
    orders.streamError = StateError('offline'); orders.errorTarget = 'orders'; orders.emit(); await tester.pumpAndSettle();
    expect(find.text('Unable to load orders. Retry'), findsOneWidget);
    orders.streamError = null; orders.errorTarget = null; orders.cached = false;
    await stage.tap(tester,'Unable to load orders. Retry'); expect(find.text('No orders yet'), findsOneWidget);
  });
}
