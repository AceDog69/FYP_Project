import 'package:flutter/material.dart';
import '../models/vendor_menu.dart';
import '../services/vendor_menu_repository.dart';
import '../services/auth_repository.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/stall_picture_picker.dart';
import '../theme/app_theme.dart';

String menuError(Object error) => error is AccountException ? error.message
    : 'Unable to load or save the menu. Check your connection and retry.';

class VendorFoodEditor extends StatefulWidget {
  const VendorFoodEditor({super.key, required this.repository, required this.categories,
    required this.stallName, this.original});
  final VendorMenuRepository repository;
  final List<MenuCategory> categories;
  final String stallName;
  final MenuFood? original;
  @override
  State<VendorFoodEditor> createState() => _VendorFoodEditorState();
}

class _VendorFoodEditorState extends State<VendorFoodEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.original?.draft.name ?? '');
  late final _description = TextEditingController(text: widget.original?.draft.description ?? '');
  late final _price = TextEditingController(text: widget.original == null ? '' : rm(widget.original!.draft.priceSen).substring(3));
  late String? _category = widget.categories.any((c) => c.id == widget.original?.draft.categoryId)
      ? widget.original?.draft.categoryId : null;
  late String? _picture = widget.original?.draft.pictureId;
  late bool _available = widget.original?.draft.available ?? true;
  bool _busy = false;
  String? _error;
  @override
  void dispose() { _name.dispose(); _description.dispose(); _price.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_picture == null) { setState(() => _error = 'Choose a food picture.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.repository.saveFood(FoodDraft(name: _name.text, description: _description.text,
        priceSen: parsePriceSen(_price.text)!, categoryId: _category!, pictureId: _picture!,
        available: _available), original: widget.original);
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) setState(() => _error = menuError(e)); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: Scaffold(
    appBar: AppBar(backgroundColor: primaryOrange, foregroundColor: Colors.white,
      title: Text(widget.original == null ? 'Add Food' : 'Edit Food')),
    body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Form(key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.stallName), const SizedBox(height: 16),
          if (_picture != null) Align(alignment: Alignment.centerLeft,
            child: StallPicture(_picture!, width: 180, height: 120)),
          OutlinedButton(onPressed: _busy ? null : () async {
            final selected = await chooseStallPicture(context, _picture ?? 'nasi_lemak');
            if (mounted && selected != null) setState(() => _picture = selected);
          }, child: const Text('Choose Picture')),
          const SizedBox(height: 16),
          AppField(label: 'Food Name', controller: _name, enabled: !_busy,
            validator: (v) => v == null || v.trim().isEmpty || v.trim().length > 100
              ? 'Enter a food name (1–100 characters).' : null),
          TextFormField(controller: _description, enabled: !_busy, maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
            validator: (v) => v == null || v.trim().isEmpty || v.trim().length > 500
              ? 'Enter a description (1–500 characters).' : null),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(initialValue: _category, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Menu Category'),
            items: [for (final c in widget.categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: _busy ? null : (v) => setState(() => _category = v),
            validator: (v) => v == null ? 'Select a menu category.' : null),
          const SizedBox(height: 16),
          AppField(label: 'Price (RM)', controller: _price, enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => parsePriceSen(v ?? '') == null ? 'Enter RM 0.01–1000.00, up to two decimal places.' : null),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Available'),
            value: _available, onChanged: _busy ? null : (v) => setState(() => _available = v)),
          ErrorMessage(_error),
          PrimaryButton('Save Food', onPressed: _save, loading: _busy),
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ]),
      )),
    ))),
  ));
}
