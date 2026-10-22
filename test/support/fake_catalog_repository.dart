import 'dart:async';
import 'package:my_fyp_app/models/catalog.dart';
import 'package:my_fyp_app/models/vendor_menu.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/services/catalog_repository.dart';

class FakeCatalogRepository extends CatalogRepository {
  final stallItems = <CatalogStall>[];
  final categoryItems = <String, List<MenuCategory>>{};
  final foodItems = <String, List<MenuFood>>{};
  final events = StreamController<int>.broadcast();
  bool cached = false, loading = false;
  Object? error;
  String? errorTarget;
  Completer<void>? pending;
  int reads = 0, _event = 0;
    Stream<MenuData<T>> _watch<T>(
    String target,
    List<T> Function() items,
  ) async* {
    if (!loading) {
      yield MenuData(items(), cached: cached);
    }

    await for (final _ in events.stream) {
      if (error != null && errorTarget == target) {
        yield* Stream<MenuData<T>>.error(error!);
      } else {
        yield MenuData(items(), cached: cached);
      }
    }
  }
  void emit() => events.add(_event++);
@override
Stream<MenuData<CatalogStall>> stalls() =>
    _watch('home', () => List.of(stallItems));

@override
Stream<MenuData<CatalogStall>> stall(String vendorUid) =>
    _watch(
      'stall',
      () => stallItems.where((s) => s.id == vendorUid).toList(),
    );

@override
Stream<MenuData<MenuCategory>> categories(String vendorUid) =>
    _watch(
      'categories',
      () => List.of(categoryItems[vendorUid] ?? []),
    );

@override
Stream<MenuData<MenuFood>> foods(String vendorUid) =>
    _watch(
      'foods',
      () => (foodItems[vendorUid] ?? [])
          .where((f) => f.draft.available)
          .toList(),
    );
  @override
  Future<CatalogSelection> selection(String vendorUid, String foodId) async {
    reads++;
    if (pending != null) await pending!.future;
    if (cached || error != null) throw const AccountException('Connect and retry.');
    final listing = stallItems.where((s) => s.id == vendorUid).firstOrNull;
    final food = foodItems[vendorUid]?.where((f) => f.id == foodId && f.draft.available).firstOrNull;
    if (listing == null || food == null) throw const AccountException('Food is no longer available.');
    final category = categoryItems[vendorUid]?.where((c) => c.id == food.draft.categoryId).firstOrNull;
    if (category == null) throw const AccountException('Category is no longer available.');
    return CatalogSelection(listing, food, category);
  }
  void dispose() { events.close(); }
}
