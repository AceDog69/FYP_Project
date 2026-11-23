# Firebase V2 ordering pilot

Current target: **fyp-v2-fd5fb**. Android application ID: **com.example.my_fyp_app**.
This runbook replaces the old project's ordering-pilot instructions. It does not migrate old users or data.

## Project and activation checks

`android/app/google-services.json` supplies the Android default app configuration. The app's real-ordering
gate additionally requires `REAL_ORDERING_PILOT=true`, the exact `REAL_ORDERING_PROJECT=fyp-v2-fd5fb`,
matching default Auth and Firestore project IDs, Android, and the canonical TLS Firestore endpoint. Missing
flags, the former project `fyp-app-9d78a`, `demo-smart-canteen`, named emulator apps, non-Android platforms,
or a non-TLS/noncanonical endpoint remain disabled. The Android project uses Email/Password Authentication.

Build flags are a client-side feature gate, not an account allowlist. Once checkout-enabled Rules are deployed,
any authenticated Student account authorized by those Rules can submit simulated orders. The payment status is
still simulated. Keep menu deletion disabled; do not pass `REAL_MENU_DELETION_RULES_ACTIVE=true`.

## Rules candidate

- `firestore.rules` is the default closed policy: checkout and menu deletion are both disabled.
- `pilot/firestore.stage4b.rules` is the V2 pilot candidate: checkout is enabled, menu deletion is disabled,
  and it includes the current public queue count and preparation-stat projection validation.
- `pilot/firestore.ordering.rules` is a stale ordering-only candidate and must not be deployed.
- `pilot/firestore.stage4-integrated.rules` enables menu deletion and must not be used for this pilot.

The separate `firebase.v2.pilot.json` references only `pilot/firestore.stage4b.rules`; it contains no project
alias or other Firebase service. The repository has no `.firebaserc`, so commands must keep specifying the
project ID explicitly.

## Local verification commands

Generate/verify the review candidate locally; this command has no Firebase connection or deployment behavior:

```powershell
node scripts/prepare_ordering_pilot.mjs --project fyp-v2-fd5fb
node --test --test-concurrency=1 scripts/ordering_pilot.test.mjs
```

Run the complete Stage 4B emulator suite from `test/firebase` with Java 21 available in PowerShell:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
& node node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --project demo-smart-canteen --only auth,firestore --config ..\..\firebase.stage4b.json "node run_stage4b_tests.mjs"
Get-Content artifacts\stage4b-budget-diagnostics.json
```

This uses only the local `demo-smart-canteen` Auth and Firestore emulators. The emulator config selects the
same Stage 4B candidate file used by the V2 deployment config. Require a zero child exit code, all tests passing,
nonempty Firestore debug-log evidence, and an empty Rules-budget diagnostic list before considering deployment.

## Deployment commands for later review only

These commands were **not executed** during local verification. First select the V2 project in Console and
confirm the database and Authentication provider. Deploy the reviewed Rules only, with the project explicit:

```powershell
firebase deploy --only firestore:rules --project fyp-v2-fd5fb --config firebase.v2.pilot.json
```

To close checkout again, the default Rules candidate can be deployed explicitly:

```powershell
firebase deploy --only firestore:rules --project fyp-v2-fd5fb --config firebase.json
```

Neither command deploys indexes or other services. Do not use `--project fyp-app-9d78a` or a project alias.

## Android test commands for later review

No APK was built as part of migration verification. After Rules review/deployment, test on the Android emulator:

```powershell
flutter run --debug -d emulator-5554 -t lib/main.dart `
  --dart-define=REAL_ORDERING_PILOT=true `
  --dart-define=REAL_ORDERING_PROJECT=fyp-v2-fd5fb `
  --dart-define=STAGE4B_QUEUE_COUNTS=true
```

The app should log that ordering is enabled for `fyp-v2-fd5fb`. Use newly registered V2 Student and Vendor
accounts. Verify stall publication and menu creation, Vendor Orders queue initialization, simulated checkout,
sequential starts with parallel preparation, independent Ready/Completed transitions, historical estimate
updates, Student queue counts, and Ready notifications/account isolation. No old-project accounts or data are
available in the new project; no automatic migration is performed.
