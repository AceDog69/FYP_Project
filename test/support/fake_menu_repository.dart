import 'dart:async';
import 'package:my_fyp_app/models/vendor_menu.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/services/vendor_menu_repository.dart';

class FakeMenuRepository extends VendorMenuRepository {
  final categoryItems = <MenuCategory>[];
  final foodItems = <MenuFood>[];
  final categoryEvents = StreamController<MenuData<MenuCategory>>.broadcast();
  final foodEvents = StreamController<MenuData<MenuFood>>.broadcast();
  bool cached = false;
  bool loading = false;
  Object? error;
  Completer<void>? pending;
  int saves = 0;
  @override
  Stream<MenuData<MenuCategory>> categories() async* {
    if (!loading) yield MenuData(List.of(categoryItems), cached: cached);
    yield* categoryEvents.stream;
  }
  @override
  Stream<MenuData<MenuFood>> foods() async* {
    if (!loading) yield MenuData(List.of(foodItems), cached: cached);
    yield* foodEvents.stream;
  }
  void emit() {
    categoryEvents.add(MenuData(List.of(categoryItems), cached: cached));
    foodEvents.add(MenuData(List.of(foodItems), cached: cached));
  }
  @override
  Future<void> saveCategory(String name, {MenuCategory? original}) async {
    final n = categoryName(name);
    if (categoryItems.any((c) => c.id != original?.id && c.name.toLowerCase() == n.toLowerCase())) {
      throw const AccountException('A category with this name already exists.');
    }
    if (original != null) categoryItems.removeWhere((c) => c.id == original.id);
    categoryItems.add(MenuCategory(original?.id ?? 'cat-${categoryItems.length}', n, (original?.revision ?? 0) + 1));
    emit();
  }
  @override
  Future<void> saveFood(FoodDraft draft, {MenuFood? original}) async {
    saves++;
    if (pending != null) await pending!.future;
    if (error != null) throw error!;
    if (original != null) foodItems.removeWhere((f) => f.id == original.id);
    foodItems.add(MenuFood(original?.id ?? 'food-${foodItems.length}', draft, (original?.revision ?? 0) + 1));
    emit();
  }
  @override
  Future<void> setAvailable(MenuFood f, bool available) => saveFood(FoodDraft(
    name: f.draft.name, description: f.draft.description, priceSen: f.draft.priceSen,
    categoryId: f.draft.categoryId, pictureId: f.draft.pictureId, available: available), original: f);
  @override
  Future<void> deleteFood(MenuFood food) async => throw const AccountException('Deletion gated.');
  void dispose() { categoryEvents.close(); foodEvents.close(); }
}
