import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vendor_menu.dart';
import 'auth_repository.dart';

abstract class VendorMenuRepository {
  // Enable in the Firebase implementation only after the paired-deletion
  // security tests have actually passed and been reviewed. No runtime override.
  bool get canDeleteFood => false;
  Stream<MenuData<MenuCategory>> categories();
  Stream<MenuData<MenuFood>> foods();
  Future<void> saveCategory(String name, {MenuCategory? original});
  Future<void> saveFood(FoodDraft draft, {MenuFood? original});
  Future<void> setAvailable(MenuFood food, bool available);
  Future<void> deleteFood(MenuFood food);
}

class FirebaseVendorMenuRepository extends VendorMenuRepository {
  FirebaseVendorMenuRepository(this.db, this.currentUid, {bool Function()? deletionAllowed})
      : _deletionAllowed = deletionAllowed ?? _disabled;
  final FirebaseFirestore db;
  final String? Function() currentUid;
  final bool Function() _deletionAllowed;
  static bool _disabled() => false;
  @override
  bool get canDeleteFood => _deletionAllowed();
  bool _writing = false;
  String get _uid => currentUid() ?? (throw const AccountException('Please sign in again.'));
  DocumentReference<Map<String, dynamic>> _root(String uid) => db.collection('stalls').doc(uid);

  Stream<MenuData<T>> _watch<T>(String collection,
      T Function(String, String, Map<String, dynamic>) decode) async* {
    final uid = _uid;
    await for (final s in _root(uid).collection(collection).snapshots(includeMetadataChanges: true)) {
      if (currentUid() != uid) throw const AccountException('Your session changed.');
      if (s.metadata.hasPendingWrites) continue;
      yield MenuData(s.docs.map((d) => decode(uid, d.id, d.data())).toList(),
        cached: s.metadata.isFromCache);
    }
  }
  @override
  Stream<MenuData<MenuCategory>> categories() => _watch('menuCategories', MenuCategory.decode);
  @override
  Stream<MenuData<MenuFood>> foods() => _watch('menuFoods', MenuFood.decode);

  Future<void> _transaction(Future<void> Function(Transaction, String) body) async {
    if (_writing) throw const AccountException('A menu update is already in progress.');
    final uid = _uid;
    _writing = true;
    try {
      await db.runTransaction((tx) async {
        final u = await tx.get(db.collection('users').doc(uid));
        final stall = await tx.get(_root(uid));
        if (currentUid() != uid || u.data()?['role'] != 'vendor' ||
            u.data()?['stallSetupComplete'] != true || u.data()?['stallId'] != uid ||
            stall.data()?['ownerUid'] != uid) {
          throw const AccountException('A configured Vendor stall is required.');
        }
        await body(tx, uid);
      });
    } finally { _writing = false; }
  }

  void _version(DocumentSnapshot<Map<String, dynamic>> doc, int revision) {
    if (!doc.exists || doc.data()?['revision'] != revision) {
      throw const AccountException('This item changed. Cancel and reopen it before retrying.');
    }
  }

  @override
  Future<void> saveCategory(String name, {MenuCategory? original}) {
    final normalized = categoryName(name);
    if (categoryError(normalized) != null) throw const AccountException('Invalid category name.');
    final key = normalized.toLowerCase();
    final uid = _uid;
    final ref = original == null ? _root(uid).collection('menuCategories').doc()
        : _root(uid).collection('menuCategories').doc(original.id);
    return _transaction((tx, uid) async {
      final existing = await tx.get(ref);
      final nameRef = _root(uid).collection('menuCategoryNames').doc(key);
      final duplicate = await tx.get(nameRef);
      if (original != null) _version(existing, original.revision);
      if (duplicate.exists && duplicate.data()?['categoryId'] != ref.id) {
        throw const AccountException('A category with this name already exists.');
      }
      final oldKey = existing.data()?['nameKey'] as String?;
      if (oldKey != null && oldKey != key) {
        tx.delete(_root(uid).collection('menuCategoryNames').doc(oldKey));
      }
      if (!duplicate.exists) tx.set(nameRef, {'vendorUid': uid, 'categoryId': ref.id});
      final values = {'vendorUid': uid, 'name': normalized, 'nameKey': key,
        'revision': (original?.revision ?? 0) + 1, 'updatedAt': FieldValue.serverTimestamp()};
      if (original == null) {
        tx.set(ref, {...values, 'createdAt': FieldValue.serverTimestamp()});
      } else { tx.update(ref, values); }
    });
  }

  @override
  Future<void> saveFood(FoodDraft draft, {MenuFood? original}) {
    final uid = _uid;
    final ref = original == null ? _root(uid).collection('menuFoods').doc()
        : _root(uid).collection('menuFoods').doc(original.id);
    return _transaction((tx, uid) async {
      final existing = await tx.get(ref);
      final category = await tx.get(_root(uid).collection('menuCategories').doc(draft.categoryId));
      if (original != null) _version(existing, original.revision);
      if (!category.exists || category.data()?['vendorUid'] != uid) {
        throw const AccountException('Select an existing menu category.');
      }
      final values = {...draft.fields, 'vendorUid': uid,
        'revision': (original?.revision ?? 0) + 1, 'updatedAt': FieldValue.serverTimestamp()};
      if (original == null) {
        tx.set(ref, {...values, 'createdAt': FieldValue.serverTimestamp()});
      } else { tx.update(ref, values); }
      // Exactly one canonical active membership per food ID. Reassignment
      // replaces its category atomically, leaving no old active reference.
      tx.set(_root(uid).collection('menuMemberships').doc(ref.id),
        {'vendorUid': uid, 'categoryId': draft.categoryId});
    });
  }

  @override
  Future<void> setAvailable(MenuFood food, bool available) => saveFood(FoodDraft(
    name: food.draft.name, description: food.draft.description,
    priceSen: food.draft.priceSen, categoryId: food.draft.categoryId,
    pictureId: food.draft.pictureId, available: available), original: food);

  @override
  Future<void> deleteFood(MenuFood food) async {
    if (!canDeleteFood) {
      throw const AccountException('Deletion awaits reviewed local security tests.');
    }
    await _transaction((tx, uid) async {
      final ref = _root(uid).collection('menuFoods').doc(food.id);
      final existing = await tx.get(ref);
      _version(existing, food.revision);
      final membershipRef = _root(uid).collection('menuMemberships').doc(food.id);
      final membership = await tx.get(membershipRef);
      final categoryId = existing.data()?['categoryId'];
      if (existing.data()?['vendorUid'] != uid || categoryId != food.draft.categoryId ||
          membership.data()?['vendorUid'] != uid || membership.data()?['categoryId'] != categoryId) {
        throw const AccountException('Food membership could not be verified. Reload the menu.');
      }
      final category = await tx.get(_root(uid).collection('menuCategories').doc(food.draft.categoryId));
      if (category.data()?['vendorUid'] != uid) {
        throw const AccountException('The food category could not be verified. Reload the menu.');
      }
      // Reading both documents makes concurrent edits/reassignment/deletion
      // retry and recheck the displayed revision before any delete is committed.
      // No order path is read or written; future orders need immutable snapshots.
      tx.delete(ref);
      tx.delete(membershipRef);
    });
  }
}
