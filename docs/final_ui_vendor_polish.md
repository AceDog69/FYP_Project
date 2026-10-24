# Focused Vendor UI polish candidate — 24 October 2026

Branch: `feature/final-ui-vendor-polish`.
Verified remote base: `3be2117e7d868110be9ea678c8ce97beef4f8596`
(`fix: stabilize Stage 3B cart and checkout UI`). The exact five changed base
blobs and complete Git tree were verified/imported through the GitHub connector
because shell Git fetch failed to connect to proxy port 8080. No stale Stage 3B
source was used. The delivery report gives this candidate's exact final SHA.

## Screenshots actually inspected

All eight supplied PNGs were opened and visually inspected. Extracted copies
were kept outside the repository; no screenshots or personal account details
were added to application assets or committed.

| Archive | Inspected file | Use |
| --- | --- | --- |
| Improved_Current_Screen.zip | Screenshot 2026-10-23 161620.png | Accepted Vendor Dashboard header, spacing, cards and typography |
| Improved_Current_Screen.zip | Screenshot 2026-10-23 161628.png | Accepted Vendor Profile header, information rows and white bordered sections |
| To_Improve_Screen.zip | Screenshot 2026-10-23 161530.png | Existing shared Order Details gaps |
| To_Improve_Screen.zip | Screenshot 2026-10-23 161606.png | Existing Vendor Orders header, filters and card gaps |
| To_Improve_Screen.zip | Screenshot 2026-10-23 161613.png | Existing Vendor Menu header, actions and card gaps |
| Reference_Screen.zip | V2-02_Vendor_Menu_Management.png | Menu image/name/category/price hierarchy, availability and actions |
| Reference_Screen.zip | V2-04_Vendor_Orders_Queued.png | Ticket/status hierarchy, filter layout and clear actions |
| Reference_Screen.zip | V3-02_Vendor_Order_Details_Ready.png | Overview, information, items and simulated payment sections |

Dashboard/Profile screenshots are the primary implemented visual standard.
Existing original Cart/Checkout references were also available in the earlier
conversation; their accepted implementation and latest fixes are preserved.
No supplied reference image was missing for this task.

## Presentation changes

- Vendor Menu: full-width orange rounded header matching Dashboard/Profile,
  circular stall icon, consistent 20px content gutters, white bordered food cards,
  larger local pictures and stronger name/category/orange-price hierarchy.
  Manage Categories is outlined and Add Food is primary; they stack on small
  screens or with larger text. Availability keeps its accessible SwitchListTile
  and adds readable icon/text status. Edit and disabled Delete Food retain their
  original callbacks/guards with at least 48px action targets.
- Vendor Orders: matching header replaces the extra generic Brand bar; white
  bordered cards replace tinted surfaces. Ticket/status, time, snapshot items,
  quantities, unit prices, subtotals and orange confirmed totals are easier to scan.
  All/Pending/Preparing/Ready/History stay inside Orders as horizontally scrollable
  48px-target filters, with a visible scrollbar and clear orange selection.
  Start Preparing, Mark as Ready and Mark Completed after collection retain the
  exact previous eligibility predicate and confirmation/error handling.
- Shared Order Details: orange back header and separate Order Overview, Order
  Information, Ordered Items and Payment Summary cards for both roles. Actual
  dates, times, snapshots, amounts and statuses come from the same existing live
  streams. Existing transition timestamps are displayed only when present.
  Cached/item-error/order-error/loading/Retry states remain explicit. Small screens
  and larger text wrap and scroll. No real payment, fabricated ETA or new queue
  action is shown. The outdated claim that queue/ETA functionality does not yet
  exist was removed; no queue logic or screen was changed.

Reference adaptations preserve approved behavior: Pending is kept as the real
status (the older image says Queued); actual ticket integers and dates are shown
rather than sample numbers. Existing Orders totals remain visible. Food/Category
Delete remain disabled in the real client. Details remains read-only: the
reference's Mark Completed button was not introduced as a new workflow; Vendor
status actions remain in Vendor Orders. Payment is labeled simulated, with no
money charged. Existing four/five-tab navigation is preserved.

## Scope and preservation evidence

Changed application files are limited to:

- lib/screens/vendor_menu_screen.dart
- lib/screens/orders_screen.dart
- lib/screens/home_screen.dart — ONLY suppress the old generic Vendor Orders AppBar
- lib/widgets/vendor_workspace_widgets.dart — shared presentation components

Added test/vendor_ui_polish_test.dart and this handover; updated the development
progress record. All existing Flutter tests remain byte-for-byte unchanged.

A source-comparison audit verified 76 protected files unchanged, including Rules,
all services/models, original assets, dependencies, Firebase security tests and
runners, the emulator launcher, accepted Dashboard/Profile, Student Queue, and
latest Cart/Checkout screen and test files. Home differs by the single Vendor
AppBar condition only, preserving the latest checkout-navigation fixes. The
shared status badge and Student Orders item layout are unchanged.

Menu action/delete callbacks and the complete category manager/dialog/validation
code are unchanged. Order stream loading and status-update callbacks and the
exact FCFS action eligibility expression are unchanged. No Firebase transactions,
cursors/projection, queue calculations, checkout limits, service gates, production
rules/configuration, billing or security tests were modified. No deployment,
merge, rebase, force-push or Stage 3C work was performed.

## Actual Cloud checks and pending verification

Executed:

```text
node --test --test-concurrency=1 scripts/checkout_demo_launcher.test.mjs test/firebase/checkout_budget.test.mjs test/firebase/checkout_transport.test.mjs
11 passed, 0 failed (7 launcher, 1 budget detector, 3 transport checks)

git diff --check
Passed.
```

The source-comparison scope audit passed. A supplemental Pygments Dart lexical
delimiter audit passed for the five new/changed Dart files. Neither is a Dart
parser/analyzer, compiler, widget renderer or executed security proof.

Added 12 focused Flutter widget cases (including the two-role Details case):
header/card consistency and action sizing; existing Menu actions and disabled
deletions; availability/Edit wiring; cached/loading/error/Retry; narrow/scaled
Menu; horizontal status filters; FCFS action eligibility and exact amounts;
Vendor Orders state handling; both roles' shared receipt fields; live Details
status/cached/item errors; Details loading/order errors; long narrow Details.
These use existing test doubles and do not replace Firestore Rules proof.

Flutter/Dart SDK binaries, Firebase CLI/dependencies and Android execution are
unavailable in this Cloud environment. **flutter analyze, flutter test (including
these 12 cases), Firebase emulator suites and Android/manual visual acceptance
were NOT run.** No SDK download attempts were repeated. No new pass count is
claimed for Flutter or Firebase. The user's locally verified starting point is
preserved; its acceptance is not evidence that this new candidate has passed.

## Beginner Windows verification

Open PowerShell in your existing clone. Replace the example directory:

```powershell
cd C:\path\to\FYP_Project
git fetch origin
git switch feature/final-ui-vendor-polish
git pull --ff-only origin feature/final-ui-vendor-polish
git rev-parse HEAD
flutter pub get
flutter analyze
flutter test test/vendor_ui_polish_test.dart
flutter test
```

Compare HEAD with the exact SHA from the delivery report. Save any local changes
separately if switching/pulling is blocked; do not force/reset them. Require clean
analysis and the new 12 cases plus the complete prior Flutter suite to pass.
Record actual counts/diagnostics rather than assuming the candidate passed.

Firebase source/coverage is unchanged. To rerun the existing full security suite
as a local regression check (stop other local emulators first):

```powershell
cd test\firebase
npm ci
npm run test:queue
Get-Content artifacts\student-queue-budget-diagnostics.json
cd ..\..
```

Require the existing suite passing with an empty budgetDiagnostics array and
childExitCode 0. This UI task adds/modifies no Firebase test or security assertion.
Never deploy production rules for this test.

## Pixel 6 acceptance

In terminal A at the repository root, start the unchanged isolated demo launcher:

```powershell
.\scripts\start_checkout_demo.cmd
```

Start the Pixel 6 in Android Studio Device Manager. In terminal B:

```powershell
flutter devices
flutter run --debug -d emulator-5554 -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2 --dart-define=EMULATOR_CHECKOUT=true
```

Replace emulator-5554 with the Android ID listed by flutter devices. Use synthetic
local demo accounts only. Normal main.dart/release/production gates are unchanged.

1. Compare Menu and Orders with the supplied accepted Dashboard/Profile and three
   reference images. Check orange rounded headers, consistent gutters, white
   cards, readable text/images and controls. Dashboard/Profile themselves must
   look unchanged; Cart/Checkout must retain the fixes from 3be2117.
2. Menu: create/rename categories, add/edit/reassign foods, select existing local
   pictures, validate fields/prices and toggle availability. Unavailable food must
   remain listed. Food Delete and Category Delete must stay disabled. Empty,
   cached, loading, failed-operation and Retry feedback must remain understandable.
3. Place two Student orders using the accepted demo checkout. In Vendor Orders,
   verify ascending ticket order, actual statuses, quantities, unit prices,
   subtotals and exact totals. Scroll all five filters; filtering cannot grant
   eligibility to a later ticket.
4. Start the earliest Pending ticket. The next ticket must remain disabled until
   the Preparing order becomes Ready. Exercise Mark as Ready and Mark Completed
   after simulated collection. Pending confirmation/duplicate taps, stale updates,
   cached state, errors and refresh must behave as before; no optimistic success.
5. Open View Details as both Vendor and Student. Compare the same immutable
   receipt: ticket, current badge, stall, order date/time, snapshot items, totals
   and simulated payment. Ready/Completed transitions should update a currently
   open Details page. Verify the real timestamps when present. Details has no new
   status/cancel/delete/payment action and shows no fabricated wait estimate.
6. Repeat on 412×915 Pixel 6 and a smaller 320×640 viewport; try larger system
   text. Scroll to History and through all Details sections. Check 48px action
   targets, wrapped long names, totals, warnings and keyboard-free navigation.
   Manual pixel/visual fidelity and accessibility remain acceptance checks.
7. Verify loading, cached/offline and error/Retry states. Reconnect/refresh before
   changing data. Check original Vendor four tabs, Student five tabs, Logout,
   Dashboard/Profile and accepted Stage 3B Cart/Checkout/Queue still behave as before.

Stop Flutter with q and stop terminal A with Ctrl+C; wait for local emulator and
temporary-file cleanup. Do not run firebase deploy or change production data.

STOP after this polish candidate. Student Queue readability and Stage 3C Ready
notifications remain separate, unstarted tasks awaiting review.
