// Synthetic identity used only by main_emulator.dart, never production options.
const checkoutDemoProject = 'demo-smart-canteen';
const checkoutDemoAppName = 'stage2a02-emulator';
const checkoutDemoApiKey = 'demo-emulator-only';
const checkoutDemoAppId = '1:1234567890:android:0000000000000000';
const _checkoutDemoEndpoints = {'10.0.2.2:8080', '127.0.0.1:8080', 'localhost:8080'};

// The caller supplies actual runtime values. Tests can exercise release/profile
// and wrong-app cases without initializing Firebase or making network requests.
bool emulatorCheckoutAllowed({
  required bool debugMode,
  required bool emulatorEntryPoint,
  required bool flagEnabled,
  required bool emulatorsConnected,
  required String appName,
  required String projectId,
  required String apiKey,
  required String appId,
  required String? firestoreHost,
  required bool? sslEnabled,
}) => debugMode && emulatorEntryPoint && flagEnabled && emulatorsConnected &&
  appName == checkoutDemoAppName && projectId == checkoutDemoProject &&
  apiKey == checkoutDemoApiKey && appId == checkoutDemoAppId &&
  _checkoutDemoEndpoints.contains(firestoreHost) &&
  sslEnabled == false;
