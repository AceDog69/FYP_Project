import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/confirmed_order.dart';
import 'package:my_fyp_app/models/user_profile.dart';
import 'package:my_fyp_app/models/vendor_menu.dart';
import 'package:my_fyp_app/screens/orders_screen.dart';
import 'package:my_fyp_app/screens/home_screen.dart';
import 'package:my_fyp_app/screens/student_home.dart';
import 'package:my_fyp_app/screens/student_queue_screen.dart';
import 'package:my_fyp_app/screens/student_stall_menu.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/services/student_cart.dart';
import 'package:my_fyp_app/theme/app_theme.dart';
import 'package:my_fyp_app/widgets/stall_picture_picker.dart';
import 'package:my_fyp_app/widgets/student_workspace_widgets.dart';
import 'package:my_fyp_app/widgets/vendor_workspace_widgets.dart';
import 'stage_one_test.dart' as stage;
import 'student_queue_test.dart' as queue;
import 'support/catalog_fixtures.dart';
import 'support/fake_catalog_repository.dart';
import 'support/fake_order_repository.dart';

class _LogoutRepository extends stage.TestRepository {
  final pendingLogout = Completer<void>();
  int logoutCalls = 0;
  @override
  Future<void> logout() async {
    logoutCalls++;
    await pendingLogout.future;
    await super.logout();
  }
}

void main() {
  Finder vertical() => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
  Future<void> reveal(WidgetTester tester, Finder target, {double delta = 200}) async {
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(target, delta, scrollable: vertical());
    }
    await tester.ensureVisible(target); await tester.pumpAndSettle();
  }
  Future<void> press(WidgetTester tester, Finder target, {double delta = 200}) async {
    await reveal(tester, target, delta: delta); await tester.tap(target); await tester.pumpAndSettle();
  }
  Future<void> mount(WidgetTester tester, Widget screen, {Size size = const Size(412, 915), double scale = 1}) async {
    await tester.binding.setSurfaceSize(size); addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: smartCanteenTheme(), builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: Scaffold(body: screen)));
    await tester.pump(); await tester.pump();
  }
  FakeCatalogRepository catalog() {
    final repo = FakeCatalogRepository(); populate(repo); addTearDown(repo.dispose); return repo;
  }
  StudentCart cart(FakeCatalogRepository repo) {
    final result = StudentCart('student', repo); addTearDown(result.dispose); return result;
  }
  FakeOrderRepository orders() {
    final repo = FakeOrderRepository(() => 'student'); addTearDown(repo.dispose); return repo;
  }

  testWidgets('Home has accepted orange header, white cards, real stall context and 48px View Menu', (tester) async {
    final repo = catalog(); String? opened;
    await mount(tester, StudentHome(repository: repo, onStall: (s) => opened = s.id)); await tester.pumpAndSettle();
    final header = find.widgetWithText(StudentWorkspaceHeader, 'Welcome, Student');
    expect(tester.getSize(header).width, 412);
    final card = find.byKey(const ValueKey('stall-alpha'));
    expect(tester.widget<VendorWorkspaceCard>(card), isA<VendorWorkspaceCard>());
    expect(find.descendant(of: card, matching: find.text('Malay')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Open')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Initial preparation: 15 minutes')), findsOneWidget);
    final action = find.descendant(of: card, matching: find.widgetWithText(FilledButton, 'View Menu'));
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48)); await press(tester, action); expect(opened, 'alpha');
  });

  testWidgets('Home search, clear and horizontal categories preserve closed-stall browsing', (tester) async {
    final repo = catalog(); String? opened;
    await mount(tester, StudentHome(repository: repo, onStall: (s) => opened = s.id)); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'aLpHa'); await tester.pumpAndSettle();
    expect(find.text('Alpha Kitchen'), findsOneWidget); expect(find.text('Beta Kitchen'), findsNothing);
    await press(tester, find.byTooltip('Clear search'));
    await press(tester, find.widgetWithText(ChoiceChip, 'Chinese'));
    expect(find.text('Closed'), findsOneWidget); expect(find.text('Alpha Kitchen'), findsNothing);
    await press(tester, find.widgetWithText(FilledButton, 'View Menu')); expect(opened, 'closed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home loading, cached warning, stream error and explicit Retry remain visible', (tester) async {
    final repo = catalog()..loading = true;
    await mount(tester, StudentHome(repository: repo, onStall: (_) {}));
    expect(find.text('Welcome, Student'), findsOneWidget); expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.loading = false; repo.cached = true; repo.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Cached stalls'), findsOneWidget);
    repo.errorTarget = 'home'; repo.error = StateError('offline'); repo.emit(); await tester.pumpAndSettle();
    expect(find.text('Stalls could not be loaded. Check your connection.'), findsOneWidget);
    repo.error = null; repo.cached = false; await press(tester, find.widgetWithText(TextButton, 'Retry'));
    expect(find.text('Alpha Kitchen'), findsOneWidget);
  });

  testWidgets('Stall Menu compact pictures, category IDs and Select Food retain precise quantity and Cart behavior', (tester) async {
    final repo = catalog(), selection = cart(repo); var cartVisits = 0;
    await mount(tester, StudentStallMenu(vendorId: 'alpha', repository: repo, cart: selection, onCart: () => cartVisits++));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('student-food-bowl'));
    final picture = tester.widget<StallPicture>(find.descendant(of: card, matching: find.byType(StallPicture)));
    expect(picture.width, 88); expect(picture.height, 96); expect(find.text('Hidden Food'), findsNothing);
    expect(find.descendant(of: card, matching: find.text('RM 8.50')), findsOneWidget);
    final select = find.widgetWithText(OutlinedButton, 'Select Food');
    await reveal(tester, select); expect(tester.getSize(select).height, greaterThanOrEqualTo(48)); await press(tester, select);
    Finder quantityButton(String tooltip) => find.ancestor(
      of: find.byTooltip(tooltip), matching: find.byType(IconButton));
    expect(tester.widget<IconButton>(quantityButton('Decrease quantity')).onPressed, isNull);
    for (var i = 1; i < 20; i++) { await tester.tap(quantityButton('Increase quantity')); await tester.pump(); }
    expect(tester.widget<IconButton>(quantityButton('Increase quantity')).onPressed, isNull);
    expect(find.text('Subtotal: RM 170.00'), findsOneWidget);
    await press(tester, find.text('Add to Cart')); expect(selection.lines.single.quantity, 20);
    await press(tester, find.text('Cart (20)'), delta: -200); expect(cartVisits, 1);
  });

  testWidgets('Menu filters use stable IDs even when a category is named All', (tester) async {
    final repo = catalog(), selection = cart(repo);
    repo.categoryItems['alpha']!.add(const MenuCategory('all-foods', 'All', 1));
    repo.foodItems['alpha']!.add(food('tea', name: 'Tea', category: 'all-foods'));
    await mount(tester, StudentStallMenu(vendorId: 'alpha', repository: repo, cart: selection, onCart: () {}));
    await tester.pumpAndSettle();
    final bar = find.byKey(const ValueKey('menu-categories'));
    final all = find.descendant(of: bar, matching: find.widgetWithText(ChoiceChip, 'All'));
    await press(tester, all.last); expect(find.text('Rice Bowl'), findsNothing); expect(find.text('Tea'), findsOneWidget);
    await press(tester, all.first); expect(find.text('Rice Bowl'), findsOneWidget);
  });

  testWidgets('Menu cache, closed stall, unavailable food and Retry retain safe selection gates', (tester) async {
    final repo = catalog(), selection = cart(repo); repo.cached = true;
    await mount(tester, StudentStallMenu(vendorId: 'alpha', repository: repo, cart: selection, onCart: () {}));
    await tester.pumpAndSettle(); expect(find.textContaining('Cached menu'), findsOneWidget);
    final select = find.widgetWithText(OutlinedButton, 'Select Food');
    await reveal(tester, select); expect(tester.widget<OutlinedButton>(select).onPressed, isNull);
    repo.cached = false; repo.stallItems[0] = listing('alpha', open: false); repo.emit(); await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(select).onPressed, isNull);
    repo.foodItems['alpha']![0] = food('bowl', available: false); repo.emit(); await tester.pumpAndSettle();
    expect(find.text('No available food items'), findsOneWidget);
    repo.errorTarget = 'foods'; repo.error = StateError('offline'); repo.emit(); await tester.pumpAndSettle();
    expect(find.text('Unable to load menu. Retry'), findsOneWidget);
    repo.error = null; await press(tester, find.text('Unable to load menu. Retry'));
    expect(find.text('No available food items'), findsOneWidget);
  });

  testWidgets('selection still rejects a stale revision and keeps its draft available for retry', (tester) async {
    final repo = catalog(), selection = cart(repo);
    await mount(tester, StudentStallMenu(vendorId: 'alpha', repository: repo, cart: selection, onCart: () {}));
    await tester.pumpAndSettle(); await press(tester, find.widgetWithText(OutlinedButton, 'Select Food'));
    repo.foodItems['alpha']![0] = food('bowl', revision: 2); // Do not replace the displayed revision.
    await press(tester, find.text('Add to Cart'));
    expect(find.text('Food details changed. Review and retry.'), findsOneWidget); expect(selection.lines, isEmpty);
    expect(find.text('Food selection'), findsOneWidget); await press(tester, find.text('Cancel'));
    expect(find.text('Food selection'), findsNothing);
  });

  testWidgets('Student Orders use matching cards, status badge and snapshots with accepted shared Details', (tester) async {
    final repo = orders(), receipt = receiptFor(queue.queueRequest('1'), 7);
    repo.receipts[receipt.order.id] = receipt;
    await mount(tester, OrdersScreen(repository: repo, vendor: false)); await tester.pumpAndSettle();
    expect(find.widgetWithText(StudentWorkspaceHeader, 'My Orders'), findsOneWidget);
    expect(find.widgetWithText(OrderStatusBadge, 'Pending'), findsOneWidget);
    expect(find.text('Ticket #7'), findsOneWidget); expect(find.text('Confirmed total: RM 17.00'), findsOneWidget);
    expect(find.text('2 × Rice Bowl'), findsOneWidget); expect(find.text('RM 8.50 each'), findsOneWidget);
    expect(find.text('Start Preparing'), findsNothing);
    await press(tester, find.widgetWithText(OutlinedButton, 'View Details'));
    expect(find.byType(OrderDetails), findsOneWidget); expect(find.text('Order Overview'), findsOneWidget);
    await reveal(tester, find.text('Payment Summary')); expect(find.text('Confirmed (simulated)'), findsOneWidget);
  });

  testWidgets('Student Orders preserve unconfirmed recovery and cached Resume gating', (tester) async {
    final repo = orders(), request = queue.queueRequest('2'); CheckoutRequest? resumed;
    repo.requests[request.id] = request;
    await mount(tester, OrdersScreen(repository: repo, vendor: false, onResume: (r) => resumed = r));
    await tester.pumpAndSettle(); expect(find.text('Not a confirmed order or ticket.'), findsOneWidget);
    await press(tester, find.widgetWithText(TextButton, 'Resume')); expect(resumed?.id, request.id);
    repo.cached = true; repo.emit(); await tester.pumpAndSettle();
    await reveal(tester, find.text('Cached request — status may be out of date.'));
    expect(find.text('Cached request — status may be out of date.'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Resume')).onPressed, isNull);
    expect(find.textContaining('Cached orders'), findsOneWidget); expect(find.text('Ticket #1'), findsNothing);
  });

  testWidgets('Student Orders header survives loading/error; Retry recovers without status controls', (tester) async {
    final repo = orders()..loading = true;
    await mount(tester, OrdersScreen(repository: repo, vendor: false));
    expect(find.text('My Orders'), findsOneWidget); expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.loading = false; repo.emit(); await tester.pumpAndSettle(); expect(find.text('No orders yet'), findsOneWidget);
    repo.errorTarget = 'orders'; repo.streamError = StateError('offline'); repo.emit(); await tester.pumpAndSettle();
    expect(find.text('Unable to load orders. Retry'), findsOneWidget);
    repo.streamError = null; await press(tester, find.text('Unable to load orders. Retry'));
    expect(find.text('No orders yet'), findsOneWidget); expect(find.text('Mark as Ready'), findsNothing);
  });

  testWidgets('Queue emphasizes exact orders ahead and approximate ETA; explanation expands separately', (tester) async {
    final repo = orders(), receipt = receiptFor(queue.queueRequest('4'), 4);
    repo.receipts[receipt.order.id] = receipt; repo.publicProgress['alpha'] = queue.progress('alpha', 3, true);
    await mount(tester, StudentQueueScreen(repository: repo, studentUid: 'student', clock: () => receipt.order.createdAt.toDate()));
    await tester.pumpAndSettle(); expect(find.text('Orders ahead: 2'), findsOneWidget);
    expect(find.text('Approx. 45 min until Ready'), findsOneWidget);
    final metric = tester.widget<Text>(find.byKey(ValueKey('queue-ahead-${receipt.order.id}')));
    expect((metric.textSpan! as TextSpan).children!.last.style!.fontSize, 32);
    expect(tester.widget<Text>(find.byKey(ValueKey('queue-eta-${receipt.order.id}'))).style!.fontSize, 24);
    expect(find.textContaining('Uses the full preparation allowance'), findsNothing);
    await press(tester, find.text('How this estimate works'));
    expect(find.textContaining('Uses the full preparation allowance'), findsOneWidget);
    await press(tester, find.text('View Order Details')); expect(find.byType(OrderDetails), findsOneWidget);
  });

  testWidgets('Queue live Pending Preparing Ready Completed uses unchanged time and history semantics', (tester) async {
    final repo = orders(), receipt = receiptFor(queue.queueRequest('1'), 1); var order = receipt.order;
    repo.receipts[order.id] = receipt; repo.publicProgress['alpha'] = queue.progress('alpha', 1, false);
    final clock = progressed(order).preparingAt!.toDate().add(const Duration(minutes: 5));
    await mount(tester, StudentQueueScreen(repository: repo, studentUid: 'student', clock: () => clock));
    await tester.pumpAndSettle(); expect(find.text('Approx. 15 min until Ready'), findsOneWidget);
    order = progressed(order); repo.receipts[order.id] = OrderReceipt(order, receipt.items);
    repo.publicProgress['alpha'] = queue.progress('alpha', 2, true); repo.emit(); await tester.pumpAndSettle();
    expect(find.widgetWithText(OrderStatusBadge, 'Preparing'), findsOneWidget); expect(find.text('Approx. 10 min until Ready'), findsOneWidget);
    order = progressed(order); repo.receipts[order.id] = OrderReceipt(order, receipt.items); repo.emit(); await tester.pumpAndSettle();
    expect(find.text('Ready for pickup'), findsOneWidget); expect(find.textContaining('min until Ready'), findsNothing);
    order = progressed(order); repo.receipts[order.id] = OrderReceipt(order, receipt.items); repo.emit(); await tester.pumpAndSettle();
    expect(find.text('No active tickets yet'), findsOneWidget);
    await press(tester, find.widgetWithText(ChoiceChip, 'History'));
    expect(find.text('Ticket #1'), findsOneWidget); expect(find.widgetWithText(OrderStatusBadge, 'Completed'), findsOneWidget);
  });

  testWidgets('Queue missing/cache/error warnings stay outside collapsed explanations and Refresh recovers', (tester) async {
    final repo = orders(), receipt = receiptFor(queue.queueRequest('1'), 1); repo.receipts[receipt.order.id] = receipt;
    await mount(tester, StudentQueueScreen(repository: repo, studentUid: 'student')); await tester.pumpAndSettle();
    expect(find.text('Orders ahead: Unavailable'), findsOneWidget); expect(find.text('Waiting time unavailable'), findsOneWidget);
    expect(find.textContaining('No position or ETA is assumed.'), findsOneWidget);
    repo.publicProgress['alpha'] = queue.progress('alpha', 1, false); repo.progressCached = true; repo.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Cached queue —'), findsOneWidget); expect(find.textContaining('min until Ready'), findsNothing);
    repo.progressCached = false; repo.errorTarget = 'progress:alpha'; repo.streamError = StateError('offline'); repo.emit();
    await tester.pumpAndSettle(); expect(find.text('Unable to verify this stall’s queue progress.'), findsOneWidget);
    repo.streamError = null; await press(tester, find.text('Refresh Queue'));
    expect(find.text('Orders ahead: 0'), findsOneWidget);
    repo.cached = true; repo.emit(); await tester.pumpAndSettle();
    await reveal(tester, find.textContaining('Cached ticket —'), delta: -200);
    expect(find.textContaining('Cached orders —'), findsOneWidget); expect(find.text('Orders ahead: Unavailable'), findsOneWidget);
  });

  testWidgets('elapsed Preparing estimate is a visible warning and never a fabricated zero-minute ETA', (tester) async {
    final repo = orders(), receipt = receiptFor(queue.queueRequest('1'), 1), preparing = progressed(receipt.order);
    repo.receipts[preparing.id] = OrderReceipt(preparing, receipt.items); repo.publicProgress['alpha'] = queue.progress('alpha', 2, true);
    await mount(tester, StudentQueueScreen(repository: repo, studentUid: 'student',
      clock: () => preparing.preparingAt!.toDate().add(const Duration(minutes: 30)))); await tester.pumpAndSettle();
    expect(find.text('Initial estimate elapsed'), findsOneWidget); expect(find.text('Orders ahead: 0'), findsOneWidget);
    expect(find.textContaining('Ready time is currently unknown.'), findsOneWidget);
    expect(find.text('Approx. 0 min until Ready'), findsNothing);
  });

  testWidgets('Queue loading/error header and explicit Retry; independent stalls never share positions', (tester) async {
    final repo = orders()..loading = true;
    final alpha = receiptFor(queue.queueRequest('1'), 4), beta = receiptFor(queue.queueRequest('2', vendor: 'beta'), 1);
    repo.receipts[alpha.order.id] = alpha; repo.receipts[beta.order.id] = beta;
    repo.publicProgress['alpha'] = queue.progress('alpha', 3, true); repo.publicProgress['beta'] = queue.progress('beta', 1, false);
    await mount(tester, StudentQueueScreen(repository: repo, studentUid: 'student'));
    expect(find.text('My Queue'), findsOneWidget); expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.loading = false; repo.emit(); await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(ValueKey('queue-${alpha.order.id}')), matching: find.text('Orders ahead: 2')), findsOneWidget);
    final other = find.byKey(ValueKey('queue-${beta.order.id}')); await reveal(tester, other);
    expect(find.descendant(of: other, matching: find.text('Orders ahead: 0')), findsOneWidget);
    repo.errorTarget = 'orders'; repo.streamError = StateError('offline'); repo.emit(); await tester.pumpAndSettle();
    repo.streamError = null; await press(tester, find.text('Unable to load your queue. Retry'));
    expect(find.text('alpha Kitchen'), findsOneWidget);
  });

  testWidgets('Student account change removes prior Orders and Queue while replacement loads', (tester) async {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.student)); addTearDown(repo.dispose);
    populate(repo.catalogRepository);
    final first = receiptFor(queue.queueRequest('1', student: 'test-user'), 1);
    final second = receiptFor(queue.queueRequest('2', student: 'student-b', vendor: 'beta'), 2);
    repo.orderRepository.receipts[first.order.id] = first; repo.orderRepository.receipts[second.order.id] = second;
    await stage.launch(tester, repo); await press(tester, find.text('Orders')); expect(find.text('Ticket #1'), findsOneWidget);
    repo.orderRepository.loading = true;
    repo.session(const UserProfile(uid: 'student-b', fullName: 'Student B', email: 'student-b@example.com',
      phoneNumber: '0123456789', role: AccountRole.student)); await tester.pumpAndSettle();
    await tester.tap(find.text('Orders')); await tester.pump(); expect(find.text('Ticket #1'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.orderRepository.loading = false; repo.orderRepository.emit(); await tester.pumpAndSettle();
    expect(find.text('Ticket #2'), findsOneWidget); expect(find.text('Ticket #1'), findsNothing);
    await press(tester, find.text('Queue')); expect(find.text('beta Kitchen'), findsOneWidget); expect(find.text('alpha Kitchen'), findsNothing);
  });

  testWidgets('Student Profile displays only existing fields and safe pending Logout keeps one session request', (tester) async {
    final repo = _LogoutRepository()..session(stage.profile(AccountRole.student)); addTearDown(repo.dispose);
    await stage.launch(tester, repo); await press(tester, find.text('Profile'));
    expect(find.widgetWithText(StudentWorkspaceHeader, 'Profile & Settings'), findsOneWidget);
    expect(find.text('Account Information'), findsOneWidget); expect(find.text('Alex Lee'), findsOneWidget);
    expect(find.text('alex@example.com'), findsOneWidget); expect(find.text('0123456789'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget); expect(find.text('Edit Profile'), findsNothing);
    final logout = find.widgetWithText(OutlinedButton, 'Logout'); await press(tester, logout); expect(repo.logoutCalls, 1);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Logging out…')).onPressed, isNull);
    repo.pendingLogout.complete(); await tester.pumpAndSettle(); expect(find.text('Welcome Back'), findsOneWidget);
  });

  testWidgets('failed Logout leaves Student profile and account visible with actionable error', (tester) async {
    final repo = _LogoutRepository()..session(stage.profile(AccountRole.student)); addTearDown(repo.dispose);
    await stage.launch(tester, repo); await press(tester, find.text('Profile'));
    await press(tester, find.widgetWithText(OutlinedButton, 'Logout'));
    repo.pendingLogout.completeError(const AccountException('Logout could not be completed. Please retry.'));
    await tester.pumpAndSettle();
    expect(find.text('Logout could not be completed. Please retry.'), findsOneWidget);
    expect(find.text('Profile & Settings'), findsOneWidget); expect(find.text('Alex Lee'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Logout')).onPressed, isNotNull);
    expect(find.text('Welcome Back'), findsNothing);
  });

  for (final small in [false, true]) {
    testWidgets('all five Student screens scroll without overflow at ${small ? '320x640 and 1.6x text' : 'Pixel 6'}', (tester) async {
      final size = small ? const Size(320, 640) : const Size(412, 915), scale = small ? 1.6 : 1.0;
      final catalogRepo = catalog(), selection = cart(catalogRepo), orderRepo = orders();
      catalogRepo.stallItems[0] = listing('alpha', name: 'A long campus kitchen name with lunch specials');
      catalogRepo.foodItems['alpha']![0] = food('bowl', name: 'A large rice bowl with vegetables and a very long name');
      final receipt = receiptFor(queue.queueRequest('1'), 1); orderRepo.receipts[receipt.order.id] = receipt;
      orderRepo.publicProgress['alpha'] = queue.progress('alpha', 1, false);
      await mount(tester, StudentHome(repository: catalogRepo, onStall: (_) {}), size: size, scale: scale); await tester.pumpAndSettle();
      await press(tester, find.widgetWithText(ChoiceChip, 'Chinese'));
      await reveal(tester, find.widgetWithText(FilledButton, 'View Menu')); expect(tester.takeException(), isNull);
      await mount(tester, StudentStallMenu(vendorId: 'alpha', repository: catalogRepo, cart: selection, onCart: () {}), size: size, scale: scale);
      await tester.pumpAndSettle(); await reveal(tester, find.widgetWithText(OutlinedButton, 'Select Food'));
      expect(tester.takeException(), isNull);
      await mount(tester, OrdersScreen(repository: orderRepo, vendor: false), size: size, scale: scale);
      await tester.pumpAndSettle(); await reveal(tester, find.widgetWithText(OutlinedButton, 'View Details')); expect(tester.takeException(), isNull);
      await mount(tester, StudentQueueScreen(repository: orderRepo, studentUid: 'student'), size: size, scale: scale);
      await tester.pumpAndSettle(); await press(tester, find.text('How this estimate works'));
      await reveal(tester, find.text('View Order Details')); expect(tester.takeException(), isNull);
      final auth = stage.TestRepository()..session(const UserProfile(uid: 'student',
        fullName: 'A long synthetic Student name for accessible profile layout',
        email: 'long.synthetic.student.address@example.com', phoneNumber: '0123456789', role: AccountRole.student));
      addTearDown(auth.dispose);
      await mount(tester, HomeScreen(profile: auth.currentProfile!, repository: auth), size: size, scale: scale);
      await tester.pumpAndSettle(); await press(tester, find.text('Profile'));
      await reveal(tester, find.widgetWithText(OutlinedButton, 'Logout'));
      expect(find.text('Account Information'), findsOneWidget);
      expect(tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).items.length, 5);
      expect(tester.takeException(), isNull);
    });
  }
}
