import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/services/real_ordering_pilot.dart';
import 'package:my_fyp_app/services/checkout_controller.dart';
import 'package:my_fyp_app/services/student_cart.dart';
import 'package:my_fyp_app/services/ready_notifications.dart';
import 'package:my_fyp_app/services/auth_repository.dart';
import 'package:my_fyp_app/models/queue_progress.dart';
import 'support/catalog_fixtures.dart';
import 'support/fake_catalog_repository.dart';
import 'support/fake_order_repository.dart';

void main() {
  bool allowed({bool enabled = false, String declared = '', String project = orderingPilotProject,
    String authProject = orderingPilotProject, String app = '[DEFAULT]', String authApp = '[DEFAULT]',
    bool android = true, String? host = 'firestore.googleapis.com', bool? ssl = true}) => realOrderingPilotAllowed(
      enabled: enabled, declaredProject: declared, actualProject: project, authProject: authProject,
      appName: app, authAppName: authApp, android: android, firestoreHost: host, sslEnabled: ssl);
  test('ordinary builds remain disabled including the authorized real project', () {
    expect(allowed(), false); expect(allowed(declared: orderingPilotProject), false);
  });
  test('both deliberate build defines and actual runtime identity are required', () {
    for (final enabled in [true, false]) {
      for (final declared in ['', orderingPilotProject, 'other', 'demo-smart-canteen']) {
        for (final project in [orderingPilotProject, 'other', 'demo-smart-canteen']) {
          expect(allowed(enabled: enabled, declared: declared, project: project),
            enabled && declared == orderingPilotProject && project == orderingPilotProject);
        }
      }
    }
  });
  test('wrong Auth identity, named app, platform or emulator endpoint fails closed', () {
    expect(allowed(enabled: true, declared: orderingPilotProject), true);
    expect(allowed(enabled: true, declared: orderingPilotProject, authProject: 'other'), false);
    expect(allowed(enabled: true, declared: orderingPilotProject, app: 'stage2a02-emulator'), false);
    expect(allowed(enabled: true, declared: orderingPilotProject, authApp: 'other'), false);
    expect(allowed(enabled: true, declared: orderingPilotProject, android: false), false);
    for (final host in <String?>[null, 'localhost:8080', '10.0.2.2:8080', 'other.googleapis.com']) {
      expect(allowed(enabled: true, declared: orderingPilotProject, host: host), false);
    }
    for (final ssl in <bool?>[null, false]) {
      expect(allowed(enabled: true, declared: orderingPilotProject, ssl: ssl), false);
    }
  });
  test('menu deletion requires both the explicit Rules activation and valid ordering pilot', () {
    expect(realMenuDeletionPilotAllowed(rulesExplicitlyActivated: false, orderingPilotAllowed: true), false);
    expect(realMenuDeletionPilotAllowed(rulesExplicitlyActivated: true, orderingPilotAllowed: false), false);
    expect(realMenuDeletionPilotAllowed(rulesExplicitlyActivated: true, orderingPilotAllowed: true), true);
  });
  test('pilot eligibility feeds the existing simulated checkout FCFS queue and Ready controllers', () async {
    // Test doubles verify controller integration, not Firestore authorization.
    final enabled = allowed(enabled: true, declared: orderingPilotProject);
    final catalog = FakeCatalogRepository(); populate(catalog);
    final student = FakeOrderRepository(() => 'student')..enabled = enabled;
    final vendor = FakeOrderRepository(() => 'alpha')..processingEnabled = enabled;
    final cart = StudentCart('student', catalog), checkout = CheckoutController(cart, student);
    final notices = ReadyNotifications(studentUid: 'student', repository: student, currentUid: () => 'student');
    addTearDown(() { notices.dispose(); checkout.dispose(); cart.dispose(); student.dispose(); vendor.dispose(); catalog.dispose(); });
    cart.add(await catalog.selection('alpha', 'bowl'), 2); await Future<void>.delayed(Duration.zero);
    final receipt = await checkout.confirm('ewallet'); expect(receipt, isNotNull);
    expect(receipt!.order.totalSen, 1700); expect(receipt.order.ticket, 1);
    await Future<void>.delayed(Duration.zero);
    vendor.receipts[receipt.order.id] = receipt;
    for (final status in ['Preparing', 'Ready', 'Completed']) {
      await vendor.advance(vendor.receipts[receipt.order.id]!.order);
      final updated = vendor.receipts[receipt.order.id]!;
      student.receipts[updated.order.id] = updated; student.emit(); await Future<void>.delayed(Duration.zero);
      expect(updated.order.status, status);
      if (status == 'Preparing') {
        final estimate = estimateQueue(updated.order, vendor.publicProgress['alpha'], updated.order.preparingAt!.toDate());
        expect(estimate.ahead, 0); expect(estimate.minutes, 15);
      }
      if (status == 'Ready') expect(notices.takeAlerts(), [updated.order.id]);
    }
    expect(notices.notices.single.order.status, 'Completed'); expect(notices.takeAlerts(), isEmpty);
    final outsider = FakeOrderRepository(() => 'other')..processingEnabled = true;
    addTearDown(outsider.dispose); outsider.receipts[receipt.order.id] = receipt;
    await expectLater(outsider.advance(receipt.order), throwsA(isA<AccountException>()));
  });
}
