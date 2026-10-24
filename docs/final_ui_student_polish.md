# Student main-screen UI polish

24 October 2026 (Asia/Singapore).

Branch: `feature/final-ui-student-polish`.
Verified GitHub base: `feature/final-ui-vendor-polish` at
`92710b06ffdddc6be837d906074b244c63bafdc1` (`fix: stabilize vendor UI polish and scrolling tests`).
The final delivery message identifies the exact backed-up candidate SHA.

This is a presentation candidate awaiting Windows Flutter and Pixel 6 acceptance.
The user's 114 passing Flutter tests describe the verified base, not this candidate's Cloud results.

## Screenshots actually inspected

All eight images in the two new ZIP archives were opened and inspected:

| Archive | Image | Use |
| --- | --- | --- |
| `To_Improve_Student_Screen.zip` | `Current_Student_Home.png` | Existing Home, search, filters and stall card |
| same | `Current_Student_Menu.png` | Existing Stall Menu and selection action |
| same | `Current_Student_Order.png` | Existing Student Orders |
| same | `Current_Student_Profile.png` | Existing Student Profile |
| same | `Current_Student_Queue.png` | Existing Queue information hierarchy |
| `Approved_Screen.zip` | `Vendor_Menu.png` | Accepted orange header, compact pictures and white cards |
| same | `Vendor_Order.png` | Accepted tickets, statuses, totals and actions |
| same | `Order_Detail.png` | Accepted shared Details; reused without layout changes |

Two earlier supplied screenshots were still accessible and were also reopened:
`Screenshot 2026-10-23 161620.png` (Vendor Dashboard) and
`Screenshot 2026-10-23 161628.png` (Vendor Profile), from `Improved_Current_Screen.zip`.
These supplied the Dashboard/Profile header and account-card standards requested by this task.
No screenshot gap prevented this work. Screenshots and private account values were not copied into the repository.

## Changes by screen

- **Home:** full-width orange rounded Welcome header, search field, horizontally scrollable category chips
  with a visible scrollbar, compact stall pictures, white bordered cards, Open/Closed badges,
  existing initial preparation time and a prominent View Menu button. Closed stalls remain browseable.
- **Stall Menu:** matching orange back/Cart header, compact stall overview and 88×96 food pictures,
  stronger name/category/price hierarchy, full descriptions and 48px Select Food actions.
  Categories still select by stable ID, including a Vendor category whose display name is `All`.
  Only available foods in existing valid categories appear. Cached/closed selection guards remain unchanged.
  The food-selection dialog, 1–20 quantities, revision validation and single-stall Cart protection are unchanged.
- **Student Orders:** matching My Orders header, accepted white order cards, readable stall/ticket/status,
  snapshot item rows, prominent integer-sen total and 48px View Details actions.
  Unconfirmed checkout recovery remains separate from confirmed tickets and disables Resume for cached requests.
  The existing repository supplies only the authenticated Student's orders and requests.
- **Profile:** Profile & Settings header and read-only Account Information card, reusing accepted
  Vendor account-field styling. Only the existing full name, email, phone and role are shown.
  Logout retains its original callback, error handling and busy guard; its presentation shows pending progress.
  No editing/security/account feature was added.
- **Queue (priority):** matching My Queue header, accessible Active/History filters and white cards.
  Stall, ticket and actual status precede a highlighted metric panel with a 32px orders-ahead number
  and 24px approximate time-until-Ready text. Unsupported values remain `Unavailable`.
  Cached/loading/error, missing/synchronizing progress and elapsed-estimate warnings stay outside the
  collapsed explanation. The expandable **How this estimate works** section holds the existing formula
  explanation, preparation allowance and actual check/update timestamps. Explicit Refresh and Details remain.
  Ready/Completed and cached terminal wording retain their existing meaning. No countdown or fabricated time was added.

All pages use 20px horizontal gutters, the accepted `#FF7A00` orange, rounded headers,
bordered white cards and natural vertical scrolling. Long labels wrap; category filters scroll horizontally.
The generic Student Brand AppBar is removed so each page uses its own orange header, as Cart already does.
The Student five-tab navigation and its existing callbacks are unchanged.

## Source boundaries

Changed application files:

- `lib/screens/student_home.dart`
- `lib/screens/student_stall_menu.dart`
- `lib/screens/student_queue_screen.dart`
- `lib/screens/orders_screen.dart` (Student inbox presentation only; Vendor rendering is equivalent)
- `lib/screens/home_screen.dart` (Student Profile presentation and removal of the redundant Student AppBar)
- `lib/widgets/student_workspace_widgets.dart` (new presentation-only headers, filters, status and notices)

Other changed files:

- `test/student_ui_polish_test.dart` (new)
- `docs/final_ui_student_polish.md` (this document)
- `docs/smart_canteen_development_progress.md`

Rules, services, models, constants/checkout limits, security tests, dependencies, assets, launcher,
accepted Cart/Checkout, Vendor Dashboard/Profile/Menu, shared Vendor widgets and shared Order Details
are unchanged. All existing Flutter test files are retained byte-for-byte from `92710b0`.
The shared inbox file retains the same Vendor FCFS filters, eligibility conditions, callbacks and rendering values.
No queue formula, cursor/projection, transaction or Firebase configuration changed.
Production checkout and both Vendor deletion actions remain gated. No merge, rebase, force-push,
deployment, production data change, paid service, new dependency or Stage 3C notification work was performed.

## Cloud verification actually executed

The following unchanged Node checks passed **11/11**:

```text
node --test --test-concurrency=1 scripts/checkout_demo_launcher.test.mjs test/firebase/checkout_budget.test.mjs test/firebase/checkout_transport.test.mjs
```

Breakdown: 7 demo-launcher tests, 1 budget-diagnostic detector unit test, 3 offline transport tests.
An initial sandboxed attempt reported two file-level failures because the checks require child processes
and loopback sockets. The approved rerun with those execution permissions passed all 11 cases.
This is not a Firebase emulator security run and does not establish a new Rules-budget diagnostic count.

Also executed successfully:

- `git diff --check`.
- Source scope audit against the exact base: 239 protected tracked files unchanged;
  all previous Flutter/security tests preserved, along with the protected selection, session,
  FCFS callback/eligibility, queue-stream inputs and verification logic.
- Dart lexical delimiter audit of the changed/new Dart files. This checks balanced punctuation,
  not Dart parsing, compilation, analysis or rendering.

**Not executed in Cloud:** `flutter analyze`, `flutter test`, Firebase emulator suites,
Android compilation/manual acceptance, accessibility runtime checks or screenshot comparison of a rendered app.
Flutter/Dart, Firebase CLI/test dependencies and Android tooling are unavailable in this workspace.
No SDK downloads were attempted. Do not treat the candidate as locally accepted until the following checks pass.

The new widget test file defines **20 cases** (18 individual cases and two parameterized device-size cases).
They cover the five screens at Pixel 6 logical dimensions and 320×640 with 1.6× text, long fields,
48px primary actions, search/filter selection, category ID/display-name separation, quantity bounds,
stale revisions, unavailable/cached/closed menus, checkout recovery, actual order snapshots,
Pending/Preparing/Ready/Completed, exact orders-ahead/ETA fixtures, elapsed and missing estimates,
separate stalls, loading/error/Retry/Refresh, account changes and pending/failed Logout.
These cases are written but unexecuted here; existing tests remain the regression baseline.

## Windows verification

Open PowerShell in your existing repository. If `git status` shows your own uncommitted work,
save it before switching branches; do not reset or discard it.

```powershell
cd C:\path\to\FYP_Project
git status
git fetch origin
git switch feature/final-ui-student-polish
git pull --ff-only origin feature/final-ui-student-polish
git rev-parse HEAD
flutter pub get
flutter analyze
flutter test test/student_ui_polish_test.dart
flutter test
```

Match `git rev-parse HEAD` to the delivery SHA. Record the actual test count/results;
do not substitute the base's reported 114 passes or the 20 newly written cases for an executed result.

For the unchanged complete security regression, stop any manually running demo emulators first:

```powershell
cd test\firebase
npm ci
npm run test:queue
Get-Content artifacts\student-queue-budget-diagnostics.json
cd ..\..
```

Require the suite to pass, `childExitCode` to be zero and `budgetDiagnostics` to be zero.
These commands use the synthetic `demo-smart-canteen` project, not production. Do not run Firebase deploy.
The earlier stalled Chrome/Dart integration run remains an existing verification gap;
no browser integration pass is claimed by this UI task.

## Pixel 6 acceptance

Start the Pixel 6 Android emulator in Android Studio. Keep two terminals open at the repository root.

Terminal A starts the existing isolated checkout-enabled **local** demo:

```powershell
.\scripts\start_checkout_demo.cmd
```

Wait for Auth/Firestore emulator readiness. The launcher must identify `demo-smart-canteen`.

Terminal B:

```powershell
flutter devices
flutter run --debug -d emulator-5554 -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2 --dart-define=EMULATOR_CHECKOUT=true
```

Use your displayed Android device ID if it differs. Use synthetic local accounts and the existing
local Stall Setup/Vendor Menu workflow. Create two available foods; production data is unnecessary.

1. **Home:** compare the orange Welcome header/cards with the supplied Vendor references. Search by
   stall name, clear it, scroll categories and inspect Open/Closed badges and actual preparation time.
   A Closed stall opens for browsing but cannot supply new selections.
2. **Stall Menu:** inspect compact pictures, names, full descriptions, prices and categories. Scroll filters,
   select food, vary quantity, cancel/add and navigate to Cart. Confirm unavailable items disappear,
   and switching stalls still requires confirmation. Check the unchanged two-distinct-food/20-unit bounds.
3. **Orders:** use the existing simulated demo checkout. Verify only the signed-in Student's receipts,
   ticket/status, quantities, prices, total and View Details. Check unconfirmed recovery if a request exists.
   Shared Details should match the accepted design with real snapshots and simulated payment.
4. **Queue:** follow two tickets. Initially inspect their actual orders ahead and approximate until-Ready
   estimates. Expand/collapse How this estimate works. Explicitly refresh. As the Vendor starts the earliest
   ticket, marks it Ready and completes collection, verify live badges/numbers and Active/History movement.
   Check independent stalls separately. An unavailable projection must never display an assumed position/time.
5. **Offline/cache:** stop/disconnect the local emulator transport temporarily while the app is open.
   SDK cache/warning behavior may take time to appear. Check visible stale/unknown labels and disabled
   selections; do not mistake cached data for confirmation. Restore the emulators and use Retry/Refresh.
6. **Profile/session:** verify read-only fields, safe Logout and no added account features. Sign in as another
   synthetic Student; previous Orders/Queue/Cart/routes must not persist. Check all five navigation tabs.
7. **Layout:** inspect normal Pixel 6, Android's larger font setting and a small device. Scroll each screen
   to its last action. Confirm no clipped text, overflowing chips, inaccessible buttons or gesture-bar overlap.
   Recheck accepted Cart, Checkout, Vendor screens and Details for regressions.

Press `q` in Terminal B to stop Flutter. Press Ctrl+C in Terminal A and wait for emulator/temporary-file
cleanup. Normal production entrypoints and gates remain unchanged. Stop after this acceptance batch;
Stage 3C Ready notifications require a separate authorization.
