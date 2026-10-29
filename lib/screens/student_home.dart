import 'package:flutter/material.dart';
import '../constants/stall_categories.dart';
import '../models/catalog.dart';
import '../models/vendor_menu.dart';
import '../services/catalog_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/stall_picture_picker.dart';
import '../widgets/student_workspace_widgets.dart';
import '../widgets/vendor_workspace_widgets.dart';
import '../widgets/stall_queue_count.dart';

class StudentHome extends StatefulWidget {
  const StudentHome({super.key, required this.repository, required this.onStall});
  final CatalogRepository? repository;
  final ValueChanged<CatalogStall> onStall;
  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  late Stream<MenuData<CatalogStall>>? _stalls;
  final _search = TextEditingController();
  String _category = 'All';
  @override
  void initState() { super.initState(); _stalls = widget.repository?.stalls(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => StreamBuilder<MenuData<CatalogStall>>(
    stream: _stalls, builder: (context, s) {
      final failed = widget.repository == null || s.hasError;
      final waiting = !failed && (!s.hasData || s.connectionState == ConnectionState.waiting);
      final stalls = (s.data?.items ?? <CatalogStall>[]).where((c) =>
        c.stall.name.toLowerCase().contains(_search.text.trim().toLowerCase()) &&
        (_category == 'All' || c.stall.category == _category)).toList()
        ..sort((a, b) => a.stall.name.toLowerCase().compareTo(b.stall.name.toLowerCase()));
      return VendorWorkspacePage(
        header: const StudentWorkspaceHeader('Welcome, Student', icon: Icons.home_outlined, subtitle: 'Find your next meal'),
        children: [
        TextField(controller: _search, onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: 'Search stall name', prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(tooltip: 'Clear search', icon: const Icon(Icons.clear),
              onPressed: () => setState(_search.clear)))),
        const SizedBox(height: 12),
        StudentFilterBar(key: const ValueKey('home-categories'), labels: ['All', ...stallCategories],
          selected: _category, onSelected: (category) => setState(() => _category = category)),
        const SizedBox(height: 16),
        if (failed) ...[
          const Text('Stalls could not be loaded. Check your connection.'),
          TextButton(onPressed: () => setState(() => _stalls = widget.repository?.stalls()), child: const Text('Retry')),
        ] else if (waiting) const Center(child: CircularProgressIndicator())
        else ...[
          if (s.data!.cached) const StudentNotice('Cached stalls — status may be out of date. Connect to refresh.'),
          if (stalls.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Text(
            _search.text.trim().isNotEmpty || _category != 'All' ? 'No matching stalls' : 'No stalls available yet',
            textAlign: TextAlign.center)),
          for (final listing in stalls) VendorWorkspaceCard(key: ValueKey('stall-${listing.id}'),
            child: InkWell(onTap: () => widget.onStall(listing), borderRadius: BorderRadius.circular(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  StallPicture(listing.stall.displayPictureId, width: 88, height: 96), const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(listing.stall.name, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 6),
                    Text(listing.stall.category, style: const TextStyle(color: mutedText)),
                    const SizedBox(height: 10), StallStatusBadge(listing.stall.isOpen),
                  ])),
                ]),
                const SizedBox(height: 14),
                Text('Initial preparation: ${listing.stall.preparationMinutes} minutes', style: const TextStyle(color: mutedText)),
                const SizedBox(height: 8),
                StallQueueCount(vendorUid: listing.id, repository: widget.repository, currentStall: !s.data!.cached),
                const SizedBox(height: 14),
                FilledButton(onPressed: () => widget.onStall(listing), child: const Text('View Menu')),
              ]))),
        ],
      ]);
    });
}
