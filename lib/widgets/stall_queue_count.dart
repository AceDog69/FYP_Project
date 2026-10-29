import 'package:flutter/material.dart';
import '../models/public_queue_count.dart';
import '../services/catalog_repository.dart';
import '../theme/app_theme.dart';

class StallQueueCount extends StatefulWidget {
  const StallQueueCount({super.key, required this.vendorUid, required this.repository, required this.currentStall});
  final String vendorUid;
  final CatalogRepository? repository;
  final bool currentStall;
  @override
  State<StallQueueCount> createState() => _StallQueueCountState();
}
class _StallQueueCountState extends State<StallQueueCount> {
  late Stream<PublicQueueCount?>? _count = widget.repository?.queueCount(widget.vendorUid);
  @override
  void didUpdateWidget(covariant StallQueueCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vendorUid != widget.vendorUid || oldWidget.repository != widget.repository) {
      _count = widget.repository?.queueCount(widget.vendorUid);
    }
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<PublicQueueCount?>(stream: _count, builder: (context, snapshot) {
    final verified = widget.repository != null && widget.currentStall && !snapshot.hasError && snapshot.connectionState == ConnectionState.active &&
      snapshot.data != null && !snapshot.data!.cached;
    return Semantics(liveRegion: true, child: Text(verified ? 'Orders in queue: ${snapshot.data!.count}' : 'Queue unavailable',
      key: ValueKey('home-queue-count-${widget.vendorUid}'), style: const TextStyle(color: mutedText)));
  });
}
