import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/confirmed_order.dart';
import '../models/vendor_menu.dart';
import 'order_repository.dart';

enum ReadyConnection { loading, server, cached, error, unavailable }

/// Read state exists only in this authenticated app session; it is not a receipt.
class ReadyNotice {
  const ReadyNotice(this.order, {this.viewed = false});
  final ConfirmedOrder order;
  final bool viewed;
  String get eventId => '${order.studentUid}/${order.id}/${order.readyAt!.seconds}:${order.readyAt!.nanoseconds}';
}

/// Uses the existing owner-scoped repository stream. FirebaseOrderRepository
/// discards hasPendingWrites snapshots; cached snapshots never create events here.
/// No Firestore writes, clocks, checkout requests or private queue reads are used.
class ReadyNotifications extends ChangeNotifier {
  factory ReadyNotifications({required String studentUid, required OrderRepository? repository,
    required String? Function() currentUid, bool foreground = true}) =>
      ReadyNotifications._(studentUid, repository, currentUid, foreground);

  ReadyNotifications._(this.studentUid, this.repository, this.currentUid, this._foreground) {
    unawaited(refresh());
  }
  final String studentUid;
  final OrderRepository? repository;
  final String? Function() currentUid;
  StreamSubscription<MenuData<ConfirmedOrder>>? _subscription;
  final _records = <String, ReadyNotice>{};
  final _previous = <String, ConfirmedOrder>{};
  final _announced = <String>{};
  final _alerts = <String>[];
  bool _baseline = false, _disposed = false, _expired = false, _foreground;
  int _generation = 0;
  ReadyConnection _connection = ReadyConnection.loading;
  ReadyConnection get connection => _connection;
  bool get foreground => _foreground;
  bool get sessionIsCurrent => !_disposed && !_expired && currentUid() == studentUid;
  List<ReadyNotice> get notices {
    if (!sessionIsCurrent) return const [];
    return List.unmodifiable(_records.values.toList()..sort((a, b) {
      final time = b.order.readyAt!.compareTo(a.order.readyAt!);
      return time == 0 ? a.order.id.compareTo(b.order.id) : time;
    }));
  }
  int get unreadCount => notices.where((n) => !n.viewed).length;
  ReadyNotice? notice(String orderId) => sessionIsCurrent ? _records[orderId] : null;

  bool _eligible(ConfirmedOrder order) => order.studentUid == studentUid &&
    ((order.status == 'Ready' && order.statusRevision == 2) ||
      (order.status == 'Completed' && order.statusRevision == 3)) &&
    order.readyAt != null && order.preparingAt != null && order.statusUpdatedAt != null &&
    order.readyAt!.compareTo(order.createdAt) >= 0 &&
    order.statusUpdatedAt!.compareTo(order.readyAt!) >= 0;

  void _expire() {
    if (_disposed || _expired) return;
    _expired = true; _generation++;
    unawaited(_subscription?.cancel()); _subscription = null;
    _records.clear(); _previous.clear(); _announced.clear(); _alerts.clear();
    _connection = ReadyConnection.unavailable;
    notifyListeners();
  }

  Future<void> refresh({bool rebaseline = false}) async {
    if (_disposed || _expired) return;
    if (!sessionIsCurrent) { _expire(); return; }
    final generation = ++_generation, old = _subscription;
    _subscription = null;
    if (rebaseline) { _baseline = false; _alerts.clear(); }
    _connection = repository == null ? ReadyConnection.unavailable : ReadyConnection.loading;
    notifyListeners();
    try {
      if (old != null) { unawaited(old.cancel().catchError((Object _) {})); }
      if (!sessionIsCurrent || generation != _generation || repository == null) return;
      _subscription = repository!.orders(vendor: false).listen((data) {
        if (_disposed || generation != _generation) return;
        if (!sessionIsCurrent) { _expire(); return; }
        if (data.cached) {
          _connection = ReadyConnection.cached; _alerts.clear(); notifyListeners(); return;
        }
        final own = {for (final order in data.items.where((o) => o.studentUid == studentUid)) order.id: order};
        _records.removeWhere((id, _) => !own.containsKey(id) || !_eligible(own[id]!));
        for (final order in own.values.where(_eligible)) {
          final existing = _records[order.id], before = _previous[order.id];
          final next = ReadyNotice(order, viewed: existing?.viewed ?? order.status == 'Completed');
          // A canonical Ready timestamp is immutable. An unexpected replacement
          // cannot create another transient alert or inherit an unrelated read flag.
          final sameEvent = existing == null || existing.eventId == next.eventId;
          _records[order.id] = sameEvent ? next : ReadyNotice(order, viewed: order.status == 'Completed');
          final firstObservation = _announced.add(next.eventId);
          if (_baseline && _foreground && sameEvent && firstObservation && order.status == 'Ready' &&
              before != null && (before.status == 'Pending' || before.status == 'Preparing')) {
            _alerts.add(order.id);
          }
        }
        _previous..clear()..addAll(own);
        _baseline = true; _connection = ReadyConnection.server;
        notifyListeners();
      }, onError: (Object _) {
        if (_disposed || generation != _generation) return;
        if (!sessionIsCurrent) { _expire(); return; }
        _connection = ReadyConnection.error; _alerts.clear(); notifyListeners();
      }, onDone: () {
        if (_disposed || generation != _generation) return;
        if (!sessionIsCurrent) { _expire(); return; }
        _connection = ReadyConnection.error; _alerts.clear(); notifyListeners();
      });
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _connection = ReadyConnection.error; _alerts.clear(); notifyListeners();
    }
  }

  List<String> takeAlerts() {
    final result = sessionIsCurrent && _foreground && _connection == ReadyConnection.server
      ? List<String>.of(_alerts) : <String>[];
    _alerts.clear(); return result;
  }
  void markViewed(String orderId) {
    if (!sessionIsCurrent) { _expire(); return; }
    final entry = _records[orderId];
    if (entry == null || entry.viewed) return;
    _records[orderId] = ReadyNotice(entry.order, viewed: true);
    _alerts.removeWhere((id) => id == orderId);
    notifyListeners();
  }
  void setForeground(bool value) {
    if (_disposed || _expired || _foreground == value) return;
    _foreground = value; _alerts.clear();
    // Resume establishes a fresh server baseline instead of replaying events
    // that may have happened while the app was backgrounded.
    if (value) { unawaited(refresh(rebaseline: true)); }
  }
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true; _generation++;
    unawaited(_subscription?.cancel());
    _records.clear(); _previous.clear(); _announced.clear(); _alerts.clear();
    super.dispose();
  }
}
