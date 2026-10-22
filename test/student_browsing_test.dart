import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/main.dart';
import 'package:my_fyp_app/models/user_profile.dart';
import 'support/catalog_fixtures.dart';
import 'stage_one_test.dart' as stage;

void main() {
  stage.TestRepository repository() {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.student));
    populate(repo.catalogRepository); return repo;
  }
  Future<void> openBowl(WidgetTester tester, String stall) async {
    await stage.tap(tester, stall); await stage.tap(tester, 'Select Food');
  }

  testWidgets('Home searches only stall names; categories, closed stalls and food details', (tester) async {
    final repo = repository(); addTearDown(repo.dispose); await stage.launch(tester, repo);
    await tester.binding.setSurfaceSize(const Size(412, 915));
    expect(find.text('Alpha Kitchen'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Search stall name'), 'aLpHa');
    await tester.pumpAndSettle(); expect(find.text('Alpha Kitchen'), findsOneWidget);
    expect(find.text('Beta Kitchen'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Rice Bowl'); await tester.pumpAndSettle();
    expect(find.text('No matching stalls'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Chinese'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Chinese')); await tester.pumpAndSettle();
    await stage.tap(tester, 'Closed Kitchen');
    expect(find.text('Closed'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Select Food')).onPressed, isNull);
    expect(find.text('Hidden Food'), findsNothing);
    await tester.pageBack(); await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'All'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'All')); await tester.pumpAndSettle();
    await stage.tap(tester, 'Alpha Kitchen');
    expect(find.text('Fresh rice and vegetables'), findsOneWidget); expect(find.text('RM 8.50'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Drinks')); await tester.pumpAndSettle();
    expect(find.text('No available food items'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Rice')); await tester.pumpAndSettle();
    expect(find.text('Rice Bowl'), findsOneWidget);
  });

  testWidgets('selection quantity, Cart navigation, integer totals and Clear Cancel/Confirm', (tester) async {
    final repo = repository(); addTearDown(repo.dispose); await stage.launch(tester, repo);
    await openBowl(tester, 'Alpha Kitchen');
    await tester.tap(find.byTooltip('Increase quantity')); await tester.pumpAndSettle();
    expect(find.text('Subtotal: RM 17.00'), findsOneWidget);
    await stage.tap(tester, 'Add to Cart'); await stage.tap(tester, 'Cart (2)');
    expect(find.text('Total: RM 17.00'), findsOneWidget);
    expect(tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).items.length, 5);
    await tester.tap(find.byTooltip('Increase bowl')); await tester.pumpAndSettle();
    expect(find.text('Total: RM 25.50'), findsOneWidget);
    await tester.tap(find.byTooltip('Decrease bowl')); await tester.pumpAndSettle();
    await stage.tap(tester, 'Orders'); expect(find.text('Coming soon'), findsOneWidget);
    await stage.tap(tester, 'Cart'); expect(find.text('Total: RM 17.00'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Checkout — available in Stage 2C')).onPressed, isNull);
    await stage.tap(tester, 'Clear Cart'); await stage.tap(tester, 'Cancel');
    expect(find.text('Rice Bowl'), findsOneWidget);
    await stage.tap(tester, 'Clear Cart'); await stage.tap(tester, 'Clear Cart');
    expect(find.text('Your cart is empty'), findsOneWidget);
    await stage.tap(tester, 'Browse Stalls'); expect(find.text('Welcome, Student'), findsOneWidget);
  });

  testWidgets('switching stalls Cancel preserves cart; Confirm replaces it; Remove is confirmed', (tester) async {
    final repo = repository(); addTearDown(repo.dispose); await stage.launch(tester, repo);
    await openBowl(tester, 'Alpha Kitchen'); await stage.tap(tester, 'Add to Cart');
    await stage.tap(tester, 'Cart (1)'); await stage.tap(tester, 'Continue Browsing');
    await openBowl(tester, 'Beta Kitchen'); await stage.tap(tester, 'Add to Cart');
    expect(find.text('Switch stalls?'), findsOneWidget);
    await stage.tap(tester, 'Cancel'); expect(find.text('Food selection'), findsOneWidget);
    await stage.tap(tester, 'Add to Cart'); await stage.tap(tester, 'Switch Stall');
    await stage.tap(tester, 'Cart (1)'); expect(find.text('Beta Kitchen'), findsOneWidget);
    expect(find.text('Alpha Kitchen'), findsNothing);
    await stage.tap(tester, 'Remove'); await stage.tap(tester, 'Cancel');
    expect(find.text('Rice Bowl'), findsOneWidget);
    await stage.tap(tester, 'Remove'); await stage.tap(tester, 'Remove');
    expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets('live loading/cache/errors and retry; unavailable foods disappear', (tester) async {
    final repo = repository(); addTearDown(repo.dispose); repo.catalogRepository.loading = true;
    // A pending stream has an intentional spinner, so do not pumpAndSettle.
    await tester.pumpWidget(SmartCanteenApp(repository: repo));
    await tester.pump(); await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.catalogRepository.loading = false; repo.catalogRepository.emit(); await tester.pumpAndSettle();
    repo.catalogRepository.cached = true; repo.catalogRepository.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Cached stalls'), findsOneWidget);
    await stage.tap(tester, 'Alpha Kitchen');
    expect(find.textContaining('Cached menu'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Select Food')).onPressed, isNull);
    repo.catalogRepository.cached = false;
    repo.catalogRepository.foodItems['alpha']![0] = food('bowl', available: false, revision: 2);
    repo.catalogRepository.emit(); await tester.pumpAndSettle();
    expect(find.text('No available food items'), findsOneWidget);
    // Simulate an error only in the food stream.
    repo.catalogRepository.errorTarget = 'foods';
    repo.catalogRepository.error = StateError('offline');
    repo.catalogRepository.emit();
    await tester.pumpAndSettle();

    expect(find.text('Unable to load menu. Retry'), findsOneWidget);

    // Clear the error before retrying.
    repo.catalogRepository.error = null;
    repo.catalogRepository.errorTarget = null;

    await stage.tap(tester, 'Unable to load menu. Retry');
    expect(find.text('No available food items'), findsOneWidget);
    // Return to Student Home.
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Simulate an error only in the Home stall-list stream.
    repo.catalogRepository.errorTarget = 'home';
    repo.catalogRepository.error = StateError('offline');
    repo.catalogRepository.emit();
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);

    // Clear the error before retrying.
    repo.catalogRepository.error = null;
    repo.catalogRepository.errorTarget = null;

    await stage.tap(tester, 'Retry');
    expect(find.text('Alpha Kitchen'), findsOneWidget);
  });

  testWidgets('account changes dispose menu/dialog routes and never retain another Student cart', (tester) async {
    final repo = repository(); addTearDown(repo.dispose); await stage.launch(tester, repo);
    await openBowl(tester, 'Alpha Kitchen'); await stage.tap(tester, 'Add to Cart');
    await stage.tap(tester, 'Select Food'); expect(find.text('Food selection'), findsOneWidget);
    repo.session(const UserProfile(uid: 'student-b', fullName: 'Synthetic Student B',
      email: 'student-b@example.com', phoneNumber: '0123456789', role: AccountRole.student));
    await tester.pumpAndSettle(); expect(find.text('Food selection'), findsNothing);
    await stage.tap(tester, 'Cart'); expect(find.text('Your cart is empty'), findsOneWidget);
    await stage.tap(tester, 'Profile'); await stage.tap(tester, 'Logout');
    expect(find.text('Welcome Back'), findsOneWidget);
    repo.session(stage.profile(AccountRole.student)); await tester.pumpAndSettle();
    await stage.tap(tester, 'Cart'); expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets('Cart flags live price/name changes and applies latest details only after review', (tester) async {
    final repo = repository(); addTearDown(repo.dispose); await stage.launch(tester, repo);
    await openBowl(tester, 'Alpha Kitchen'); await stage.tap(tester, 'Add to Cart');
    await stage.tap(tester, 'Cart (1)');
    repo.catalogRepository.foodItems['alpha']![0] = food('bowl', name: 'Updated Bowl', price: 905, revision: 2);
    repo.catalogRepository.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Menu details changed'), findsOneWidget);
    expect(find.text('Total: RM 8.50'), findsOneWidget);
    await stage.tap(tester, 'Review Changes'); await stage.tap(tester, 'Cancel');
    expect(find.text('Total: RM 8.50'), findsOneWidget);
    await stage.tap(tester, 'Review Changes'); await stage.tap(tester, 'Apply Latest');
    expect(find.text('Total: RM 9.05'), findsOneWidget); expect(find.text('Updated Bowl'), findsOneWidget);
    repo.catalogRepository.cached = true; repo.catalogRepository.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Cart needs a current server menu'), findsOneWidget);
    final increaseButton = find.ancestor(
      of: find.byTooltip('Increase bowl'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(increaseButton).onPressed, isNull);
    repo.catalogRepository.cached = false;
    repo.catalogRepository.stallItems[0] = listing('alpha', open: false);
    repo.catalogRepository.emit(); await tester.pumpAndSettle();
    expect(find.textContaining('Stall is Closed'), findsOneWidget);
  });
}
