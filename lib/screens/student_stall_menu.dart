import 'package:flutter/material.dart';
import '../models/catalog.dart';
import '../models/vendor_menu.dart';
import '../services/auth_repository.dart';
import '../services/catalog_repository.dart';
import '../services/student_cart.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/stall_picture_picker.dart';
import 'student_cart_screen.dart';

class StudentStallMenu extends StatefulWidget {
  const StudentStallMenu({super.key, required this.vendorId, required this.repository,
    required this.cart, required this.onCart});
  final String vendorId;
  final CatalogRepository repository;
  final StudentCart cart;
  final VoidCallback onCart;
  @override
  State<StudentStallMenu> createState() => _StudentStallMenuState();
}

class _StudentStallMenuState extends State<StudentStallMenu> {
  late Stream<MenuData<CatalogStall>> _stall;
  late Stream<MenuData<MenuCategory>> _categories;
  late Stream<MenuData<MenuFood>> _foods;
  String? _category;
  @override
  void initState() { super.initState(); _load(); }
  void _load() {
    _stall = widget.repository.stall(widget.vendorId);
    _categories = widget.repository.categories(widget.vendorId);
    _foods = widget.repository.foods(widget.vendorId);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stall Menu'), actions: [
      AnimatedBuilder(animation: widget.cart, builder: (context, _) => TextButton(
        onPressed: widget.onCart, child: Text('Cart (${widget.cart.itemCount})'))),
    ]),
    body: StreamBuilder<MenuData<CatalogStall>>(stream: _stall, builder: (context, stall) =>
      StreamBuilder<MenuData<MenuCategory>>(stream: _categories, builder: (context, cats) =>
        StreamBuilder<MenuData<MenuFood>>(stream: _foods, builder: (context, foods) {
          final failed = stall.hasError || cats.hasError || foods.hasError;
          final waiting = !stall.hasData || !cats.hasData || !foods.hasData ||
            stall.connectionState == ConnectionState.waiting || cats.connectionState == ConnectionState.waiting ||
            foods.connectionState == ConnectionState.waiting;
          if (failed) {
            return Center(child: TextButton(onPressed: () => setState(_load), child: const Text('Unable to load menu. Retry')));
          }
          if (waiting) return const Center(child: CircularProgressIndicator());
          if (stall.data!.items.isEmpty) return const Center(child: Text('This stall is no longer listed.'));
          final listing = stall.data!.items.single;
          final cached = stall.data!.cached || cats.data!.cached || foods.data!.cached;
          final categories = cats.data!.items;
          final selected = categories.any((c) => c.id == _category) ? _category : null;
          final items = foods.data!.items.where((f) => f.draft.available &&
            categories.any((c) => c.id == f.draft.categoryId) &&
            (selected == null || f.draft.categoryId == selected)).toList();
          return ListView(padding: const EdgeInsets.all(20), children: [
            StallPicture(listing.stall.displayPictureId, height: 160), const SizedBox(height: 12),
            Text(listing.stall.name, style: Theme.of(context).textTheme.headlineSmall),
            Text(listing.stall.category), Text(listing.stall.isOpen ? 'Open' : 'Closed'),
            Text('Initial preparation: ${listing.stall.preparationMinutes} minutes'),
            if (cached) const Text('Cached menu — connect to select food.'),
            if (!listing.stall.isOpen) const Text('Stall is Closed. Browse only; new selections are unavailable.'),
            const SizedBox(height: 16),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: const Text('All'),
                selected: selected == null, showCheckmark: false, onSelected: (_) => setState(() => _category = null))),
              for (final category in categories) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
                label: Text(category.name), selected: selected == category.id, showCheckmark: false,
                onSelected: (_) => setState(() => _category = category.id))),
            ])),
            const SizedBox(height: 12),
            if (items.isEmpty) const Padding(padding: EdgeInsets.all(32),
              child: Text('No available food items', textAlign: TextAlign.center)),
            for (final food in items) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                StallPicture(food.draft.pictureId, height: 140), const SizedBox(height: 12),
                Text(food.draft.name, style: Theme.of(context).textTheme.titleLarge),
                Text(food.draft.description), Text(categories.firstWhere((c) => c.id == food.draft.categoryId).name),
                Text(rm(food.draft.priceSen), style: const TextStyle(color: primaryOrange, fontWeight: FontWeight.w700)),
                OutlinedButton(onPressed: cached || !listing.stall.isOpen ? null : () => showDialog<void>(
                  context: context, useRootNavigator: false, builder: (_) => _FoodSelection(
                    vendorId: widget.vendorId, foodId: food.id, repository: widget.repository, cart: widget.cart)),
                  child: const Text('Select Food')),
              ]))),
          ]);
        }))),
  );
}

class _FoodSelection extends StatefulWidget {
  const _FoodSelection({required this.vendorId, required this.foodId, required this.repository, required this.cart});
  final String vendorId, foodId;
  final CatalogRepository repository;
  final StudentCart cart;
  @override
  State<_FoodSelection> createState() => _FoodSelectionState();
}
class _FoodSelectionState extends State<_FoodSelection> {
  late final _stall = widget.repository.stall(widget.vendorId);
  late final _foods = widget.repository.foods(widget.vendorId);
  int _quantity = 1;
  bool _busy = false;
  String? _error;
  Future<void> _add(MenuFood shown) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final version = widget.cart.version;
      final switching = widget.cart.vendorId != null && widget.cart.vendorId != widget.vendorId;
      if (switching) {
        final replace = await confirmCartAction(context, 'Switch stalls?',
          'Selecting another stall clears your existing unpaid cart from ${widget.cart.stallName}. Continue?', 'Switch Stall');
        if (!mounted || !replace) return;
      }
      final current = await widget.repository.selection(widget.vendorId, widget.foodId);
      if (!mounted) return;
      if (widget.cart.version != version) throw const AccountException('Your cart changed. Review and retry.');
      if (current.food.revision != shown.revision) throw const AccountException('Food details changed. Review and retry.');
      widget.cart.add(current, _quantity, replaceStall: switching);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to unpaid cart.')));
    } catch (e) {
      if (mounted) setState(() => _error = catalogError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<MenuData<CatalogStall>>(stream: _stall, builder: (context, stall) =>
    StreamBuilder<MenuData<MenuFood>>(stream: _foods, builder: (context, foods) {
      final food = foods.data?.items.where((f) => f.id == widget.foodId && f.draft.available).firstOrNull;
      final safe = !stall.hasError && !foods.hasError &&
        stall.connectionState != ConnectionState.waiting && foods.connectionState != ConnectionState.waiting &&
        stall.data?.cached == false && foods.data?.cached == false &&
        stall.data?.items.firstOrNull?.stall.isOpen == true && food != null;
      return PopScope(canPop: !_busy, child: AlertDialog(scrollable: true,
        title: const Text('Food selection'), content: SizedBox(width: 340, child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (food != null) ...[
              StallPicture(food.draft.pictureId, height: 140), const SizedBox(height: 8),
              Text(food.draft.name, style: Theme.of(context).textTheme.titleLarge),
              Text(food.draft.description), Text(rm(food.draft.priceSen)),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(tooltip: 'Decrease quantity', onPressed: _busy || _quantity <= 1 ? null : () => setState(() => _quantity--),
                  icon: const Icon(Icons.remove_circle_outline)), Text('$_quantity'),
                IconButton(tooltip: 'Increase quantity', onPressed: _busy || _quantity >= StudentCart.maxQuantity ? null : () => setState(() => _quantity++),
                  icon: const Icon(Icons.add_circle_outline)),
              ]), Text('Subtotal: ${rm(food.draft.priceSen * _quantity)}'),
            ],
            if (!safe) const Text('Selection unavailable. Wait for a current server menu from an Open stall.'),
            ErrorMessage(_error),
          ])),
        actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: _busy || !safe ? null : () => _add(food), child: Text(_busy ? 'Checking…' : 'Add to Cart'))],
      ));
    }));
}
