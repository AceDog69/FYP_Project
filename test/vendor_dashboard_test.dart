import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_fyp_app/models/preparation_stats.dart';
import 'package:my_fyp_app/models/user_profile.dart';
import 'package:my_fyp_app/models/vendor_menu.dart';
import 'package:my_fyp_app/models/vendor_stall.dart';
import 'package:my_fyp_app/screens/vendor_dashboard.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/theme/app_theme.dart';
import 'stage_one_test.dart' as stage;

Future<stage.TestRepository> launchVendor(WidgetTester tester) async {
  final repo = stage.TestRepository();
  repo.session(stage.profile(AccountRole.vendor, setup: true));
  addTearDown(repo.dispose);
  await stage.launch(tester, repo);
  return repo;
}

void main() {
  test('existing Stage 1 fields decode without new fields or category migration', () {
    final data = <String, dynamic>{
      'ownerUid': 'vendor', 'name': 'Actual Kitchen', 'category': 'Malay Food',
      'preparationMinutes': 12, 'status': 'closed',
    };
    final stall = VendorStall.fromMap('vendor', data);
    expect(stall.name, 'Actual Kitchen');
    expect(stall.category, 'Malay Food');
    expect(stall.preparationMinutes, 12);
    expect(stall.isOpen, false);
    expect(VendorStall.fromMap('vendor', {...data, 'status': 'open'}).isOpen, true);
    for (final invalid in [
      {'ownerUid': 'other'}, {'name': ''}, {'name': '   '}, {'category': null},
      {'preparationMinutes': 0}, {'preparationMinutes': 181},
      {'preparationMinutes': 1.5}, {'status': 'unknown'},
    ]) {
      expect(() => VendorStall.fromMap('vendor', {...data, ...invalid}),
        throwsFormatException);
    }
  });

  testWidgets('dashboard displays real stall values with an enabled status action', (tester) async {
    final repo = await launchVendor(tester);
    expect(repo.stallReads, 1);
    expect(find.text('Campus Kitchen'), findsNWidgets(2));
    expect(find.text('Malay'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('15 minutes'), findsNothing);
    expect(find.text('Initial Preparation Time'), findsOneWidget);
    final overview = find.byKey(const ValueKey('preparation-time-overview'));
    expect(find.descendant(of: overview, matching: find.text('Preparation Time Overview')), findsOneWidget);
    expect(find.descendant(of: overview, matching: find.text('Initial Preparation Time')), findsOneWidget);
    expect(find.descendant(of: overview, matching: find.text('Current Estimated Preparation Time')), findsOneWidget);
    expect(find.descendant(of: overview, matching: find.text('Historical Samples Recorded')), findsOneWidget);
    expect(find.descendant(of: overview, matching: find.text('15 min')), findsNWidgets(2));
    expect(find.descendant(of: overview, matching: find.text('0 orders')), findsOneWidget);
    expect(find.descendant(of: overview, matching: find.textContaining('The estimated preparation time is calculated')), findsNothing);
    final action = find.ancestor(of: find.text('Open Stall'), matching: find.byType(OutlinedButton));
    expect(tester.widget<OutlinedButton>(action).onPressed, isNotNull);
    expect(tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).items
      .map((item) => item.label), ['Dashboard', 'Orders', 'Menu', 'Profile']);
  });

  testWidgets('Preparation overview follows live verified history and rejects cached history', (tester) async {
    final repo = await launchVendor(tester);
    final history = PreparationStats(sampleCount: 2, totalDurationMillis: 360000,
      revision: 2, lastOrderId: List.filled(20, 'A').join(),
      updatedAt: Timestamp.fromDate(DateTime.utc(2026, 1, 1)));
    repo.preparationStatsChanges.add(MenuData([history]));
    await tester.pumpAndSettle();
    expect(find.text('3 min'), findsOneWidget);
    expect(find.text('2 orders'), findsOneWidget);
    repo.preparationStatsChanges.add(MenuData([history], cached: true));
    await tester.pumpAndSettle();
    expect(find.text('Unavailable'), findsNWidgets(2));
  });

  testWidgets('live updates and cache metadata are reflected without writing', (tester) async {
    final repo = await launchVendor(tester);
    repo.stallChanges.add(const VendorStall(name: 'Updated Stall', category: 'Western',
      preparationMinutes: 20, isOpen: true, isCached: true));
    await tester.pumpAndSettle();
    expect(find.text('Updated Stall'), findsNWidgets(2));
    expect(find.text('Western'), findsOneWidget);
    expect(find.text('20 minutes'), findsNothing);
    expect(find.text('20 min (cached)'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.textContaining('may be out of date'), findsOneWidget);
    final action = find.ancestor(of: find.text('Close Stall'), matching: find.byType(OutlinedButton));
    expect(tester.widget<OutlinedButton>(action).onPressed, isNull);
    repo.stallChanges.add(repo.currentStall);
    await tester.pumpAndSettle();
    expect(find.textContaining('may be out of date'), findsNothing);
  });

  testWidgets('loading remains explicit until stall data arrives', (tester) async {
    final repo = stage.TestRepository()..stallLoading = true;
    addTearDown(repo.dispose);
    await tester.pumpWidget(MaterialApp(theme: smartCanteenTheme(),
      home: Scaffold(body: VendorDashboard(repository: repo, onOrders: () {}, onMenu: () {}))));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('My Stall'), findsNothing);
    repo.stallChanges.add(repo.currentStall);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('My Stall'), findsOneWidget);
  });

  testWidgets('missing stall can retry; errors hide previous stall data', (tester) async {
    final repo = stage.TestRepository()
      ..dashboardError = const AccountException('Your stall could not be found. Please retry.');
    repo.session(stage.profile(AccountRole.vendor, setup: true));
    addTearDown(repo.dispose);
    await stage.launch(tester, repo);
    expect(find.text('Unable to Load Stall'), findsOneWidget);
    expect(find.text('My Stall'), findsNothing);
    repo.dashboardError = null;
    await stage.tap(tester, 'Retry');
    expect(find.text('My Stall'), findsOneWidget);
    expect(repo.stallReads, 2);
    repo.stallChanges.addError(const FormatException('Malformed stall'));
    await tester.pumpAndSettle();
    expect(find.text('My Stall'), findsNothing);
    expect(find.text('Campus Kitchen'), findsNothing);
    expect(find.text('Unable to Load Stall'), findsOneWidget);
  });

  testWidgets('quick actions use existing tabs and Profile logout remains functional', (tester) async {
    await launchVendor(tester);
    await tester.ensureVisible(find.text('View Orders'));
    await tester.pumpAndSettle();
    await stage.tap(tester, 'View Orders');
    expect(find.text('No orders yet'), findsOneWidget);
    await stage.tap(tester, 'Dashboard');
    await tester.ensureVisible(find.text('Manage Menu'));
    await tester.pumpAndSettle();
    await stage.tap(tester, 'Manage Menu');
    expect(find.text('No food items yet'), findsOneWidget);
    await stage.tap(tester, 'Profile');
    expect(find.text('alex@example.com'), findsOneWidget);
    await stage.tap(tester, 'Logout');
    expect(find.text('Welcome Back'), findsOneWidget);
  });

  testWidgets('Student screens never request a vendor stall', (tester) async {
    final repo = stage.TestRepository()..session(stage.profile(AccountRole.student));
    addTearDown(repo.dispose);
    await stage.launch(tester, repo);
    expect(find.text('Welcome, Student'), findsOneWidget);
    expect(repo.stallReads, 0);
    expect(tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).items.length, 5);
  });
}
