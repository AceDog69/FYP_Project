import 'package:flutter/material.dart';
import '../models/catalog.dart';
import '../models/vendor_menu.dart';
import '../services/auth_repository.dart';
import '../services/catalog_repository.dart';
import '../services/student_cart.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/stall_picture_picker.dart';
import '../widgets/student_workspace_widgets.dart';
import '../widgets/vendor_workspace_widgets.dart';
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
  Widget _page(List<Widget> children) => VendorWorkspacePage(
    header: StudentWorkspaceHeader('Stall Menu', icon: Icons.restaurant_menu_outlined, back: true,
      action: AnimatedBuilder(animation: widget.cart, builder: (context, _) => TextButton(
        style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(48, 48)),
        onPressed: widget.onCart, child: Text('Cart (${widget.cart.itemCount})')))), children: children);
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: StreamBuilder<MenuData<CatalogStall>>(stream: _stall, builder: (context, stall) =>
      StreamBuilder<MenuData<MenuCategory>>(stream: _categories, builder: (context, cats) =>
        StreamBuilder<MenuData<MenuFood>>(stream: _foods, builder: (context, foods) {
          final failed = stall.hasError || cats.hasError || foods.hasError;
          final waiting = !stall.hasData || !cats.hasData || !foods.hasData ||
            stall.connectionState == ConnectionState.waiting || cats.connectionState == ConnectionState.waiting ||
            foods.connectionState == ConnectionState.waiting;
          if (failed) {
            return _page([VendorWorkspaceCard(child: TextButton(onPressed: () => setState(_load), child: const Text('Unable to load menu. Retry')))]);
          }
          if (waiting) return _page([const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))]);
          if (stall.data!.items.isEmpty) return _page([const VendorWorkspaceCard(child: Text('This stall is no longer listed.'))]);
          final listing = stall.data!.items.single;
          final cached = stall.data!.cached || cats.data!.cached || foods.data!.cached;
          final categories = cats.data!.items;
          final selected = categories.any((c) => c.id == _category) ? _category : null;
          final items = foods.data!.items.where((f) => f.draft.available &&
            categories.any((c) => c.id == f.draft.categoryId) &&
            (selected == null || f.draft.categoryId == selected)).toList();
          return _page([
            VendorWorkspaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                StallPicture(listing.stall.displayPictureId, width: 80, height: 88), const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(listing.stall.name, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 6),
                  Text(listing.stall.category, style: const TextStyle(color: mutedText)), const SizedBox(height: 10),
                  StallStatusBadge(listing.stall.isOpen),
                ])),
              ]), const SizedBox(height: 14),
              Text('Initial preparation: ${listing.stall.preparationMinutes} minutes', style: const TextStyle(color: mutedText)),
            ])),
            if (cached) const StudentNotice('Cached menu — connect to select food.'),
            if (!listing.stall.isOpen) const StudentNotice('Stall is Closed. Browse only; new selections are unavailable.'),
            StudentFilterBar(key: const ValueKey('menu-categories'), labels: ['All', ...categories.map((c) => c.name)],
              values: ['', ...categories.map((c) => c.id)], selected: selected ?? '',
              onSelected: (id) => setState(() => _category = id.isEmpty ? null : id)),
            const SizedBox(height: 12),
            if (items.isEmpty) const Padding(padding: EdgeInsets.all(32),
              child: Text('No available food items', textAlign: TextAlign.center)),
            for (final food in items) VendorWorkspaceCard(key: ValueKey('student-food-${food.id}'), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  StallPicture(food.draft.pictureId, width: 88, height: 96), const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(food.draft.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(categories.firstWhere((c) => c.id == food.draft.categoryId).name, style: const TextStyle(color: mutedText)),
                    const SizedBox(height: 10),
                    Text(rm(food.draft.priceSen), style: const TextStyle(color: primaryOrange, fontSize: 21, fontWeight: FontWeight.w700)),
                  ])),
                ]), const SizedBox(height: 12),
                Text(food.draft.description, style: const TextStyle(color: mutedText)), const SizedBox(height: 14),
                OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                  onPressed: cached || !listing.stall.isOpen ? null : () => showDialog<void>(
                  context: context, useRootNavigator: false, builder: (_) => _FoodSelection(
                    vendorId: widget.vendorId, foodId: food.id, repository: widget.repository, cart: widget.cart)),
                  child: const Text('Select Food')),
              ])),
          ]);
        })))),
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
