import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/catalog.dart';
import '../models/vendor_menu.dart';
import 'auth_repository.dart';

abstract class CatalogRepository {
  Stream<MenuData<CatalogStall>> stalls();
  Stream<MenuData<CatalogStall>> stall(String vendorUid);
  Stream<MenuData<MenuCategory>> categories(String vendorUid);
  Stream<MenuData<MenuFood>> foods(String vendorUid);
}

/// Only deliberately public fields are selected, never a spread of source data.
Map<String, dynamic> publicStallFields(String uid, Map<String, dynamic> source) => {
  'vendorUid': uid, 'name': source['name'], 'category': source['category'],
  'preparationMinutes': source['preparationMinutes'], 'status': source['status'],
  if (source.containsKey('pictureId')) 'pictureId': source['pictureId'],
};

class FirebaseCatalogRepository extends CatalogRepository {
  FirebaseCatalogRepository(this.db, this.currentUid);
  final FirebaseFirestore db;
  final String? Function() currentUid;

  Stream<MenuData<T>> _watch<T>(Query<Map<String, dynamic>> query,
      T Function(String, Map<String, dynamic>, bool) decode) async* {
    final session = currentUid();
    if (session == null) throw const AccountException('Please sign in again.');
    await for (final s in query.snapshots(includeMetadataChanges: true)) {
      if (currentUid() != session) throw const AccountException('Your session changed.');
      if (s.metadata.hasPendingWrites) continue;
      yield MenuData(s.docs.map((d) => decode(d.id, d.data(), s.metadata.isFromCache)).toList(),
        cached: s.metadata.isFromCache);
    }
  }

  @override
  Stream<MenuData<CatalogStall>> stalls() => _watch(db.collection('publicStalls'),
    (id, d, cached) => CatalogStall.decode(id, d, cached: cached));

  @override
  Stream<MenuData<CatalogStall>> stall(String vendorUid) async* {
    final session = currentUid();
    if (session == null) throw const AccountException('Please sign in again.');
    await for (final s in db.collection('publicStalls').doc(vendorUid)
        .snapshots(includeMetadataChanges: true)) {
      if (currentUid() != session) throw const AccountException('Your session changed.');
      if (s.metadata.hasPendingWrites) continue;
      yield MenuData(s.exists ? [CatalogStall.decode(s.id, s.data()!, cached: s.metadata.isFromCache)] : [],
        cached: s.metadata.isFromCache);
    }
  }

  @override
  Stream<MenuData<MenuCategory>> categories(String vendorUid) => _watch(
    db.collection('stalls').doc(vendorUid).collection('menuCategories'),
    (id, d, _) => MenuCategory.decode(vendorUid, id, d));

  @override
  Stream<MenuData<MenuFood>> foods(String vendorUid) => _watch(
    db.collection('stalls').doc(vendorUid).collection('menuFoods').where('available', isEqualTo: true),
    (id, d, _) => MenuFood.decode(vendorUid, id, d));

  /// Owner-driven, idempotent publication of existing stalls. No student can
  /// backfill another vendor. Runs against the server, never an offline queue.
  Future<void> publishOwnStall() async {
    final uid = currentUid();
    if (uid == null) throw const AccountException('Please sign in again.');
    await db.runTransaction((tx) async {
      final user = await tx.get(db.collection('users').doc(uid));
      final source = await tx.get(db.collection('stalls').doc(uid));
      final target = db.collection('publicStalls').doc(uid);
      final listing = await tx.get(target);
      if (currentUid() != uid || user.data()?['role'] != 'vendor' ||
          user.data()?['stallSetupComplete'] != true || user.data()?['stallId'] != uid ||
          source.data()?['ownerUid'] != uid) {
        throw const AccountException('A configured Vendor stall is required.');
      }
      final fields = publicStallFields(uid, source.data()!);
      final previous = listing.data();
      if (previous != null && previous.length == fields.length + 1 &&
          fields.entries.every((e) => previous[e.key] == e.value)) return;
      tx.set(target, {...fields, 'updatedAt': FieldValue.serverTimestamp()});
    });
  }
}
