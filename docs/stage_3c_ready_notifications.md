# Stage 3C — Ready notifications and Stall Menu header

24 October 2026 (Asia/Singapore).

Branch: `feature/stage-3c-ready-notifications`.
Exact GitHub base: `a5847df924b0a22a86d1135f40bbd5c4884c8ed5` on
`feature/final-ui-student-polish` (`fix: stabilize student UI quantity and cached request tests`).
The delivery report identifies the exact backed-up candidate commit.

The user reports **134/134 Flutter tests** and **104/104 Firebase security cases with zero Rules-budget
diagnostics** for the accepted base. Those are prior Windows results, not results executed for this candidate.

## What changed

### Stall Menu header

Back, Stall Menu and the live Cart count share one horizontal orange rounded header when their
measured text widths fit. Title, text scaling, button padding and 48px touch targets are included in the
fit calculation. A narrow/enlarged-text fallback moves only Cart below the title when necessary.
Only Stall Menu uses this new header. Other accepted headers and the food-selection workflow are unchanged.

### Student Ready notifications

- An active authenticated Student session owns one `ReadyNotifications` controller and an owner-scoped
  order subscription. Vendor sessions do not construct this controller.
- An observed, server-confirmed Pending/Preparing → Ready change can show a transient in-app alert
  containing the actual stall name, ticket and **Ready for pickup**. Its View action opens that order.
  A batch of multiple Ready changes shows a combined alert and links to the center.
- The existing Student **Profile** tab has an unread badge. Open **Profile → Notifications** for the
  notification center. No navigation tab or overlay obscuring existing actions was added.
- Center cards show the real stall, ticket, current Ready/Completed badge and server Ready timestamp.
  Ready tickets and completed notification history have separate filters.
- View Order Details marks that individual notification **Viewed** locally and opens the existing shared,
  live, owner-scoped Details screen. Merely opening the center does not mark all entries viewed.
- Ready → Completed updates the same notification and preserves its viewed/unread state. A newly
  completed but unviewed event may therefore still contribute to the badge until opened from History.
  Existing completed history found at startup starts viewed.
- Cached/error states retain only records already confirmed in this session and clearly warn that their
  status may be stale. Cached snapshots cannot create a new notification or a transient alert.
  Refresh/Retry are explicit. An ended stream is treated as unavailable for live updates.

## Data source and security boundary

There is **no notification collection, write, token, new permission or backend service**.
The controller subscribes through the existing `OrderRepository.orders(vendor: false)` API.
The unchanged Firebase implementation:

1. Queries `orders` with `studentUid == authenticated UID`.
2. Rejects a changed session while reading.
3. Discards snapshots with `metadata.hasPendingWrites`.
4. Decodes the canonical order fields and labels cached data.

The notification controller additionally checks its live session UID, filters every order by Student UID,
requires a Ready/Completed revision with real `readyAt`, `preparingAt` and status timestamps,
and ignores cached snapshots for event creation. It never reads private Vendor cursors or uses checkout
requests/client-estimated status to manufacture Ready events.

Existing Rules already require Ready transitions to be performed by the owning Vendor with
`readyAt == request.time`, valid status progression and the atomic FCFS queue release. Completion preserves
the same Ready timestamp. All existing order identity/snapshot protections and owner-only reads remain.
No Rules or Firebase transaction code was changed, so no new Rules proof or deployment is introduced.

## Initial snapshots, duplicates and lifecycle

The deterministic event identity is:

```text
studentUid / orderId / readyAt.seconds : readyAt.nanoseconds
```

The controller tracks confirmed previous states and announced identities in memory for the session.
The first server snapshot establishes a baseline: existing Ready tickets populate the center and badge
without a transient alert. Subsequent repeated snapshots, tab rebuilds, refreshes and reconnects cannot
announce an already observed event again. A timestamp replacement cannot manufacture another popup.
An order first observed already Ready after baseline is also listed without inventing an unseen transition.

Foreground transitions are best-effort alerts. Background updates may update center/read state but do not
show alerts; resume refreshes the server baseline rather than replaying background events. There is no
timer, polling loop or OS background notification. If a Ready state is skipped and the next observed status
is Completed, it becomes history rather than a false Ready-for-pickup alert.

The Home session owns and disposes the controller/subscription. A generation guard ignores late callbacks
from replaced listeners. A UID guard prevents old-account data from being returned even before disposal.
The existing UID-keyed Navigator is wrapped in a UID-keyed ScaffoldMessenger so queued transient messages
are also destroyed on Logout/account changes. Notification actions validate the current session before
opening Details. The original Logout/checkout/tab callbacks are unchanged.

## Known limitations

- **In-app only:** no FCM, OS push, permissions, background job, Cloud Function or guaranteed delivery while
  the app is closed. A notification popup requires an observed confirmed transition while foregrounded.
- **Session-local viewed state:** read/announced flags are not saved to disk or Firestore. Logout, process
  restart or replacement of the session/controller resets them. Existing Ready tickets can be unread again
  on reopening, but are not replayed as new popups. No durable or cross-device read receipt is claimed.
- **Offline:** only previously server-confirmed notification records in this running session are shown as
  last-known information. A fresh offline session waits for server verification instead of trusting a cached
  Ready state. Automatic reconnect may confirm a previously observed Pending/Preparing ticket as Ready once.
- **History:** records are derived from currently authorized confirmed orders; there is no separate durable
  delivery log. In-memory event bookkeeping grows with order history during this FYP session.
- **Verification:** this candidate has not been compiled, analyzed by Dart, run by Flutter, or Android-tested
  in Cloud. Windows analysis/tests and the two-client acceptance below are still required.

## Changed files

Application:

- `lib/services/ready_notifications.dart` — new session-scoped controller and notification record.
- `lib/screens/ready_notifications_screen.dart` — new center and accessible Profile entry.
- `lib/screens/home_screen.dart` — Student listener/lifecycle, transient alerts, badge and navigation.
- `lib/screens/auth_gate.dart` — session-scoped transient-message container.
- `lib/widgets/stall_menu_header.dart` — isolated responsive Back/title/Cart header.
- `lib/screens/student_stall_menu.dart` — opt into the header; selection body/dialog unchanged.

Tests/documentation:

- `test/ready_notifications_test.dart` — 20 controller cases.
- `test/ready_notifications_ui_test.dart` — 15 widget cases.
- `test/support/ready_notification_fixtures.dart` — synthetic fixtures only.
- `docs/stage_3c_ready_notifications.md` — this guide.
- `docs/smart_canteen_development_progress.md` — current handover.

All earlier Flutter/security test files, Rules, existing repositories/transactions, queue/ETA formulas,
checkout limits, dependencies, assets, emulator launcher and accepted screen layouts remain unchanged.
Production checkout and Food/Category Delete gates stay closed.

## Cloud checks actually executed

Passed **11/11** existing Node cases:

```text
node --test --test-concurrency=1 scripts/checkout_demo_launcher.test.mjs test/firebase/checkout_budget.test.mjs test/firebase/checkout_transport.test.mjs
```

This consists of 7 launcher tests, 1 Rules-budget diagnostic-detector unit test and 3 offline transport tests.
The checks used their approved local-process/loopback-socket permissions. They do not execute the Ready
controller/UI or the Firestore emulator suite; no new Rules-budget diagnostic count is claimed.

Also passed: `git diff --check`, protected-source audit (244 tracked files byte-for-byte unchanged,
including all pre-existing test files and all Rules/security sources), and a lexical Dart delimiter audit.
The lexical check is **not** a Dart parser, analyzer or compiler.

**Not executed:** `flutter analyze`, focused/full Flutter tests, Firebase emulator/security tests,
Android build/manual acceptance, rendered screenshot checks or the historical stalled Chrome/Dart integration test.
Flutter/Dart, Firebase CLI/dependencies and Android tooling are unavailable in this Cloud workspace.
No SDK/dependency versions changed and no SDK downloads were attempted.

The 35 new tests are written but unexecuted here. They cover ownership, initial/cache/server distinctions,
deterministic identities, repeated/reconnected snapshots, multi-stall tickets, viewed state, restart behavior,
missing Ready timestamps, completion/history, background/resume, stream errors/disposal, Logout/account
switches, correct Details navigation, small-screen center and responsive/live-count header behavior.

## Windows checks

Save your own uncommitted changes before switching. Open PowerShell at your repository:

```powershell
cd C:\path\to\FYP_Project
git status
git fetch origin
git switch feature/stage-3c-ready-notifications
git pull --ff-only origin feature/stage-3c-ready-notifications
git rev-parse HEAD
flutter pub get
flutter analyze
flutter test test/ready_notifications_test.dart test/ready_notifications_ui_test.dart
flutter test
```

Match HEAD to the delivery SHA. Record actual results; the prior 134 passes and the 35 newly written cases
must not be represented as executed candidate passes until Flutter reports them.

For the unchanged 104-case security regression, first stop manually running demo emulators:

```powershell
cd test\firebase
npm ci
npm run test:queue
Get-Content artifacts\student-queue-budget-diagnostics.json
cd ..\..
```

Require a passing suite, `childExitCode: 0` and `budgetDiagnostics: 0`.
This remains the existing local `demo-smart-canteen` security setup. Do not deploy Rules.

## Pixel 6 two-client acceptance

Use **two simultaneously running clients**: Pixel 6 as Student and a second Android emulator as Vendor.
Logging the Student out to act as Vendor on the same client cannot demonstrate a foreground Student alert;
reopening instead intentionally shows existing Ready information without a popup.

In Android Studio Device Manager start both AVDs. Keep the same local Firebase emulators running throughout.
Open three PowerShell terminals at the repository root.

Terminal A:

```powershell
.\scripts\start_checkout_demo.cmd
```

Wait for Auth/Firestore readiness and confirm the launcher identifies `demo-smart-canteen`.
It still changes only the temporary checkout gate and keeps both deletion gates closed.

Terminal B (Pixel 6 Student):

```powershell
flutter devices
flutter run --debug -d emulator-5554 -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2 --dart-define=EMULATOR_CHECKOUT=true
```

Terminal C (second Android emulator Vendor):

```powershell
flutter run --debug -d emulator-5556 -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2 --dart-define=EMULATOR_CHECKOUT=true
```

Replace both device IDs with the IDs listed by `flutter devices`. Both Android emulators use `10.0.2.2`
to reach the same Windows-host demo emulators. Use synthetic local accounts only.

1. **Vendor opens stall:** on the Vendor device sign in/register, complete local Stall Setup if needed,
   add a category and available foods using existing Menu actions, and Open Stall. Leave Vendor signed in.
2. **Student creates two tickets:** on Pixel 6 sign in as a different synthetic Student. Open Stall Menu;
   confirm Back/title/Cart align in one row at normal text size and Cart count/navigation remain live.
   Confirm one simulated checkout, then another. Respect two distinct foods and 20 units per food.
   On a fresh local stall these are #1/#2; otherwise use their actual next sequential numbers without editing counters.
3. **Earliest prepares:** Vendor Orders must allow Start Preparing only for the earliest eligible ticket.
   Start it. Student Orders/Queue still show live Preparing status and the original approximate ETA behavior.
4. **Ticket #1 Ready:** keep Pixel 6 app open. Vendor marks the preparing ticket Ready. Pixel 6 should show
   the actual stall/ticket Ready-for-pickup alert and an unread badge on Profile, once.
5. **Student opens notification:** tap the alert's View action. Confirm the correct own Order Details and
   current Ready status. Return, open Profile → Notifications, and confirm Viewed state/badge behavior.
6. **Vendor completes:** mark that Ready ticket Completed after collection. Student Details updates live;
   Notifications → History shows Completed with the same Ready timestamp and preserved Viewed state.
7. **Second/multiple tickets:** progress the next ticket. Check a new unread event, repeated Refresh without
   duplicate popups, and correct Details. Optionally repeat with a second synthetic stall to verify separate identities.
8. **Reopen:** leave a ticket Ready and stop only the Student Flutter app (`q` in Terminal B), then run it again.
   Existing Ready tickets appear in Notifications without a new popup. Viewed state may reset, as documented.
9. **Isolation:** sign out Student A, sign in as Student B while the demo stays running. No Student A
   center cards, badge, Details route or transient alerts may survive. Vendor must have no Student notification entry.
10. **Readability/offline:** test enlarged Android text and a small AVD. Cart falls back only when needed;
    the center scrolls to all actions without overflow. For an optional offline check, stopping the local demo
    must never manufacture Ready or a ticket. SDK cache detection may take time. Previously confirmed center
    records must be labeled stale; a fresh offline launch cannot create new verified notifications.
    Restarting the default non-exported demo may reset synthetic data, so repeat setup as needed.

Press `q` in both Flutter terminals to stop clients. Press Ctrl+C in Terminal A and wait for emulator and
temporary-file cleanup. No production deploy, gate activation, new service, payment change or next feature
is part of this batch. Stop after Stage 3C acceptance and record any failures against the exact candidate SHA.
