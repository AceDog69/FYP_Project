import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/catalog.dart';
import 'package:my_fyp_app/models/vendor_menu.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/services/student_cart.dart';
import 'support/catalog_fixtures.dart';
import 'support/fake_catalog_repository.dart';

Future<void> settleStreams() => Future<void>.delayed(Duration.zero);
void main() {
  late FakeCatalogRepository repo;
  late StudentCart cart;
  setUp(() { repo = FakeCatalogRepository(); populate(repo); cart = StudentCart('student-a', repo); });
  tearDown(() { if (cart.active) cart.dispose(); repo.dispose(); });
  CatalogSelection selection(String vendor, String id, {int price = 850}) =>
    CatalogSelection(repo.stallItems.firstWhere((s) => s.id == vendor), food(id, price: price),
      const MenuCategory('rice', 'Rice', 1));

  test('integer sen totals, quantity limits and four distinct products are enforced', () async {
    for (var i = 0; i < 4; i++) { cart.add(selection('alpha', 'f$i', price: 105), 1); }
    expect(cart.totalSen, 420); expect(cart.lines.length, 4);
    expect(() => cart.add(selection('alpha', 'fifth'), 1), throwsA(isA<AccountException>()));
    cart.add(selection('alpha', 'f0', price: 105), 19);
    expect(cart.lines.first.quantity, 20); expect(cart.totalSen, 2415);
    expect(() => cart.add(selection('alpha', 'f0'), 1), throwsA(isA<AccountException>()));
    expect(() => cart.quantity('f0', 21), throwsA(isA<AccountException>()));
    expect(() => cart.quantity('f0', 0), throwsA(isA<AccountException>()));
    cart.quantity('f0', 1); expect(cart.totalSen, 420);
    cart.remove('f0'); expect(cart.lines.length, 3);
    cart.clear(); expect(cart.totalSen, 0); expect(cart.vendorId, isNull);
  });

  test('single vendor requires explicit replacement and validates before discarding old cart', () {
    cart.add(selection('alpha', 'bowl'), 2);
    expect(() => cart.add(selection('beta', 'bowl'), 1), throwsA(isA<AccountException>()));
    expect(cart.vendorId, 'alpha'); expect(cart.itemCount, 2);
    expect(() => cart.add(selection('beta', 'bowl'), 21, replaceStall: true), throwsA(isA<AccountException>()));
    expect(cart.vendorId, 'alpha'); expect(cart.itemCount, 2);
    cart.add(selection('beta', 'bowl'), 1, replaceStall: true);
    expect(cart.vendorId, 'beta'); expect(cart.itemCount, 1);
    expect(() => cart.add(selection('closed', 'bowl'), 1, replaceStall: true), throwsA(isA<AccountException>()));
    expect(cart.vendorId, 'beta');
  });

  test('price/name/category changes retain old display totals until explicit server review', () async {
    cart.add(await repo.selection('alpha', 'bowl'), 2); await settleStreams();
    expect(cart.confirmed, true); expect(cart.issue(cart.lines.single), isNull);
    repo.foodItems['alpha']![0] = food('bowl', name: 'New Bowl', price: 905, revision: 2, category: 'drinks');
    repo.emit(); await settleStreams();
    expect(cart.issue(cart.lines.single), contains('changed')); expect(cart.totalSen, 1700);
    expect(() => cart.quantity('bowl', 3), throwsA(isA<AccountException>()));
    await cart.review('bowl', 2);
    expect(cart.totalSen, 1810); expect(cart.lines.single.food.draft.name, 'New Bowl');
    expect(cart.lines.single.food.draft.categoryId, 'drinks');
    expect(cart.issue(cart.lines.single), isNull);
    cart.quantity('bowl', 3); expect(cart.totalSen, 2715);
  });

  test('unavailable food, closed stalls, cached and error states do not promise valid selections', () async {
    cart.add(await repo.selection('alpha', 'bowl'), 1); await settleStreams();
    repo.foodItems['alpha']![0] = food('bowl', available: false, revision: 2);
    repo.emit(); await settleStreams();
    expect(cart.issue(cart.lines.single), contains('No longer available'));
    expect(() => cart.quantity('bowl', 2), throwsA(isA<AccountException>()));
    repo.stallItems[0] = listing('alpha', open: false); repo.emit(); await settleStreams();
    expect(cart.warning, contains('Closed'));
    repo.cached = true; repo.emit(); await settleStreams();
    expect(cart.confirmed, false); expect(cart.warning, contains('current server'));
    repo.cached = false; repo.error = StateError('offline'); repo.emit(); await settleStreams();
    expect(cart.confirmed, false);
    repo.error = null; cart.refresh(); await settleStreams(); expect(cart.confirmed, true);
    cart.remove('bowl'); expect(cart.lines, isEmpty);
  });

  test('stale review fails and a disposed session cannot mutate a new Student cart', () async {
    cart.add(await repo.selection('alpha', 'bowl'), 1); await settleStreams();
    repo.foodItems['alpha']![0] = food('bowl', revision: 3);
    await expectLater(cart.review('bowl', 2), throwsA(isA<AccountException>()));
    cart.dispose(); expect(cart.lines, isEmpty); expect(cart.active, false);
    expect(() => cart.add(selection('beta', 'bowl'), 1), throwsA(isA<AccountException>()));
    final second = StudentCart('student-b', repo); addTearDown(second.dispose);
    expect(second.ownerUid, 'student-b'); expect(second.lines, isEmpty);
  });
}
