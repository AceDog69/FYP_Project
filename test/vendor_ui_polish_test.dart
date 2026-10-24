import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/confirmed_order.dart';
import 'package:my_fyp_app/models/user_profile.dart';
import 'package:my_fyp_app/models/vendor_menu.dart';
import 'package:my_fyp_app/screens/orders_screen.dart';
import 'package:my_fyp_app/screens/vendor_menu_screen.dart';
import 'package:my_fyp_app/screens/vendor_food_editor.dart';
import 'package:my_fyp_app/theme/app_theme.dart';
import 'package:my_fyp_app/widgets/stall_picture_picker.dart';
import 'package:my_fyp_app/widgets/vendor_workspace_widgets.dart';
import 'support/fake_order_repository.dart';
import 'stage_one_test.dart' as stage;

OrderReceipt polishedReceipt(String suffix, int ticket, {String status = 'Pending', bool longText = false}) {
  final request = CheckoutRequest(id: suffix.padLeft(20, '0'), studentUid: 'student', vendorUid: 'owner',
    stallName: longText ? 'Campus Kitchen with a long stall name for small-screen wrapping' : 'Campus Kitchen',
    paymentMethod: 'ewallet', items: [
      OrderItem(foodId: 'rice', name: longText ? 'Rice Bowl with vegetables and a long immutable food name' : 'Rice Bowl',
        description: 'Snapshot description', categoryId: 'meals', pictureId: 'nasi_lemak', priceSen: 850, quantity: 2, foodRevision: 1),
      const OrderItem(foodId: 'drink', name: 'Teh Ais', description: 'Snapshot drink', categoryId: 'drinks',
        pictureId: 'teh_ais', priceSen: 250, quantity: 1, foodRevision: 1),
    ]);
  final receipt = receiptFor(request, ticket), original = receipt.order;
  final revision = orderStatuses.indexOf(status), created = DateTime(2026, 10, 24, 12, 34);
  Timestamp at(int minutes) => Timestamp.fromDate(created.add(Duration(minutes: minutes)));
  final order = ConfirmedOrder(id: original.id, studentUid: original.studentUid, vendorUid: original.vendorUid,
    stallName: original.stallName, ticket: ticket, totalSen: original.totalSen, itemCount: original.itemCount,
    preparationMinutes: original.preparationMinutes, paymentMethod: original.paymentMethod, createdAt: at(0), firstItem: original.firstItem,
    status: status, statusRevision: revision, preparingAt: revision > 0 ? at(5) : null,
    readyAt: revision > 1 ? at(10) : null, completedAt: revision > 2 ? at(15) : null,
    statusUpdatedAt: revision > 0 ? at(revision * 5) : null);
  return OrderReceipt(order, receipt.items);
}

void main() {
  Future<void> mount(WidgetTester tester, Widget widget, {Size size = const Size(412, 915), bool settle = true}) async {
    await tester.binding.setSurfaceSize(size); addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: smartCanteenTheme(), home: widget));
    if (settle) { await tester.pumpAndSettle(); } else { await tester.pump(); }
  }
  Future<void> press(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder); await tester.tap(finder); await tester.pumpAndSettle();
  }
  Future<void> reveal(WidgetTester tester, Finder finder, {double delta = 240}) async {
    await tester.scrollUntilVisible(finder, delta, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }
  stage.TestRepository menuRepository() {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.vendor, setup: true)); addTearDown(repo.dispose);
    repo.menuRepository.categoryItems.add(const MenuCategory('rice', 'Rice', 1));
    repo.menuRepository.foodItems.add(MenuFood('food', FoodDraft(name: 'Rice Bowl', description: 'Fresh rice',
      categoryId: 'rice', pictureId: 'nasi_lemak', priceSen: 850, available: true), 1));
    return repo;
  }
  FakeOrderRepository ordersRepository({bool enabled = true}) {
    final repo = FakeOrderRepository(() => 'owner')..processingEnabled = enabled; addTearDown(repo.dispose);
    for (final r in [polishedReceipt('1', 1), polishedReceipt('2', 2)]) { repo.receipts[r.order.id] = r; }
    return repo;
  }

  testWidgets('Menu uses accepted full-width header, white food card and accessible existing actions', (tester) async {
    final repo = menuRepository(); await mount(tester, Scaffold(body: VendorMenuScreen(auth: repo)));
    final header = find.byType(VendorWorkspaceHeader);
    expect(tester.getTopLeft(header).dx, 0); expect(tester.getSize(header).width, 412);
    expect(find.widgetWithText(VendorWorkspaceHeader, 'Manage Menu'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Menu Items')).dx, 20);
    final card = find.byKey(const ValueKey('menu-food-food'));
    final container = tester.widget<Container>(find.descendant(of: card, matching: find.byType(Container)).first);
    expect((container.decoration! as BoxDecoration).color, Colors.white);
    expect(find.text('RM 8.50'), findsOneWidget); expect(find.text('Rice'), findsOneWidget);
    expect(tester.widget<StallPicture>(find.descendant(of: card, matching: find.byType(StallPicture))).width, 96);
    final add = find.widgetWithText(FilledButton, 'Add Food'), manage = find.widgetWithText(OutlinedButton, 'Manage Categories');
    expect(tester.getSize(manage).height, greaterThanOrEqualTo(48));
    expect(tester.widget<FilledButton>(add).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Delete Food')).onPressed, isNull);
    await press(tester, manage);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Delete Category')).onPressed, isNull);
    await tester.pageBack(); await tester.pumpAndSettle();
    await press(tester, add); expect(find.byType(VendorFoodEditor), findsOneWidget);
    expect(repo.menuRepository.saves, 0); await tester.pageBack(); await tester.pumpAndSettle();
    expect(repo.menuRepository.foodItems.single.draft.name, 'Rice Bowl'); expect(repo.menuRepository.deletes, 0);
  });

  testWidgets('Menu availability and Edit remain wired while both delete gates stay closed', (tester) async {
    final repo = menuRepository(); await mount(tester, Scaffold(body: VendorMenuScreen(auth: repo)));
    await press(tester, find.byType(Switch)); expect(repo.menuRepository.foodItems.single.draft.available, false);
    expect(find.text('Unavailable'), findsOneWidget); expect(find.text('Rice Bowl'), findsOneWidget);
    await press(tester, find.widgetWithText(OutlinedButton, 'Edit')); expect(find.byType(VendorFoodEditor), findsOneWidget);
    expect(find.text('Rice Bowl'), findsOneWidget); await tester.pageBack(); await tester.pumpAndSettle();
    expect(repo.menuRepository.foodItems.single.draft.priceSen, 850); expect(repo.menuRepository.deletes, 0);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Delete Food')).onPressed, isNull);
  });

  testWidgets('Menu header survives loading and errors; cache blocks mutations and Retry restores them', (tester) async {
    final repo = menuRepository(); repo.menuRepository.loading = true;
    await mount(tester, Scaffold(body: VendorMenuScreen(auth: repo)), settle: false);
    expect(find.byType(VendorWorkspaceHeader), findsOneWidget); expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add Food')).onPressed, isNull);
    repo.menuRepository.loading = false; repo.menuRepository.emit(); await tester.pumpAndSettle();
    repo.menuRepository.cached = true; repo.menuRepository.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Cached menu'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Edit')).onPressed, isNull);
    repo.menuRepository.foodEvents.addError(StateError('offline')); await tester.pumpAndSettle();
    expect(find.textContaining('Menu could not be loaded'), findsOneWidget); expect(find.byType(VendorWorkspaceHeader), findsOneWidget);
    repo.menuRepository.cached = false; await press(tester, find.text('Retry'));
    expect(find.text('Rice Bowl'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNotNull);
  });

  testWidgets('small Menu stacks category/Add actions and retains readable controls with scaled text', (tester) async {
    final repo = menuRepository(); await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: smartCanteenTheme(), home: MediaQuery(
      data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.3)),
      child: Scaffold(body: VendorMenuScreen(auth: repo))))); await tester.pumpAndSettle();
    final manage = find.widgetWithText(OutlinedButton, 'Manage Categories'), add = find.widgetWithText(FilledButton, 'Add Food');
    expect(tester.getTopLeft(add).dy, greaterThan(tester.getTopLeft(manage).dy));
    await reveal(tester, find.text('Delete Food'));
    expect(tester.getSize(find.widgetWithText(OutlinedButton, 'Edit')).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Vendor status filters scroll to History on a small screen and keep actual status labels', (tester) async {
    final repo = ordersRepository(); final completed = polishedReceipt('2', 2, status: 'Completed'); repo.receipts[completed.order.id] = completed;
    await mount(tester, Scaffold(body: OrdersScreen(repository: repo, vendor: true)), size: const Size(320, 640));
    expect(find.widgetWithText(VendorWorkspaceHeader, 'Vendor Orders'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(5));
    await tester.drag(find.byKey(const ValueKey('order-status-filters')), const Offset(-600, 0)); await tester.pumpAndSettle();
    await press(tester, find.widgetWithText(ChoiceChip, 'History'));
    expect(find.text('Ticket #1'), findsNothing); expect(find.text('Ticket #2'), findsOneWidget);
    expect(find.widgetWithText(OrderStatusBadge, 'Completed'), findsOneWidget);
    expect(find.text('Start Preparing'), findsNothing); expect(tester.takeException(), isNull);
  });

  testWidgets('polished Vendor cards preserve exact FCFS button eligibility and confirmed item totals', (tester) async {
    final repo = ordersRepository(); await mount(tester, Scaffold(body: OrdersScreen(repository: repo, vendor: true)));
    final first = polishedReceipt('1', 1).order, second = polishedReceipt('2', 2).order;
    Finder action(String id) => find.byKey(ValueKey('advance-$id'));
    expect(tester.widget<FilledButton>(action(first.id)).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(action(second.id)).onPressed, isNull);
    expect(find.text('2 × Rice Bowl'), findsWidgets); expect(find.text('Confirmed total: RM 19.50'), findsWidgets);
    await press(tester, action(first.id)); expect(repo.receipts[first.id]!.order.status, 'Preparing');
    expect(tester.widget<FilledButton>(action(second.id)).onPressed, isNull);
    await press(tester, action(first.id)); expect(repo.receipts[first.id]!.order.status, 'Ready');
    expect(tester.widget<FilledButton>(action(second.id)).onPressed, isNotNull); expect(repo.advanceCalls, 2);
  });

  testWidgets('Vendor Orders loading, cached and error/Retry presentation never enables unsafe actions', (tester) async {
    final repo = ordersRepository()..loading = true;
    await mount(tester, Scaffold(body: OrdersScreen(repository: repo, vendor: true)), settle: false);
    expect(find.byType(VendorWorkspaceHeader), findsOneWidget); expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.loading = false; repo.emit(); await tester.pumpAndSettle();
    repo.cached = true; repo.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Cached orders'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(ValueKey('advance-${polishedReceipt('1', 1).order.id}'))).onPressed, isNull);
    repo.cached = false; repo.errorTarget = 'orders'; repo.streamError = StateError('offline'); repo.emit(); await tester.pumpAndSettle();
    expect(find.byType(VendorWorkspaceHeader), findsOneWidget); expect(find.text('Unable to load orders. Retry'), findsOneWidget);
    repo.errorTarget = null; repo.streamError = null; await press(tester, find.text('Unable to load orders. Retry'));
    expect(find.text('Ticket #1'), findsOneWidget);
  });

  for (final vendor in [false, true]) {
    testWidgets('${vendor ? 'Vendor' : 'Student'} shared Details shows authoritative sections, money and timestamps', (tester) async {
      final repo = FakeOrderRepository(() => vendor ? 'owner' : 'student'); addTearDown(repo.dispose);
      final receipt = polishedReceipt('1', 1, status: 'Ready'); repo.receipts[receipt.order.id] = receipt;
      await mount(tester, OrderDetails(order: receipt.order, repository: repo, vendor: vendor));
      expect(find.text('Order Overview'), findsOneWidget); expect(find.widgetWithText(OrderStatusBadge, 'Ready'), findsOneWidget);
      expect(find.text('Ticket #1'), findsOneWidget); expect(find.text('2026-10-24'), findsOneWidget); expect(find.text('12:34'), findsOneWidget);
      await reveal(tester, find.text('Payment Summary'));
      expect(find.text('Ordered Items'), findsOneWidget); expect(find.text('2 × Rice Bowl'), findsOneWidget); expect(find.text('1 × Teh Ais'), findsOneWidget);
      expect(find.text('Confirmed total: RM 19.50'), findsOneWidget); expect(find.text('Confirmed (simulated)'), findsOneWidget);
      expect(find.textContaining('simulated, no money charged'), findsOneWidget);
      expect(find.text('Start Preparing'), findsNothing); expect(find.text('Mark as Ready'), findsNothing);
      expect(find.text('Mark Completed'), findsNothing); expect(repo.advanceCalls, 0);
      expect(find.textContaining('ETA are not available yet'), findsNothing); expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shared Details updates status live and preserves cached/item-error Retry warnings', (tester) async {
    final repo = FakeOrderRepository(() => 'student'); addTearDown(repo.dispose);
    var receipt = polishedReceipt('1', 1); repo.receipts[receipt.order.id] = receipt;
    await mount(tester, OrderDetails(order: receipt.order, repository: repo));
    receipt = polishedReceipt('1', 1, status: 'Preparing'); repo.receipts[receipt.order.id] = receipt; repo.emit(); await tester.pumpAndSettle();
    expect(find.widgetWithText(OrderStatusBadge, 'Preparing'), findsOneWidget);
    repo.cached = true; repo.emit(); await tester.pumpAndSettle(); expect(find.textContaining('Cached order —'), findsOneWidget);
    await reveal(tester, find.text('Ordered Items'));
    repo.errorTarget = 'items'; repo.streamError = StateError('offline'); repo.emit(); await tester.pumpAndSettle();
    expect(find.text('Unable to load items. Retry'), findsOneWidget);
    repo.errorTarget = null; repo.streamError = null; await press(tester, find.text('Unable to load items. Retry'));
    expect(find.text('2 × Rice Bowl'), findsOneWidget); expect(find.text('Cached item snapshots'), findsOneWidget);
  });

  testWidgets('shared Details loading/order errors do not retain old receipt data', (tester) async {
    final repo = FakeOrderRepository(() => 'student')..loading = true; addTearDown(repo.dispose);
    final receipt = polishedReceipt('1', 1); repo.receipts[receipt.order.id] = receipt;
    await mount(tester, OrderDetails(order: receipt.order, repository: repo), settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget); expect(find.text('Ticket #1'), findsNothing);
    repo.loading = false; repo.emit(); await tester.pumpAndSettle();
    repo.errorTarget = 'orders'; repo.streamError = StateError('offline'); repo.emit(); await tester.pumpAndSettle();
    expect(find.text('Unable to load order. Retry'), findsOneWidget); expect(find.text('Ticket #1'), findsNothing);
    repo.streamError = null; repo.errorTarget = null; await press(tester, find.text('Unable to load order. Retry'));
    expect(find.text('Ticket #1'), findsOneWidget);
  });

  testWidgets('long shared Details scrolls through all sections on 320px Android with larger text', (tester) async {
    final repo = FakeOrderRepository(() => 'student'); addTearDown(repo.dispose);
    final receipt = polishedReceipt('1', 1, status: 'Completed', longText: true); repo.receipts[receipt.order.id] = receipt;
    await tester.binding.setSurfaceSize(const Size(320, 640)); addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: smartCanteenTheme(), home: MediaQuery(
      data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.3)),
      child: OrderDetails(order: receipt.order, repository: repo)))); await tester.pumpAndSettle();
    await reveal(tester, find.text('Payment Summary'));
    expect(find.text('Confirmed total: RM 19.50'), findsOneWidget); expect(tester.takeException(), isNull);
  });
}
