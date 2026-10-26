# Controlled real-Firebase ordering pilot and private APK

26 October 2026 (Asia/Singapore). Branch `feature/real-firebase-apk-pilot`.
Base verified through GitHub: `017fd9fe78a0e6116544c4246cf52eb959280218`.
The delivery report supplies the exact final candidate SHA.

This guide prepares a private supervisor demo, not a Play Store release. No live project connection,
deployment, production data modification, APK build or publication was performed in Cloud.
The existing package `com.example.my_fyp_app`, Firebase configuration and debug-key release signing are unchanged.
The main manifest already includes INTERNET permission for release builds; debug-only cleartext remains isolated.

## Activation and security boundary

Normal `lib/main.dart` is still disabled by default. The existing FirebaseOrderRepository also remains
disabled. A small wrapper overrides only `canCheckout` and `canProcessOrders` when ALL apply:

- `REAL_ORDERING_PILOT=true` and `REAL_ORDERING_PROJECT=fyp-app-9d78a` were deliberately passed at build time.
- Actual Firestore AND Auth apps are the default app and both actually identify project `fyp-app-9d78a`.
- This is native Android, with Firestore host `firestore.googleapis.com` and TLS enabled.

The normal entrypoint explicitly binds that TLS endpoint before repository use only when the flag,
declaration and actual project agree. Wrong projects, named emulator apps, non-Android platforms,
missing flags and local/non-TLS endpoints fail closed. Both debug pilot runs and release APKs can opt in.
The emulator entrypoint, launcher, synthetic identity and its separate gate are byte-for-byte unchanged.

All checkout/FCFS transactions are inherited unchanged. Two distinct foods, 1–20 units each, integer sen,
one stall, canonical snapshots, sequential tickets, idempotency, ownership and FCFS remain enforced by Rules.
Queue/ETA and in-app Ready notifications continue to read the existing authorized streams without new flags
or services. No FCM, Functions, Storage, paid resource, billing change or real payment is introduced.

**The app flag is not an authorization boundary.** Deploying the pilot Rules opens secure checkout for
all otherwise authorized users of this project, including direct clients; it is not an account allowlist.
Use controlled demo accounts and keep the APK private. Vendor processing remains owner-only and FCFS.
Food/Category Delete stays disabled in both app and Rules. Rolling back Rules closes checkout for every
client, including an already installed pilot APK. Existing valid Vendor progression Rules are preserved;
to stop Vendor processing in the app, replace the APK with a normal build as well.

## Reviewable Rules candidate

- Default `firestore.rules`: checkout false, menu deletion false, unchanged.
- Candidate `pilot/firestore.ordering.rules`: checkout true, menu deletion false.
- Explicit `firebase.pilot.json`: references only that candidate, no hosting/index deployment.
- `scripts/prepare_ordering_pilot.mjs`: generates those two files, never connects to Firebase or deploys.

The candidate is otherwise byte-identical to the default Rules. The existing checkout/FCFS/queue security
tests already exercise that exact gate replacement. Their malicious price/snapshot/ownership/Ready forgery,
counter/size/concurrency and queue cases apply to precisely the same candidate bytes. The new Node checks
verify this equivalence, not the success of unexecuted emulator tests. Full security regression and zero budget
diagnostics remain mandatory before deployment; no new proof is inferred from source comparison alone.

## Cloud results and Windows prerequisites

Cloud executed **16/16 Node tests**, `git diff --check`, source scope checks and a lexical Dart delimiter audit.
Five Node cases cover candidate equality, equivalence to tested gate substitution, refused generation inputs,
fixed project and config. Eleven existing launcher/budget-detector/transport cases also passed.
The lexical audit is not parsing/compilation. Flutter/Dart, Firebase CLI/emulators and Android are unavailable
here, so Flutter analyze/tests, actual emulator Rules evaluation/budget results, APK build/sign/install and live
acceptance were **not executed**. No SDK download or dependency upgrade was attempted.

Four new Flutter tests cover policy defaults/identity/endpoint combinations and a test-double controller journey
through simulated checkout, FCFS, queue/ETA, Ready/Completed and wrong Vendor rejection. The test-double journey
is not Firestore authorization proof. All previous 169 Flutter test sources and 104-case security sources are
preserved from the verified base. Their reported passes are earlier Windows evidence, not candidate Cloud results.

## 1. Verify source and run tests (Windows CMD)

Save any personal uncommitted work first. Open CMD at the existing repository:

```bat
cd /d C:\path\to\FYP_Project
git status
git fetch origin
git switch feature/real-firebase-apk-pilot
git pull --ff-only origin feature/real-firebase-apk-pilot
git rev-parse HEAD
flutter pub get
flutter analyze
flutter test test/real_ordering_pilot_test.dart
flutter test
node scripts/prepare_ordering_pilot.mjs --project fyp-app-9d78a
node --test --test-concurrency=1 scripts/ordering_pilot.test.mjs scripts/checkout_demo_launcher.test.mjs test/firebase/checkout_budget.test.mjs test/firebase/checkout_transport.test.mjs
git diff --exit-code -- firestore.rules pilot/firestore.ordering.rules firebase.pilot.json
```

Match HEAD to the delivery SHA. Every command must pass; if regeneration changes the committed candidate,
stop and review the discrepancy. Stop manually running local demo emulators before the complete security suite:

```bat
cd test\firebase
npm ci
npm run test:queue
type artifacts\student-queue-budget-diagnostics.json
cd ..\..
```

This suite uses synthetic emulator projects, not `fyp-app-9d78a`. Require all cases passing, childExitCode zero,
an empty/zero budgetDiagnostics result and the runner's log-evidence check passing. An expected denial caused
only by budget exhaustion is a failure. Preserve the output as local acceptance evidence. The historical Chrome
test stall remains a separate gap; it is not claimed passed here. Do not deploy if any prerequisite fails.

## 2. Back up the actually deployed Rules before manually enabling anything

No deployment command in this guide has been executed by Cloud. After the checks pass and you review the
single-gate diff, use Firebase Console and select **fyp-app-9d78a** explicitly. Open Firestore Database → Rules.
Copy the entire currently published Rules text (not the proposed editor draft) into a local file outside Git:

```bat
mkdir C:\SmartCanteenPilotBackup
notepad C:\SmartCanteenPilotBackup\firestore.before-pilot.rules
```

Save the published text. Also record project ID, published date/release identifier if shown, capture the Console
view and retain the previous accepted normal APK. Do not assume the deployed text equals the checked-in file.
Check the saved backup contains the current checkout false and deletion false gates. Verify the file is complete
and nonempty before proceeding. Keep personal data, access tokens and signing keys outside Git.

Create `C:\SmartCanteenPilotBackup\firebase.rollback.json` in Notepad containing exactly:

```json
{"firestore":{"rules":"firestore.before-pilot.rules"}}
```

This backup is a Rules rollback, not a data backup. The pilot writes real demo order/counter/request documents;
closing a gate does not remove them. Do not erase counters, change tickets, rewrite snapshots or delete account
data as a rollback shortcut. Leave unrelated existing project data intact.

## 3. Explicit manual Rules deployment and verification

Use your already authorized Firebase CLI login; confirm the account and project in Console/CLI first:

```bat
firebase projects:list
firebase deploy --only firestore:rules --project fyp-app-9d78a --config firebase.pilot.json
```

Run the deploy only after local test evidence and candidate review, with the saved rollback ready.
Do not use a broad `firebase deploy`, omit `--project`, deploy indexes/hosting, or change billing.
Check CLI success and then reopen Console **fyp-app-9d78a → Firestore → Rules**. Compare the published text
against the committed candidate: checkout true; menu deletion false; all other expressions unchanged.
Record deployment time/Rules release and candidate SHA. A CLI exit without Console verification is insufficient.
Use the controlled pilot app below to verify a valid order and progression. Failed writes should be investigated
through their errors; never widen Rules to get a demo through.

## 4. Pixel 6 real-Firebase pilot (two clients)

Stop local demo emulators. These runs use real Firebase over the Internet, with `lib/main.dart`, not
`main_emulator.dart`. Use a dedicated synthetic Student and Vendor in the real project; simulated payment
still means no money is charged. Existing accounts/stalls require no migration.

```bat
flutter devices
flutter run --debug -d emulator-5554 -t lib/main.dart --dart-define=REAL_ORDERING_PILOT=true --dart-define=REAL_ORDERING_PROJECT=fyp-app-9d78a
```

The startup log must say `Real ordering pilot: enabled; project: fyp-app-9d78a`. A wrong/disabled result means
stop, check actual configuration and rebuild; do not bypass the guard. The existing `google-services.json`
project and package must match the specified project and `com.example.my_fyp_app`.
Run a second client for Vendor in another CMD, replacing the device ID with its actual ID:

```bat
flutter run --debug -d emulator-5556 -t lib/main.dart --dart-define=REAL_ORDERING_PILOT=true --dart-define=REAL_ORDERING_PROJECT=fyp-app-9d78a
```

1. Vendor signs in, confirms its own stall/menu and opens the stall.
2. Student signs in, selects at most two distinct foods, confirms simulated payment twice, and records the
   actual sequential ticket numbers. Existing real counters may already be nonzero; never reset them to force #1.
3. Vendor can prepare only the earliest eligible ticket with the single slot; Student sees live Preparing/ETA.
4. Vendor marks Ready; foreground Student sees the actual stall/ticket alert and Profile badge. Tap View or
   Profile → Notifications → Details; verify exact items/total and current status.
5. Vendor completes collection; Student sees Completed/history. Test the second ticket and session isolation.
6. Confirm normal builds without the defines still disable Confirm Order/Vendor processing; wrong project
   declaration also stays disabled. Verify Food/Category Delete remains disabled in the pilot.
7. Test offline/retry without manufacturing confirmed tickets, duplicate taps/recovery, Logout and account
   switching. Ready viewed state is session-local and notifications are in-app only, as in Stage 3C.

Keep this pilot private and small. Reads/writes count toward the existing Firebase project's free quotas;
no paid service or billing change is required by this implementation.

## 5. Private release APK, installation and verification

Build only after the previous acceptance passes. No production/public APK is built or published by this task.
This is your deliberate local private demo build with the existing debug signing configuration:

```bat
flutter build apk --release -t lib/main.dart --dart-define=REAL_ORDERING_PILOT=true --dart-define=REAL_ORDERING_PROJECT=fyp-app-9d78a
certutil -hashfile build\app\outputs\flutter-apk\app-release.apk SHA256
adb devices
adb -s emulator-5554 install -r build\app\outputs\flutter-apk\app-release.apk
adb -s emulator-5554 shell am start -n com.example.my_fyp_app/.MainActivity
```

Repeat install/launch for the second device if required. Record APK SHA256, source SHA, flags and signing
certificate used. In Android Studio **Build → Analyze APK** inspect the manifest application ID
`com.example.my_fyp_app`, Smart Canteen branding and INTERNET permission. If SDK command-line tools are installed:

```bat
"%LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest\bin\apkanalyzer.bat" manifest application-id build\app\outputs\flutter-apk\app-release.apk
adb -s emulator-5554 logcat -s flutter
```

Confirm the runtime startup line identifies the exact real project and enabled pilot, verify real sign-in,
and repeat the complete simulated order journey on the installed release APK. Debug-mode acceptance alone
does not establish release acceptance. A signature mismatch during install needs investigation; do not uninstall
blindly since that clears local session state. This signing arrangement is for a private demo, not Play Store use.

To create the ordinary default-disabled private APK, omit BOTH defines:

```bat
flutter build apk --release -t lib/main.dart
```

APK builds use the same output filename. Rename/copy the accepted pilot and normal artifacts to clearly
labelled local locations and record hashes before another build overwrites them. Do not commit APKs or keys.

## Rollback and stop

If the live pilot fails, first close checkout using the exact saved pre-pilot Rules:

```bat
firebase deploy --only firestore:rules --project fyp-app-9d78a --config C:\SmartCanteenPilotBackup\firebase.rollback.json
```

Verify the restored published Rules in Console against the backup. If the backup is missing, do not improvise
an unrestricted file: review/deploy the checked-in closed default using explicit `--config firebase.json`
and the same project/only-rules arguments only after comparing it with known accepted behavior.
Install a normal default-disabled APK to disable client checkout AND Vendor processing. Existing confirmed
history is retained; decide how to finish any outstanding demo orders before ending the pilot.
Do not change billing, deploy Functions, publish publicly or start another feature. Record exact acceptance
results/limitations and stop for supervisor review.
