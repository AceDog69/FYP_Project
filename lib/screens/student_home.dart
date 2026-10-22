import 'package:flutter/material.dart';
import '../constants/stall_categories.dart';
import '../models/catalog.dart';
import '../models/vendor_menu.dart';
import '../services/catalog_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/stall_picture_picker.dart';

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
      return ListView(padding: const EdgeInsets.all(20), children: [
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: primaryOrange,
          borderRadius: BorderRadius.circular(20)), child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Welcome, Student', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
            SizedBox(height: 8), Text('Find your next meal', style: TextStyle(color: Colors.white)),
          ])),
        const SizedBox(height: 20),
        TextField(controller: _search, onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: 'Search stall name', prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(tooltip: 'Clear search', icon: const Icon(Icons.clear),
              onPressed: () => setState(_search.clear)))),
        const SizedBox(height: 12),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          for (final category in ['All', ...stallCategories]) Padding(padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: Text(category), selected: category == _category,
              showCheckmark: false,
              onSelected: (_) => setState(() => _category = category))),
        ])),
        const SizedBox(height: 16),
        if (failed) ...[
          const Text('Stalls could not be loaded. Check your connection.'),
          TextButton(onPressed: () => setState(() => _stalls = widget.repository?.stalls()), child: const Text('Retry')),
        ] else if (waiting) const Center(child: CircularProgressIndicator())
        else ...[
          if (s.data!.cached) const Text('Cached stalls — status may be out of date. Connect to refresh.'),
          if (stalls.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Text(
            _search.text.trim().isNotEmpty || _category != 'All' ? 'No matching stalls' : 'No stalls available yet',
            textAlign: TextAlign.center)),
          for (final listing in stalls) Card(child: InkWell(onTap: () => widget.onStall(listing),
            borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                StallPicture(listing.stall.displayPictureId, height: 140), const SizedBox(height: 12),
                Text(listing.stall.name, style: Theme.of(context).textTheme.titleLarge),
                Text(listing.stall.category), const SizedBox(height: 6),
                Text(listing.stall.isOpen ? 'Open' : 'Closed', style: TextStyle(
                  color: listing.stall.isOpen ? Colors.green.shade800 : mutedText)),
                Text('Initial preparation: ${listing.stall.preparationMinutes} minutes'),
                const SizedBox(height: 8), const Text('View Menu', style: TextStyle(color: primaryOrange)),
              ])))),
        ],
      ]);
    });
}
