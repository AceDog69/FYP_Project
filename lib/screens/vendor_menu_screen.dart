import 'package:flutter/material.dart';
import '../models/vendor_menu.dart';
import '../models/vendor_stall.dart';
import '../services/auth_repository.dart';
import '../services/vendor_menu_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/stall_picture_picker.dart';
import '../widgets/delete_confirmation.dart';
import '../widgets/vendor_workspace_widgets.dart';
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
  bool _confirmingDelete = false;
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
    if (mounted && saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Food saved.')));
    }
  }
  Future<void> _delete(MenuFood food) async {
    final repository = _repo;
    if (_busy || _confirmingDelete || repository == null || !repository.canDeleteFood) return;
    // Lock before opening the dialog as well as while awaiting the server.
    setState(() { _confirmingDelete = true; _error = null; });
    try {
      final confirmed = await confirmDeletion(context, food.draft.name);
      if (!mounted || !confirmed) return;
      setState(() { _confirmingDelete = false; _busy = true; });
      await repository.deleteFood(food);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Food deleted.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = menuError(e));
    } finally {
      if (mounted) setState(() { _busy = false; _confirmingDelete = false; });
    }
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
          final safe = !failed && !loading && !cached && !_busy && !_confirmingDelete;
          final stallName = !stall.hasError ? stall.data?.name : null;
          return VendorWorkspacePage(header: VendorWorkspaceHeader('Manage Menu', subtitle: stallName), children: [
            LayoutBuilder(builder: (context, constraints) {
              final categoriesButton = OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                onPressed: safe ? () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                  MenuCategoriesScreen(repository: _repo!))) : null,
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.grid_view_outlined, size: 20),
                  SizedBox(width: 8), Flexible(child: Text('Manage Categories'))]));
              final addButton = FilledButton(
                onPressed: safe && categories.isNotEmpty ? () => _editor(categories, stallName ?? '') : null,
                child: const Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8, children: [Icon(Icons.add), Text('Add Food')]));
              if (constraints.maxWidth < 360 || MediaQuery.textScalerOf(context).scale(14) > 18) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  categoriesButton, const SizedBox(height: 10), addButton,
                ]);
              }
              return Row(children: [Expanded(child: categoriesButton), const SizedBox(width: 12),
                Expanded(child: addButton)]);
            }),
            const SizedBox(height: 20),
            Text('Menu Items', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12),
            ErrorMessage(_error),
            if (_busy) const LinearProgressIndicator(),
            if (failed) VendorWorkspaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Menu could not be loaded. Check your connection and retry.'),
              TextButton(onPressed: () => setState(_load), child: const Text('Retry')),
            ]))
            else if (loading) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else ...[
              if (cached) const Padding(padding: EdgeInsets.only(bottom: 12),
                child: Text('Cached menu — may be out of date. Connect to make changes.')),
              if (categories.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 12),
                child: Text('Create a menu category before adding food.')),
              if (foods.data!.items.isEmpty)
                const VendorWorkspaceCard(child: Padding(padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No food items yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 20)))),
              if (!_repo!.canDeleteFood) const Padding(padding: EdgeInsets.only(bottom: 12), child: Text(
                'Food deletion is unavailable until security testing is complete.', style: TextStyle(color: mutedText))),
              for (final food in foods.data!.items) VendorWorkspaceCard(key: ValueKey('menu-food-${food.id}'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    StallPicture(food.draft.pictureId, width: 96, height: 100), const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(food.draft.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(categories.any((c) => c.id == food.draft.categoryId)
                        ? categories.firstWhere((c) => c.id == food.draft.categoryId).name : 'Category unavailable',
                        style: const TextStyle(color: mutedText)),
                      const SizedBox(height: 8),
                      Text(rm(food.draft.priceSen), style: const TextStyle(color: primaryOrange, fontSize: 21,
                        fontWeight: FontWeight.w700)),
                    ])),
                  ]),
                  const SizedBox(height: 8),
                  SwitchListTile(contentPadding: EdgeInsets.zero,
                    secondary: Icon(food.draft.available ? Icons.check_circle_outline : Icons.pause_circle_outline,
                      color: food.draft.available ? const Color(0xFF176B35) : mutedText),
                    title: Text(food.draft.available ? 'Available' : 'Unavailable',
                      style: TextStyle(color: food.draft.available ? const Color(0xFF176B35) : mutedText,
                        fontWeight: FontWeight.w600)), value: food.draft.available,
                    onChanged: safe ? (v) => _action(() => _repo!.setAvailable(food, v)) : null),
                  const Divider(height: 20),
                  Wrap(spacing: 12, runSpacing: 8, children: [
                    OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(100, 48)),
                      onPressed: safe ? () => _editor(categories, stallName ?? '', food) : null,
                      child: const Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8, children: [Icon(Icons.edit_outlined, size: 18), Text('Edit')])),
                    OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
                      onPressed: safe && _repo!.canDeleteFood ? () => _delete(food) : null,
                      child: const Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8, children: [Icon(Icons.delete_outline, size: 18), Text('Delete Food')])),
                  ]),
                ])),
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
      if (s.hasError) {
        return Center(child: TextButton(onPressed: () => setState(() =>
          _categories = widget.repository.categories()), child: const Text('Unable to load categories. Retry')));
      }
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      return ListView(padding: const EdgeInsets.all(20), children: [
        if (s.data!.cached) const Text('Cached categories — connect to make changes.'),
        FilledButton(onPressed: s.data!.cached ? null : () => _edit(), child: const Text('Add Category')),
        const SizedBox(height: 16),
        const Text('Category deletion is unavailable because empty categories cannot yet be verified securely.'),
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
