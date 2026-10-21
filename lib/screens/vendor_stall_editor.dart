import 'package:flutter/material.dart';
import '../constants/predefined_pictures.dart';
import '../constants/stall_categories.dart';
import '../models/vendor_stall.dart';
import '../services/auth_repository.dart';
import '../services/error_messages.dart';
import '../services/validators.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/stall_picture_picker.dart';
import '../widgets/vendor_profile_widgets.dart';

class VendorStallEditor extends StatefulWidget {
  const VendorStallEditor({super.key, required this.stall, required this.repository,
    required this.onCancel, required this.onSaved, required this.onBusy});
  final VendorStall stall;
  final AuthRepository repository;
  final VoidCallback onCancel, onSaved;
  final ValueChanged<bool> onBusy;
  @override
  State<VendorStallEditor> createState() => _VendorStallEditorState();
}

class _VendorStallEditorState extends State<VendorStallEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.stall.name);
  late final _minutes = TextEditingController(text: '${widget.stall.preparationMinutes}');
  late String? _category = stallCategories.contains(widget.stall.category)
      ? widget.stall.category : null;
  late String? _pictureId = widget.stall.pictureId;
  bool _busy = false;
  String? _error;
  String get _picture => resolvedPictureId(_pictureId, _category ?? widget.stall.category);

  @override
  void dispose() {
    _name.dispose(); _minutes.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final id = await chooseStallPicture(context, _picture);
    if (mounted && id != null) setState(() => _pictureId = id);
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    widget.onBusy(true);
    var saved = false;
    try {
      await widget.repository.updateStallSettings(StallSettings(
        name: _name.text, category: _category!,
        preparationMinutes: int.parse(_minutes.text.trim()), pictureId: _picture));
      saved = true;
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusy(false);
      }
    }
    if (mounted && saved) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) => Form(key: _form, child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      VendorSection(title: 'Stall Information',
        action: TextButton(onPressed: _busy ? null : widget.onCancel,
          child: const Text('Cancel')),
        children: [
          AppField(label: 'Stall Name', controller: _name,
            validator: Validators.name, enabled: !_busy),
          const Text('Stall Picture'), const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center, children: [
              StallPicture(_picture),
              OutlinedButton(onPressed: _busy ? null : _choose,
                child: const Text('Choose Picture')),
            ]),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _category, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Stall Category'),
            items: [for (final category in stallCategories)
              DropdownMenuItem(value: category, child: Text(category))],
            onChanged: _busy ? null : (value) => setState(() => _category = value),
            validator: (value) => value == null ? 'Please select a stall category.' : null,
          ),
          const SizedBox(height: 16),
          AppField(label: 'Initial Preparation Time (minutes)', controller: _minutes,
            validator: Validators.minutes, keyboardType: TextInputType.number,
            enabled: !_busy),
          ErrorMessage(_error),
        ]),
      PrimaryButton('Save Changes', onPressed: _busy ? null : _save, loading: _busy),
      const SizedBox(height: 16),
    ],
  ));
}
