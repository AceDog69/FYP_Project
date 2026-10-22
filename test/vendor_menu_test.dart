import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/vendor_menu.dart';
import 'package:my_fyp_app/models/user_profile.dart';
import 'package:my_fyp_app/screens/vendor_food_editor.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/theme/app_theme.dart';
import 'package:my_fyp_app/widgets/delete_confirmation.dart';
import 'stage_one_test.dart' as stage;

void main() {
  test('precise sen parsing has no rounding or floating point acceptance', () {
    expect(parsePriceSen('8.50'), 850); expect(parsePriceSen('0.01'), 1);
    expect(parsePriceSen('1000.00'), 100000); expect(rm(105), 'RM 1.05');
    for (final s in ['0', '-1', '1.001', '1000.01', 'NaN', '1e2', '01.20']) {
      expect(parsePriceSen(s), isNull);
    }
    expect(categoryName(' Rice   Bowls '), 'Rice Bowls');
    expect(categoryError('a/b'), isNotNull); expect(categoryError(''), isNotNull);
  });

  testWidgets('empty menu, categories, duplicate error, cached gating and four tabs', (tester) async {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.vendor, setup: true));
    addTearDown(repo.dispose);
    await stage.launch(tester, repo); await stage.tap(tester, 'Menu');
    expect(find.text('No food items yet'), findsOneWidget);
    expect(tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).items.length, 4);
    await stage.tap(tester, 'Manage Categories'); await stage.tap(tester, 'Add Category');
    await tester.enterText(find.byType(TextFormField), 'Rice'); await stage.tap(tester, 'Save');
    expect(repo.menuRepository.categoryItems.single.name, 'Rice');
    await stage.tap(tester, 'Add Category');
    await tester.enterText(find.byType(TextFormField), ' rice '); await stage.tap(tester, 'Save');
    expect(find.textContaining('already exists'), findsOneWidget);
    await stage.tap(tester, 'Cancel');
    final del = find.widgetWithText(TextButton, 'Delete Category');
    expect(tester.widget<TextButton>(del).onPressed, isNull);
    await tester.pageBack(); await tester.pumpAndSettle();
    repo.menuRepository.cached = true; repo.menuRepository.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Cached menu'), findsOneWidget);
    await stage.tap(tester, 'Profile'); await stage.tap(tester, 'Logout');
    expect(find.text('Welcome Back'), findsOneWidget);
  });

  testWidgets('Add/Edit form validates and preserves failed drafts; reuses picker', (tester) async {
    final repo = stage.TestRepository(); addTearDown(repo.dispose);
    repo.menuRepository.categoryItems.addAll([const MenuCategory('rice','Rice',1), const MenuCategory('drinks','Drinks',1)]);
    await tester.binding.setSurfaceSize(const Size(412,915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: smartCanteenTheme(), home: VendorFoodEditor(
      repository: repo.menuRepository, categories: repo.menuRepository.categoryItems, stallName: 'Kitchen')));
    await stage.tap(tester, 'Save Food'); expect(repo.menuRepository.saves, 0);
    await stage.fill(tester, 'Food Name', 'Rice Bowl');
    await tester.enterText(find.widgetWithText(TextFormField, 'Description'), 'Fresh rice');
    await stage.fill(tester, 'Price (RM)', '8.50');
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>)); await tester.pumpAndSettle();
    await stage.tap(tester, 'Rice');
    await stage.tap(tester, 'Choose Picture');
    final target = find.byKey(const ValueKey('picture-western_food'));
    await tester.scrollUntilVisible(target, 200, scrollable: find.descendant(
      of: find.byKey(const ValueKey('picture-library')), matching: find.byType(Scrollable)));
    await tester.tap(target); await stage.tap(tester, 'Confirm');
    expect(repo.menuRepository.saves, 0);
    repo.menuRepository.error = const AccountException('Retry save.');
    await stage.tap(tester, 'Save Food');
    expect(find.text('Retry save.'), findsOneWidget); expect(find.text('Rice Bowl'), findsOneWidget);
  });

  testWidgets('Delete confirmation Cancel returns false and never writes', (tester) async {
    bool? answer;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () async { answer = await confirmDeletion(context, 'Rice'); }, child: const Text('Ask'))))));
    await stage.tap(tester, 'Ask'); await stage.tap(tester, 'Cancel'); expect(answer, false);
  });

  testWidgets('food delete Cancel writes nothing; pending, failure and retry keep server semantics', (tester) async {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.vendor, setup: true));
    addTearDown(repo.dispose);
    final menu = repo.menuRepository..deletesEnabled = true;
    menu.categoryItems.add(const MenuCategory('rice', 'Rice', 1));
    menu.foodItems.add(MenuFood('food', FoodDraft(name: 'Rice Bowl', description: 'Fresh rice',
      priceSen: 850, categoryId: 'rice', pictureId: 'nasi_lemak', available: false), 1));
    await stage.launch(tester, repo);
    await tester.binding.setSurfaceSize(const Size(412, 915));
    await stage.tap(tester, 'Menu');
    final button = find.widgetWithText(OutlinedButton, 'Delete Food');
    await tester.ensureVisible(button); await tester.tap(button); await tester.pumpAndSettle();
    await stage.tap(tester, 'Cancel');
    expect(menu.deletes, 0); expect(menu.foodItems, hasLength(1));
    expect(find.text('Rice Bowl'), findsOneWidget);

    menu.pending = Completer<void>();
    menu.error = const AccountException('Delete failed. Please retry.');
    await tester.ensureVisible(button); await tester.tap(button); await tester.pumpAndSettle();
    final confirm = find.widgetWithText(TextButton, 'Delete Food');
    await tester.tap(confirm); await tester.pump();
    expect(menu.deletes, 1); expect(menu.foodItems, hasLength(1));
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(find.text('Food deleted.'), findsNothing);
    menu.pending!.complete(); await tester.pumpAndSettle();
    expect(find.text('Delete failed. Please retry.'), findsOneWidget);
    expect(find.text('Rice Bowl'), findsOneWidget);

    menu.pending = null; menu.error = null;
    await tester.ensureVisible(button); await tester.tap(button); await tester.pumpAndSettle();
    await stage.tap(tester, 'Delete Food');
    expect(menu.deletes, 2); expect(menu.foodItems, isEmpty);
    expect(find.text('No food items yet'), findsOneWidget);
    expect(find.text('Food deleted.'), findsOneWidget);
  });

  testWidgets('edit changes category and price; availability stays visible and Delete is gated', (tester) async {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.vendor, setup: true));
    addTearDown(repo.dispose);
    repo.menuRepository.categoryItems.addAll([const MenuCategory('rice','Rice',1), const MenuCategory('drinks','Drinks',1)]);
    repo.menuRepository.foodItems.add(MenuFood('food', FoodDraft(name:'Rice Bowl', description:'Fresh rice',
      priceSen:850, categoryId:'rice', pictureId:'nasi_lemak', available:true),1));
    await stage.launch(tester,repo); await stage.tap(tester,'Menu');
    expect(find.text('RM 8.50'),findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Delete Food')).onPressed,isNull);
    await stage.tap(tester,'Edit'); await stage.fill(tester,'Food Name','Updated Bowl');
    await stage.fill(tester,'Price (RM)','9.05');
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>)); await tester.pumpAndSettle();
    await stage.tap(tester,'Drinks'); await stage.tap(tester,'Save Food');
    expect(repo.menuRepository.foodItems.single.draft.categoryId,'drinks');
    expect(find.text('RM 9.05'),findsOneWidget);
    await tester.ensureVisible(find.byType(SwitchListTile)); await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle(); expect(find.text('Unavailable'),findsOneWidget);
    expect(find.text('Updated Bowl'),findsOneWidget);
  });

  testWidgets('menu loading and stream error have explicit states and Retry', (tester) async {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.vendor, setup:true));
    addTearDown(repo.dispose); repo.menuRepository.loading=true;
    await stage.launch(tester,repo); await tester.tap(find.text('Menu').last); await tester.pump();
    expect(find.byType(CircularProgressIndicator),findsOneWidget);
    repo.menuRepository.emit(); await tester.pumpAndSettle();
    expect(find.text('No food items yet'),findsOneWidget);
    repo.menuRepository.foodEvents.addError(StateError('offline')); await tester.pumpAndSettle();
    expect(find.text('Retry'),findsOneWidget);
    repo.menuRepository.loading=false; await stage.tap(tester,'Retry');
    expect(find.text('No food items yet'),findsOneWidget);
  });
}
