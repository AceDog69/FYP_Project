import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/catalog.dart';
import '../models/vendor_menu.dart';
import 'auth_repository.dart';
import 'catalog_repository.dart';

class CartLine {
  const CartLine(this.food, this.quantity);
  final MenuFood food;
  final int quantity;
  int get subtotalSen => food.draft.priceSen * quantity;
}

/// Unpaid, in-memory and owned by one Home/session tree. Never writes Firestore.
class StudentCart extends ChangeNotifier {
  StudentCart(this.ownerUid, this.repository);
  final String ownerUid;
  final CatalogRepository? repository;
  static const maxProducts = 4, maxQuantity = 20;
  final _lines = <String, CartLine>{};
  String? _vendorId, _stallName;
  bool _active = true;
  int _generation = 0;
  int _version = 0;
  MenuData<CatalogStall>? _stall;
  MenuData<MenuFood>? _foods;
  MenuData<MenuCategory>? _categories;
  bool _stallError = false, _foodError = false, _categoryError = false;
  StreamSubscription<MenuData<CatalogStall>>? _stallSub;
  StreamSubscription<MenuData<MenuFood>>? _foodSub;
  StreamSubscription<MenuData<MenuCategory>>? _categorySub;

  bool get active => _active;
  int get version => _version;
  String? get vendorId => _vendorId;
  String get stallName => _stall?.items.firstOrNull?.stall.name ?? _stallName ?? '';
  List<CartLine> get lines => List.unmodifiable(_lines.values);
  int get totalSen => _lines.values.fold(0, (sum, l) => sum + l.subtotalSen);
  int get itemCount => _lines.values.fold(0, (sum, l) => sum + l.quantity);
  bool get confirmed => _stall?.cached == false && _foods?.cached == false &&
    _categories?.cached == false && !_stallError && !_foodError && !_categoryError;
  String? get warning {
    if (_lines.isEmpty) return null;
    if (!confirmed) return 'Cart needs a current server menu. Connect and refresh.';
    if (_stall!.items.isEmpty) return 'This stall is no longer listed. Remove the selections.';
    if (!_stall!.items.single.stall.isOpen) return 'Stall is Closed. Your unpaid selections are not an order.';
    return null;
  }
  MenuFood? currentFood(String foodId) => _foods?.items.where((f) => f.id == foodId).firstOrNull;
  String? issue(CartLine line) {
    if (!confirmed) return 'Selection has not been verified with the server.';
    final current = currentFood(line.food.id);
    if (current == null || !current.draft.available) return 'No longer available. Remove this item.';
    if (!_categories!.items.any((c) => c.id == current.draft.categoryId)) return 'Category no longer available.';
    if (current.revision != line.food.revision) return 'Menu details changed. Review the latest selection.';
    return null;
  }

  void _checkActive() {
    if (!_active) throw const AccountException('This cart session has ended.');
  }
  void add(CatalogSelection selection, int quantity, {bool replaceStall = false}) {
    _checkActive();
    final vendor = selection.stall;
    final food = selection.food;
    if (vendor.stall.isCached || !vendor.stall.isOpen || !food.draft.available ||
        selection.category.id != food.draft.categoryId) {
      throw const AccountException('Choose a current available food from an Open stall.');
    }
    final switching = _vendorId != null && _vendorId != vendor.id;
    if (switching && !replaceStall) throw const AccountException('Confirm switching stalls before replacing the cart.');
    final previous = switching ? null : _lines[food.id];
    final count = (previous?.quantity ?? 0) + quantity;
    if (quantity < 1 || count > maxQuantity) throw const AccountException('Use 1–20 units per item.');
    if (!switching && previous == null && _lines.length >= maxProducts) {
      throw const AccountException('A cart can contain at most four distinct foods.');
    }
    if (previous != null && previous.food.revision != food.revision) {
      throw const AccountException('Review this item in your cart before adding more.');
    }
    // Validate everything before replacing another stall's unpaid cart.
    if (switching) _lines.clear();
    final changedStall = _vendorId != vendor.id;
    _vendorId = vendor.id; _stallName = vendor.stall.name;
    _lines[food.id] = CartLine(food, count);
    _version++;
    if (changedStall) refresh();
    notifyListeners();
  }

  void quantity(String id, int value) {
    _checkActive();
    final line = _lines[id];
    if (line == null) return;
    if (value < 1 || value > maxQuantity) throw const AccountException('Use 1–20 units per item.');
    if (value > line.quantity && (warning != null || issue(line) != null)) {
      throw const AccountException('Refresh and review this selection before increasing quantity.');
    }
    _lines[id] = CartLine(line.food, value); _version++; notifyListeners();
  }
  void remove(String id) {
    _checkActive(); _lines.remove(id); _version++;
    if (_lines.isEmpty) { clear(); } else { notifyListeners(); }
  }
  void clear() {
    _checkActive(); _lines.clear(); _vendorId = null; _stallName = null; _version++;
    _stop(); notifyListeners();
  }

  Future<void> review(String id, int shownRevision) async {
    _checkActive();
    final vendor = _vendorId, version = _version;
    if (repository == null || vendor == null) throw const AccountException('Refresh the cart first.');
    final selection = await repository!.selection(vendor, id);
    _checkActive();
    if (_vendorId != vendor || _version != version || !_lines.containsKey(id)) {
      throw const AccountException('Your cart changed. Please retry.');
    }
    if (selection.food.revision != shownRevision) throw const AccountException('The menu changed again. Review and retry.');
    final old = _lines[id]!;
    _lines[id] = CartLine(selection.food, old.quantity); _version++; notifyListeners();
  }

  void refresh() {
    _checkActive(); _stop();
    final vendor = _vendorId, repo = repository, generation = _generation;
    if (vendor == null || repo == null) { notifyListeners(); return; }
    bool valid() => _active && generation == _generation;
    _stallSub = repo.stall(vendor).listen((s) {
      if (valid()) { _stall = s; _stallError = false; notifyListeners(); }
    }, onError: (Object _) { if (valid()) { _stallError = true; notifyListeners(); } });
    _foodSub = repo.foods(vendor).listen((s) {
      if (valid()) { _foods = s; _foodError = false; notifyListeners(); }
    }, onError: (Object _) { if (valid()) { _foodError = true; notifyListeners(); } });
    _categorySub = repo.categories(vendor).listen((s) {
      if (valid()) { _categories = s; _categoryError = false; notifyListeners(); }
    }, onError: (Object _) { if (valid()) { _categoryError = true; notifyListeners(); } });
    notifyListeners();
  }
  void _stop() {
    _generation++;
    unawaited(_stallSub?.cancel()); unawaited(_foodSub?.cancel()); unawaited(_categorySub?.cancel());
    _stallSub = null; _foodSub = null; _categorySub = null;
    _stall = null; _foods = null; _categories = null;
    _stallError = false; _foodError = false; _categoryError = false;
  }
  @override
  void dispose() { _active = false; _lines.clear(); _stop(); super.dispose(); }
}
