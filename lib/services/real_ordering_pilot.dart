import 'package:flutter/foundation.dart';
import 'firebase_auth_repository.dart';
import 'order_repository.dart';
import 'vendor_menu_repository.dart';

const orderingPilotProject = 'fyp-app-9d78a';

// Defaults fail closed, including a flag accidentally supplied to another project.
bool realOrderingPilotAllowed({required bool enabled, required String declaredProject,
  required String actualProject, required String authProject, required String appName,
  required String authAppName, required bool android, required String? firestoreHost,
  required bool? sslEnabled}) => enabled && android && declaredProject == orderingPilotProject &&
  actualProject == orderingPilotProject && authProject == orderingPilotProject &&
  appName == '[DEFAULT]' && authAppName == '[DEFAULT]' &&
  firestoreHost == 'firestore.googleapis.com' && sslEnabled == true;

bool realMenuDeletionPilotAllowed({required bool rulesExplicitlyActivated,
  required bool orderingPilotAllowed}) => rulesExplicitlyActivated && orderingPilotAllowed;

/// Only normal main.dart constructs this repository; main_emulator.dart is unchanged.
class RealOrderingPilotAuthRepository extends FirebaseAuthRepository {
  RealOrderingPilotAuthRepository(super.auth, super.db);
  bool get _orderingAllowed => realOrderingPilotAllowed(
    enabled: const bool.fromEnvironment('REAL_ORDERING_PILOT', defaultValue: false),
    declaredProject: const String.fromEnvironment('REAL_ORDERING_PROJECT', defaultValue: ''),
    actualProject: db.app.options.projectId, authProject: auth.app.options.projectId,
    appName: db.app.name, authAppName: auth.app.name,
    android: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
    firestoreHost: db.settings.host, sslEnabled: db.settings.sslEnabled,
  );
  late final OrderRepository _pilotOrders = _PilotOrders(db, () => uid, () =>
    _orderingAllowed);
  late final VendorMenuRepository _pilotMenu = FirebaseVendorMenuRepository(db, () => uid,
    deletionAllowed: () => realMenuDeletionPilotAllowed(
      rulesExplicitlyActivated: const bool.fromEnvironment(
        'REAL_MENU_DELETION_RULES_ACTIVE', defaultValue: false),
      orderingPilotAllowed: _orderingAllowed));
  @override
  OrderRepository get orderRepository => _pilotOrders;
  @override
  VendorMenuRepository get menuRepository => _pilotMenu;
}

class _PilotOrders extends FirebaseOrderRepository {
  _PilotOrders(super.db, super.currentUid, this.allowed);
  final bool Function() allowed;
  @override
  bool get canCheckout => allowed();
  @override
  bool get canProcessOrders => allowed();
}
