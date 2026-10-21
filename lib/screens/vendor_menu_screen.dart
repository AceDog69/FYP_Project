import 'package:flutter/material.dart';
import '../models/vendor_menu.dart';
import '../models/vendor_stall.dart';
import '../services/auth_repository.dart';
import '../services/vendor_menu_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/stall_picture_picker.dart';
import '../widgets/delete_confirmation.dart';
import 'vendor_food_editor.dart';

class VendorMenuScreen extends StatefulWidget {
  const VendorMenuScreen({super.key, required this.auth});
  final AuthRepository auth;
  @override
  State<VendorMenuScreen> createState() => _VendorMenuScreenState();
}

class _VendorMenuScreenState extends State<VendorMenuScreen> {
  late Stream<MenuData<MenuCategory>>? _categories;
  late Stream<MenuData<MenuFood>>? _foods;
  late Stream<VendorStall> _stall;
  bool _busy = false;
  String? _error;
  VendorMenuRepository? get _repo => widget.auth.menuRepository;
  @override
  void initState() { super.initState(); _load(); }
  void _load() {
    _categories = _repo?.categories(); _foods = _repo?.foods();
    _stall = widget.auth.watchVendorStall(); _error = null;
  }
  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try { await action(); }
    catch (e) { if (mounted) setState(() => _error = menuError(e)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _editor(List<MenuCategory> categories, String stall, [MenuFood? food]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) =>
      VendorFoodEditor(repository: _repo!, categories: categories, stallName: stall, original: food)));
    if (mounted && saved == true) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Food saved.')));
  }

  @override
  Widget build(BuildContext context) => Material(color: const Color(0xFFFAFAFC),
    child: StreamBuilder<VendorStall>(stream: _stall, builder: (context, stall) =>
      StreamBuilder<MenuData<MenuCategory>>(stream: _categories, builder: (context, cats) =>
        StreamBuilder<MenuData<MenuFood>>(stream: _foods, builder: (context, foods) {
          final failed = _repo == null || stall.hasError || cats.hasError || foods.hasError;
          final loading = !failed && (!stall.hasData || !cats.hasData || !foods.hasData ||
            stall.connectionState == ConnectionState.waiting ||
            cats.connectionState == ConnectionState.waiting || foods.connectionState == ConnectionState.waiting);
          final categories = cats.data?.items ?? <MenuCategory>[];
          final cached = stall.data?.isCached != false || cats.data?.cached != false || foods.data?.cached != false;
          final safe = !failed && !loading && !cached && !_busy;
          final stallName = !stall.hasError ? stall.data?.name : null;
          return ListView(padding: const EdgeInsets.all(20), children: [
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: primaryOrange,
              borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [const Text('Manage Menu', style: TextStyle(color: Colors.white, fontSize: 24,
                fontWeight: FontWeight.w700)), if (stallName != null) Text(stallName,
                  style: const TextStyle(color: Colors.white))])),
            const SizedBox(height: 20),
            Wrap(spacing: 12, runSpacing: 8, children: [
              OutlinedButton(onPressed: safe ? () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                MenuCategoriesScreen(repository: _repo!))) : null, child: const Text('Manage Categories')),
              OutlinedButton(onPressed: safe && categories.isNotEmpty
                ? () => _editor(categories, stallName ?? '') : null, child: const Text('Add Food')),
            ]),
            const SizedBox(height: 16), ErrorMessage(_error),
            if (_busy) const LinearProgressIndicator(),
            if (failed) ...[
              const Text('Menu could not be loaded. Check your connection and retry.'),
              TextButton(onPressed: () => setState(_load), child: const Text('Retry')),
            ] else if (loading) const Center(child: CircularProgressIndicator())
            else ...[
              if (cached) const Text('Cached menu — may be out of date. Connect to make changes.'),
              if (categories.isEmpty) const Text('Create a menu category before adding food.'),
              if (foods.data!.items.isEmpty) ...[
                const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Text('No food items yet',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 20))),
              ],
              const Text('Deletion awaits reviewed local security tests.', style: TextStyle(color: mutedText)),
              for (final food in foods.data!.items) Card(child: Padding(padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    StallPicture(food.draft.pictureId, width: 84, height: 80), const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(food.draft.name, style: Theme.of(context).textTheme.titleMedium),
                      Text(categories.any((c) => c.id == food.draft.categoryId)
                        ? categories.firstWhere((c) => c.id == food.draft.categoryId).name : 'Category unavailable'),
                      Text(rm(food.draft.priceSen), style: const TextStyle(color: primaryOrange, fontWeight: FontWeight.w700)),
                    ])),
                  ]),
                  SwitchListTile(contentPadding: EdgeInsets.zero,
                    title: Text(food.draft.available ? 'Available' : 'Unavailable'), value: food.draft.available,
                    onChanged: safe ? (v) => _action(() => _repo!.setAvailable(food, v)) : null),
                  Wrap(spacing: 12, children: [
                    OutlinedButton(onPressed: safe ? () => _editor(categories, stallName ?? '', food) : null,
                      child: const Text('Edit')),
                    OutlinedButton(onPressed: safe && _repo!.canDeleteFood ? () async {
                      if (await confirmDeletion(context, food.draft.name)) {
                        await _action(() => _repo!.deleteFood(food));
                      }
                    } : null, child: const Text('Delete Food')),
                  ]),
                ]))),
            ],
          ]);
        }))),
  );
}

class MenuCategoriesScreen extends StatefulWidget {
  const MenuCategoriesScreen({super.key, required this.repository});
  final VendorMenuRepository repository;
  @override
  State<MenuCategoriesScreen> createState() => _MenuCategoriesScreenState();
}

class _MenuCategoriesScreenState extends State<MenuCategoriesScreen> {
  late Stream<MenuData<MenuCategory>> _categories;
  @override
  void initState() { super.initState(); _categories = widget.repository.categories(); }
  Future<void> _edit([MenuCategory? category]) => showDialog<void>(context: context,
    builder: (_) => _CategoryDialog(repository: widget.repository, original: category));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(backgroundColor: primaryOrange, foregroundColor: Colors.white, title: const Text('Manage Categories')),
    body: StreamBuilder<MenuData<MenuCategory>>(stream: _categories, builder: (context, s) {
      if (s.hasError) return Center(child: TextButton(onPressed: () => setState(() =>
        _categories = widget.repository.categories()), child: const Text('Unable to load categories. Retry')));
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      return ListView(padding: const EdgeInsets.all(20), children: [
        if (s.data!.cached) const Text('Cached categories — connect to make changes.'),
        FilledButton(onPressed: s.data!.cached ? null : () => _edit(), child: const Text('Add Category')),
        const SizedBox(height: 16),
        const Text('Category deletion is blocked until membership and deletion races are proven in local security tests.'),
        for (final c in s.data!.items) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(c.name), Wrap(spacing: 12, children: [
            TextButton(onPressed: s.data!.cached ? null : () => _edit(c), child: const Text('Edit')),
            const TextButton(onPressed: null, child: Text('Delete Category')),
          ])]))),
      ]);
    }),
  );
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.repository, this.original});
  final VendorMenuRepository repository;
  final MenuCategory? original;
  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}
class _CategoryDialogState extends State<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.original?.name ?? '');
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  @override
  void dispose() { _name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: AlertDialog(
    title: Text(widget.original == null ? 'Add Category' : 'Edit Category'),
    content: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(controller: _name, enabled: !_busy, validator: categoryError,
        decoration: const InputDecoration(labelText: 'Category Name')),
      ErrorMessage(_error),
    ])),
    actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: _busy ? null : () async {
        if (!_form.currentState!.validate()) return;
        setState(() { _busy = true; _error = null; });
        try {
          await widget.repository.saveCategory(_name.text, original: widget.original);
          if (context.mounted) Navigator.pop(context);
        } catch (e) { if (mounted) setState(() => _error = menuError(e)); }
        finally { if (mounted) setState(() => _busy = false); }
      }, child: Text(_busy ? 'Saving…' : 'Save'))],
  ));
}
