import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../models/vendor_stall.dart';
import '../services/auth_repository.dart';
import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/stall_picture_picker.dart';
import '../widgets/vendor_profile_widgets.dart';
import 'vendor_stall_editor.dart';

class VendorProfile extends StatefulWidget {
  const VendorProfile({super.key, required this.profile, required this.repository});
  final UserProfile profile;
  final AuthRepository repository;
  @override
  State<VendorProfile> createState() => _VendorProfileState();
}

class _VendorProfileState extends State<VendorProfile> {
  late Stream<VendorStall> _stall;
  VendorStall? _editingStall;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _stall = widget.repository.watchVendorStall();
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try { await widget.repository.logout(); }
    catch (error) { if (mounted) setState(() => _error = friendlyError(error)); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Widget _account() => VendorSection(title: 'Account Information', children: [
    VendorInformation('Full Name', widget.profile.fullName),
    VendorInformation('Email Address', widget.profile.email),
    VendorInformation('Phone Number', widget.profile.phoneNumber),
    const VendorInformation('Role', 'Vendor'),
  ]);

  Widget _information(VendorStall stall) => VendorSection(
    title: 'Stall Information',
    action: OutlinedButton.icon(
      onPressed: _busy || stall.isCached ? null
          : () => setState(() => _editingStall = stall),
      icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit')),
    children: [
      Align(alignment: Alignment.centerLeft,
        child: StallPicture(stall.displayPictureId, width: 160, height: 100)),
      VendorInformation('Stall Name', stall.name),
      const Divider(),
      VendorInformation('Stall Category', stall.category),
      const Divider(),
      VendorInformation('Initial Preparation Time', '${stall.preparationMinutes} minutes'),
    ]);

  @override
  Widget build(BuildContext context) => StreamBuilder<VendorStall>(
    stream: _stall,
    builder: (context, snapshot) {
      final stall = snapshot.hasError || snapshot.connectionState == ConnectionState.waiting
          ? null : snapshot.data;
      return Material(color: const Color(0xFFFAFAFC), child: ListView(children: [
        VendorProfileHeader(stall?.name),
        Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(padding: const EdgeInsets.all(20), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _account(), ErrorMessage(_error),
              if (stall?.isCached == true)
                const Padding(padding: EdgeInsets.only(bottom: 16), child: Text(
                  'Cached stall information — may be out of date.',
                  style: TextStyle(color: mutedText))),
              if (_editingStall != null)
                VendorStallEditor(
                  stall: _editingStall!, repository: widget.repository,
                  onCancel: () => setState(() => _editingStall = null),
                  onBusy: (busy) => setState(() => _busy = busy),
                  onSaved: () {
                    setState(() => _editingStall = null);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Stall settings saved.')));
                  },
                )
              else if (stall != null) _information(stall)
              else if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()))
              else
                VendorSection(title: 'Unable to Load Stall', children: [
                  const Text('Stall information could not be loaded. Please retry.'),
                  OutlinedButton(onPressed: _busy ? null : () => setState(() {
                    _stall = widget.repository.watchVendorStall();
                  }), child: const Text('Retry')),
                ]),
              OutlinedButton.icon(
                onPressed: _busy ? null : _logout,
                icon: const Icon(Icons.logout), label: const Text('Logout'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size(double.infinity, 48)),
              ),
            ],
          )),
        )),
      ]));
    },
  );
}
