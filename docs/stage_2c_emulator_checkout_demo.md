# Stage 2C — checkout-enabled LOCAL Android demo

This is the final Android acceptance setup, **not a production release**.
Branch: `feature/stage-2c-checkout-orders`. Starting HEAD verified as
`7c9ee91618a73b77a858900e84919b250ef7d030`. Use the final commit SHA from the
delivery report/GitHub history when resuming.

## Accepted proof and remaining checks

User Windows results, 22 October 2026: **70/70** checkout security cases passed,
**zero** Rules-budget diagnostics, budget unit test passed, transport/helper tests
**3/3** passed. Flutter previously passed analysis and **67/67** tests. One/two
foods, three/four/five rejection, malformed snapshots, security boundaries,
sequential concurrent tickets, same-ID recovery and offline safety passed.
These are user-reported results at the starting commit, not Cloud reruns.

This increment adds only emulator activation, a launcher, tests and handover.
Checkout transaction code, two-food limit, quantities 1–20, integer-sen totals,
simulated payment, Cart recovery, immutable snapshots/tickets and security checks
are unchanged. No Stage 3 queue/status/ETA/notification work is included.

## Safety boundaries

- Checked-in `firestore.rules` retains `checkoutWritesEnabled() == false`.
  Both Vendor deletion gates stay false, even in the generated demo rules.
- `main.dart` and the normal `FirebaseOrderRepository` are unchanged and disabled.
  A private subclass exists only in `main_emulator.dart`, after Auth/Firestore
  emulator configuration. No global flag enables the production repository.
- Its gate requires **all**: actual `kDebugMode`; emulator entry point/setup;
  exact synthetic named app `stage2a02-emulator`; project `demo-smart-canteen`;
  synthetic app options; explicit `EMULATOR_CHECKOUT=true`; local Firestore endpoint
  on port 8080 with TLS disabled. Profile/release, default/foreign apps, production
  projects, missing flag or non-local endpoints fail closed. No health/connection
  success is inferred from this gate: writes still require a server acknowledgement.
- The launcher exposes only `emulators:start --project demo-smart-canteen --only
  auth,firestore`. Any other project or arbitrary Firebase arguments are refused.
  No deploy operation, admin permissions or Windows execution-policy change is used.
- Files are created in a unique OS temporary directory named
  `smart-canteen-checkout-demo-*`, **outside the repository**. A temporary
  `.firebaserc` defaults only to the demo. There is deliberately no default
  `firebase.json` there. Production Firebase config is never rewritten.
- The only Rules edit is the exact one-function `false` → `true` checkout gate.
  Missing/duplicate/already-open gates or open Vendor deletion gates stop generation.
  Readback and reverse comparison prove all other bytes unchanged. The CLI uses
  the temporary config explicitly; logs are also outside the repository.
- Generated names have extra `.gitignore` protection if copied into the repo.
  Do not copy, commit or deploy them. Closing the normal launcher removes its
  directory. Forced process/window termination may leave an isolated temporary
  folder; it is not production configuration and cannot enable ordinary app runs.

The independent `test:checkout` command still reads the closed production rules
and opens only its own in-memory candidate. Stop the manual demo before running
it: both use ports 8080/9099.

## 1. Prepare Windows once

Use the existing Windows Flutter, Node/npm, Java and Android Studio setup. No
Blaze, paid service, Firebase login or production project is needed. Open PowerShell
in your `FYP_Project` repository folder. Run:

```powershell
git fetch origin
git switch feature/stage-2c-checkout-orders
git pull --ff-only
git rev-parse HEAD
flutter pub get --enforce-lockfile
flutter analyze
flutter test
Push-Location test/firebase
npm ci
Pop-Location
node scripts/checkout_demo_launcher.test.mjs
```

Compare HEAD with the delivery report. Stop on divergence; do not merge/rebase or
force-push. New Flutter policy tests must pass along with the earlier regressions.
The launcher checks the CLI installed by `npm ci`; it does not download tooling.

If rerunning security proof before Android acceptance:

```powershell
Push-Location test/firebase
node checkout_budget.test.mjs
node checkout_transport.test.mjs
npm run test:checkout
Pop-Location
```

Expect 70 security passes and zero budget diagnostics. This command ends its own
emulators; then start the manual demo below. Never run both sets simultaneously.

## 2. Terminal A — start checkout-enabled local emulators

Close any previous local emulator process with Ctrl+C. From the repository root:

```powershell
.\scripts\start_checkout_demo.cmd
```

Equivalent from CMD: `scripts\start_checkout_demo.cmd`.
The Node entry is also usable as `node scripts/start_checkout_demo.mjs`.
An explicit `--project demo-smart-canteen` is allowed, but unnecessary. Do not add
project aliases, config paths, import/export or other Firebase arguments.

Wait for Firebase to report **all emulators ready**. The launcher prints the
demo project and temporary directory. Auth listens at `127.0.0.1:9099`; Firestore
at `127.0.0.1:8080`. Android's `10.0.2.2` reaches your Windows host. If a port is
occupied, stop the previous demo you started; this launcher never kills unrelated
Windows processes. Keep this terminal open throughout acceptance.

## 3. Terminal B — Pixel 6 debug app with explicit checkout flag

Start Pixel 6 in Android Studio Device Manager. Open another PowerShell in the
same repository folder and run:

```powershell
flutter devices
flutter run --debug -d <pixel-6-emulator-id> -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2 --dart-define=EMULATOR_CHECKOUT=true
```

Replace `<pixel-6-emulator-id>` with the Android ID from `flutter devices`, such as
`emulator-5554` (use your actual ID). Console should print `Local demo checkout:
enabled`. Use this entry point, not `main.dart`. A flag change requires stopping
and starting Flutter again; hot reload is not a mode switch.

To prove the ordinary emulator run stays closed, stop Flutter with `q` and rerun
without the checkout flag:

```powershell
flutter run --debug -d <pixel-6-emulator-id> -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2
```

Console should report disabled, and Confirm Order must be disabled. Stop this
run and restart the flag-enabled command before continuing. Do not run the
production entry point to test this guard; the focused policy tests cover it.

## 4. Demonstrate checkout and Vendor receipt

Use newly created **synthetic local** accounts/passwords only. These live in the
demo emulators; do not enter production credentials or personal test data.

1. Register a Vendor in the app, complete Stall Setup, create two Menu Categories
   and three available foods with predefined pictures/integer RM prices. Open the
   stall on Dashboard. Revisit Dashboard if needed so its public listing appears.
2. Log out, register a Student, open the stall and add one or two distinct foods.
   Adjust quantities within 1–20; verify the RM total. A third distinct food must
   be rejected without discarding the Cart.
3. Open Cart → Review Checkout. Check the two-food limit, itemized price/quantity,
   total and **simulated payment/no money charged** wording. Choose a simulated
   method and press Confirm Order once. Pending/repeated taps must not duplicate
   an order. Wait for the server-confirmed receipt/ticket; only then should the
   matching Cart clear. My Orders → View Details must retain the snapshots.
4. Record the first ticket. Another confirmed checkout at the same stall must use
   the next ticket. A draft/cancelled request does not consume a ticket. An unknown
   result retains the same ID/Cart for Retry Same Checkout or safe discard; do not
   create a fresh identity to work around a failed acknowledgement.
5. Log out and log in as the Vendor. Open Orders. The confirmed Pending orders,
   tickets, quantities, immutable totals and item snapshots must be present. This
   one-device sequence demonstrates receipt, not a simultaneous live arrival.
6. For a genuine live-inbox demonstration, run a **second Android emulator**, log
   in the Vendor there and leave Orders visible. Run the same flag-enabled Flutter
   command in terminal C with the second device's ID. On Pixel 6, log in the
   Student and confirm another order. The Vendor inbox should update automatically
   without leaving the tab, in ticket order. Both apps share the same local demo
   project. Do not substitute a production build/device or browser test setup.
7. Verify Menu/Settings/Profile/Logout and both deletion-disabled labels still
   work. Vendor Orders remains read-only: no Stage 3 preparation/status/queue
   controls are added by this increment.

Do not use actual payments. If a server/network acknowledgement fails, keep the
request/Cart and use its existing retry/discard flow. Security proof is not a
replacement for Android acceptance: report exact errors and stop on a failed
invariant rather than changing Rules/gates during the demonstration.

## 5. Stop safely

1. Stop each Flutter run with `q` in its terminal (or close its debug app).
2. In terminal A press Ctrl+C once. Wait for Firebase shutdown and the launcher
   message `Temporary checkout demo files removed.` If CMD asks whether to
   terminate its batch job, allow the Firebase/Node shutdown to finish first.
3. The default demo has no persistence import/export; stopping emulators discards
   synthetic accounts/orders. Next start is a fresh demo. No production data is
   deleted. Do not use system-wide process-kill or execution-policy commands.
4. `git status --short` should show no generated rules/config/data. If the window
   was forcibly closed, only the printed `smart-canteen-checkout-demo-*` temporary
   directory may need removal after confirming that demo stopped. Never delete
   unrelated temporary directories. Reopen the standard launcher for the next demo.

## Verification in Codex versus Windows

Actually executed in Cloud: launcher/generator safety tests **7/7 passed**, all
JavaScript syntax and Git scope/whitespace checks passed. First local test run
exposed an optional absent `.firebaserc` fixture and a sandbox child-process EPERM;
the fixture was corrected and the approved subprocess-capable rerun passed all 7.
Generation used only temporary files; no Firebase emulator or production service
was started. Production rules/config and transaction source were byte-compared.

Written but **not run in Cloud**: three Flutter gate tests (48 environment
combinations, synthetic/setup/endpoint restrictions, default repository closed).
Flutter/Dart, Firebase CLI/dependencies and Windows CMD/PowerShell are unavailable.
No SDK/dependency download was retried. Actual launcher startup/Ctrl+C cleanup on
Windows, Rules compilation, Flutter analysis/full tests, 70-case security rerun
and Pixel 6/two-device live inbox acceptance remain local checks. The historical
Chrome/Dart loading gap is unchanged and is not used for this Android workflow.

Production checkout remains closed. Stop for review after Android acceptance;
no merge, production deployment, billing change or Stage 3 implementation occurs.
