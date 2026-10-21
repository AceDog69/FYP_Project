import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/constants/predefined_pictures.dart';
import 'package:my_fyp_app/models/user_profile.dart';
import 'package:my_fyp_app/models/vendor_stall.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/widgets/stall_picture_picker.dart';
import 'stage_one_test.dart' as stage;

Future<stage.TestRepository> launch(WidgetTester tester) async {
  final repo = stage.TestRepository()
    ..session(stage.profile(AccountRole.vendor, setup: true));
  addTearDown(repo.dispose);
  await stage.launch(tester, repo);
  return repo;
}

Future<void> edit(WidgetTester tester) async {
  await stage.tap(tester, 'Profile');
  await stage.tap(tester, 'Edit');
}

Future<void> selectLastPicture(WidgetTester tester) async {
  await stage.tap(tester, 'Choose Picture');
  final grid = find.descendant(of: find.byKey(const ValueKey('picture-library')),
    matching: find.byType(Scrollable));
  final last = find.byKey(const ValueKey('picture-western_food'));
  await tester.scrollUntilVisible(last, 200, scrollable: grid);
  await tester.tap(last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('23 real pictures are bundled with exact names and category defaults', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(predefinedPictures.length, 23);
    expect(predefinedPictures['japanese_1'], 'Japanese 1.png');
    for (final id in predefinedPictures.keys) {
      expect(manifest.listAssets(), contains(pictureAsset(id)));
      expect((await rootBundle.load(pictureAsset(id))).lengthInBytes, greaterThan(0));
    }
    const defaults = {'Malay': 'nasi_lemak', 'Western': 'western_food',
      'Chinese': 'chinese_food_1', 'Japanese': 'bento', 'Korean': 'bibimbap',
      'Beverage': 'drink', 'Dessert': 'dessert'};
    for (final entry in defaults.entries) {
      expect(resolvedPictureId(null, entry.key), entry.value);
    }
    expect(resolvedPictureId('missing', 'Western'), 'western_food');
    expect(resolvedPictureId('sushi', 'Malay'), 'sushi');
  });

  test('settings reject invalid input, category, minutes and image identifiers', () {
    StallSettings settings({String name = 'Kitchen', String category = 'Malay',
      int minutes = 15, String picture = 'nasi_lemak'}) => StallSettings(
        name: name, category: category, preparationMinutes: minutes, pictureId: picture);
    expect(settings(name: '  Kitchen  ').name, 'Kitchen');
    for (final action in <void Function()>[
      () => settings(name: '   '), () => settings(name: 'x' * 101),
      () => settings(category: 'Other'), () => settings(category: 'Malay '),
      () => settings(minutes: 0), () => settings(minutes: 181),
      () => settings(picture: 'https://example.com/image.png'),
    ]) { expect(action, throwsFormatException); }
  });

  testWidgets('Open/Close waits for acknowledgement and prevents repeated submission', (tester) async {
    final repo = await launch(tester);
    repo.pendingStallWrite = Completer<void>();
    await tester.ensureVisible(find.text('Open Stall'));
    await tester.tap(find.text('Open Stall'));
    await tester.pump();
    await tester.tap(find.text('Open Stall'));
    expect(repo.statusWrites, 1);
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Stall opened.'), findsNothing);
    repo.pendingStallWrite!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    await stage.tap(tester, 'Close Stall');
    expect(find.text('Closed'), findsOneWidget);
    expect(repo.statusWrites, 2);
  });

  testWidgets('failed status write preserves prior status and exposes retryable error', (tester) async {
    final repo = await launch(tester);
    repo.stallWriteError = const AccountException('Connection lost. Please retry.');
    await stage.tap(tester, 'Open Stall');
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Connection lost. Please retry.'), findsOneWidget);
    expect(find.text('Stall opened.'), findsNothing);
  });

  testWidgets('Vendor account stays read-only; Cancel in dialog and form discards drafts', (tester) async {
    final repo = await launch(tester);
    await edit(tester);
    expect(find.text('alex@example.com'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    await selectLastPicture(tester);
    await stage.tap(tester, 'Cancel');
    expect(tester.widget<StallPicture>(find.byType(StallPicture)).id, 'nasi_lemak');
    await selectLastPicture(tester);
    await stage.tap(tester, 'Confirm');
    expect(repo.savedSettings, isEmpty);
    expect(tester.widget<StallPicture>(find.byType(StallPicture)).id, 'western_food');
    await stage.fill(tester, 'Stall Name', 'Unsaved Kitchen');
    await stage.tap(tester, 'Cancel');
    await stage.tap(tester, 'Edit');
    expect(tester.widget<StallPicture>(find.byType(StallPicture)).id, 'nasi_lemak');
    expect(find.text('Unsaved Kitchen'), findsNothing);
    expect(repo.savedSettings, isEmpty);
  });

  testWidgets('valid settings and selected image persist only after successful Save', (tester) async {
    final repo = await launch(tester);
    await edit(tester);
    final dropdown = tester.widget<DropdownButton<String>>(find.descendant(
      of: find.byType(DropdownButtonFormField<String>),
      matching: find.byType(DropdownButton<String>)));
    expect(dropdown.items!.map((item) => item.value),
      ['Malay', 'Western', 'Chinese', 'Japanese', 'Korean', 'Beverage', 'Dessert']);
    await stage.fill(tester, 'Stall Name', 'Updated Kitchen');
    await stage.fill(tester, 'Initial Preparation Time (minutes)', '0');
    await stage.tap(tester, 'Save Changes');
    expect(find.text('Enter 1–180 minutes.'), findsOneWidget);
    expect(repo.settingsWrites, 0);
    await stage.fill(tester, 'Initial Preparation Time (minutes)', '20');
    await selectLastPicture(tester);
    await stage.tap(tester, 'Confirm');
    repo.stallWriteError = const AccountException('Unable to save settings.');
    await stage.tap(tester, 'Save Changes');
    expect(find.text('Unable to save settings.'), findsOneWidget);
    expect(repo.savedSettings, isEmpty);
    repo.stallWriteError = null;
    repo.pendingStallWrite = Completer<void>();
    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    repo.pendingStallWrite!.complete();
    await tester.pumpAndSettle();
    expect(repo.savedSettings.single.pictureId, 'western_food');
    expect(repo.savedSettings.single.name, 'Updated Kitchen');
    expect(repo.savedSettings.single.preparationMinutes, 20);
    await stage.tap(tester, 'Edit');
    expect(tester.widget<StallPicture>(find.byType(StallPicture)).id, 'western_food');
  });

  testWidgets('picker scrolls through full library at Pixel-sized layout and logout works', (tester) async {
    await launch(tester);
    await tester.binding.setSurfaceSize(const Size(412, 915));
    await tester.pumpAndSettle();
    await edit(tester);
    await selectLastPicture(tester);
    expect(find.byKey(const ValueKey('picture-western_food')).hitTestable(), findsOneWidget);
    await stage.tap(tester, 'Cancel');
    await stage.tap(tester, 'Cancel');
    await stage.tap(tester, 'Logout');
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Vendor can log out even when stall loading fails', (tester) async {
    final repo = await launch(tester);
    repo.dashboardError = const AccountException('Stall not available.');
    await stage.tap(tester, 'Profile');
    expect(find.text('Account Information'), findsOneWidget);
    await stage.tap(tester, 'Logout');
    expect(find.text('Welcome Back'), findsOneWidget);
  });
}
