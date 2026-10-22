import 'package:my_fyp_app/models/catalog.dart';
import 'package:my_fyp_app/models/vendor_menu.dart';
import 'package:my_fyp_app/models/vendor_stall.dart';
import 'fake_catalog_repository.dart';

CatalogStall listing(String id, {String? name, bool open = true, String category = 'Malay'}) =>
  CatalogStall(id, VendorStall(name: name ?? '$id Kitchen', category: category,
    preparationMinutes: 15, isOpen: open, pictureId: 'nasi_lemak'));
MenuFood food(String id, {String name = 'Rice Bowl', int price = 850, int revision = 1,
  bool available = true, String category = 'rice'}) => MenuFood(id, FoodDraft(name: name,
    description: 'Fresh rice and vegetables', priceSen: price, categoryId: category,
    pictureId: 'nasi_lemak', available: available), revision);
void populate(FakeCatalogRepository repo) {
  repo.stallItems.addAll([listing('alpha', name: 'Alpha Kitchen'),
    listing('beta', name: 'Beta Kitchen', category: 'Western'),
    listing('closed', name: 'Closed Kitchen', open: false, category: 'Chinese')]);
  for (final id in ['alpha', 'beta', 'closed']) {
    repo.categoryItems[id] = [const MenuCategory('rice', 'Rice', 1), const MenuCategory('drinks', 'Drinks', 1)];
    repo.foodItems[id] = [food('bowl'), food('hidden', name: 'Hidden Food', available: false)];
  }
}
