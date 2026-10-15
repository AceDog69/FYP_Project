import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/user_profile.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'stage_one_test.dart' as stage;

class StallRepository extends stage.TestRepository {
  final submissions = <({String name, String category, int minutes})>[];
  Completer<void>? pendingSetup;

  @override
  Future<void> setupStall(String name, String category, int minutes) async {
    submissions.add((name: name, category: category, minutes: minutes));
    if (pendingSetup != null) await pendingSetup!.future;
    await super.setupStall(name, category, minutes);
  }
}

final dropdown = find.byType(DropdownButtonFormField<String>);
String? selectedCategory(WidgetTester tester) =>
    tester.state<FormFieldState<String>>(dropdown).value;

Future<StallRepository> launchSetup(WidgetTester tester) async {
  final repository = StallRepository()
    ..session(stage.profile(AccountRole.vendor));
  addTearDown(repository.dispose);
  await stage.launch(tester, repository);
  return repository;
}

void main() {
  testWidgets(
    'category dropdown starts empty with exactly the approved options',
    (tester) async {
      await launchSetup(tester);
      const expected = [
        'Malay',
        'Western',
        'Chinese',
        'Japanese',
        'Korean',
        'Beverage',
        'Dessert',
      ];
      expect(find.text('Stall Category'), findsOneWidget);
      expect(find.text('Food Category'), findsNothing);
      expect(find.text('Select stall category'), findsOneWidget);
      expect(selectedCategory(tester), isNull);
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.descendant(
                of: dropdown,
                matching: find.byType(DropdownButton<String>),
              ),
            )
            .items!
            .map((item) => item.value),
        expected,
      );
      // Name and preparation time remain text fields; category has no text entry.
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(
        tester
            .widget<TextFormField>(
              stage.field('Initial Preparation Time (minutes)'),
            )
            .controller!
            .text,
        '15',
      );
      await stage.openStallCategory(tester);
      for (final value in expected) {
        expect(find.text(value).last.hitTestable(), findsOneWidget);
      }
      await stage.tap(tester, 'Western');
      expect(selectedCategory(tester), 'Western');
    },
  );

  testWidgets(
    'category selection is required and changing it replaces the value',
    (tester) async {
      final repository = await launchSetup(tester);
      await stage.fill(tester, 'Stall Name', 'Campus Kitchen');
      await stage.tap(tester, 'Complete Stall Setup');
      expect(find.text('Please select a stall category.'), findsOneWidget);
      expect(repository.submissions, isEmpty);
      await stage.openStallCategory(tester);
      await stage.tap(tester, 'Malay');
      expect(find.text('Please select a stall category.'), findsNothing);
      expect(selectedCategory(tester), 'Malay');
      await stage.openStallCategory(tester);
      await stage.tap(tester, 'Japanese');
      expect(selectedCategory(tester), 'Japanese');
      expect(find.text('Malay'), findsNothing);
      expect(find.text('Japanese'), findsOneWidget);
    },
  );

  testWidgets(
    'selection survives rebuilds and success still reaches dashboard/logout',
    (tester) async {
      final repository = await launchSetup(tester);
      await stage.fill(tester, 'Stall Name', 'Campus Kitchen');
      await stage.openStallCategory(tester);
      await stage.tap(tester, 'Beverage');
      repository.notifyListeners();
      await tester.pumpAndSettle();
      expect(selectedCategory(tester), 'Beverage');
      await stage.tap(tester, 'Complete Stall Setup');
      expect(repository.submissions.single, (
        name: 'Campus Kitchen',
        category: 'Beverage',
        minutes: 15,
      ));
      expect(repository.currentProfile!.stallSetupComplete, isTrue);
      expect(find.text('Welcome, Vendor'), findsOneWidget);
      await stage.tap(tester, 'Profile');
      await stage.tap(tester, 'Logout');
      expect(find.text('Welcome Back'), findsOneWidget);
    },
  );

  testWidgets(
    'pending submission disables category and failed setup retains selection',
    (tester) async {
      final repository = await launchSetup(tester);
      repository.pendingSetup = Completer<void>();
      repository.stallError = const AccountException('Could not save stall.');
      await stage.fill(tester, 'Stall Name', 'Campus Kitchen');
      await stage.fill(tester, 'Initial Preparation Time (minutes)', '23');
      await stage.openStallCategory(tester);
      await stage.tap(tester, 'Korean');
      await tester.tap(find.text('Complete Stall Setup'));
      await tester.pump();
      expect(
        tester.widget<DropdownButtonFormField<String>>(dropdown).onChanged,
        isNull,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(selectedCategory(tester), 'Korean');
      expect(repository.submissions.single, (
        name: 'Campus Kitchen',
        category: 'Korean',
        minutes: 23,
      ));
      repository.pendingSetup!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Could not save stall.'), findsOneWidget);
      expect(selectedCategory(tester), 'Korean');
      expect(
        tester.widget<DropdownButtonFormField<String>>(dropdown).onChanged,
        isNotNull,
      );
      expect(find.text('Welcome, Vendor'), findsNothing);
    },
  );
}
