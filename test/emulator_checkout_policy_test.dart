import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/services/emulator_checkout_policy.dart';
import 'package:my_fyp_app/services/order_repository.dart';

// Reading the normal repository's gate must not even access a Firebase client.
class _NoNetworkFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected Firebase access');
}

void main() {
  bool allowed({bool debug = true, bool entry = true, bool flag = true, bool connected = true,
    String name = checkoutDemoAppName, String project = checkoutDemoProject,
    String key = checkoutDemoApiKey, String id = checkoutDemoAppId,
    String? host = '10.0.2.2:8080', bool? ssl = false}) => emulatorCheckoutAllowed(
      debugMode: debug, emulatorEntryPoint: entry, flagEnabled: flag,
      emulatorsConnected: connected, appName: name, projectId: project,
      apiKey: key, appId: id, firestoreHost: host, sslEnabled: ssl);

  test('all required debug, entry point, flag, app and project combinations fail closed', () {
    for (final debug in [true, false]) {
      for (final entry in [true, false]) {
        for (final flag in [true, false]) {
          for (final name in [checkoutDemoAppName, '[DEFAULT]', 'another-app']) {
            for (final project in [checkoutDemoProject, 'production-project']) {
              expect(allowed(debug: debug, entry: entry, flag: flag, name: name, project: project),
                debug && entry && flag && name == checkoutDemoAppName && project == checkoutDemoProject,
                reason: '$debug / $entry / $flag / $name / $project');
            }
          }
        }
      }
    }
  });

  test('synthetic options, completed emulator setup and a local non-TLS endpoint are required', () {
    expect(allowed(connected: false), false);
    expect(allowed(key: 'real-project-key'), false);
    expect(allowed(id: 'real-project-app'), false);
    for (final host in ['10.0.2.2:8080', '127.0.0.1:8080', 'localhost:8080']) {
      expect(allowed(host: host), true);
    }
    for (final host in <String?>[null, 'firestore.googleapis.com', '10.0.2.2:443', '192.168.1.2:8080']) {
      expect(allowed(host: host), false);
    }
    expect(allowed(ssl: true), false); expect(allowed(ssl: null), false);
  });

  test('normal Firebase repository stays disabled without touching Firebase', () {
    expect(FirebaseOrderRepository(_NoNetworkFirestore(), () => 'student').canCheckout, false);
  });
}
