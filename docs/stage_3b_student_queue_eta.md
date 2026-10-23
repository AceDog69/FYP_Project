# Stage 3B candidate — Student Queue, ETA, Cart and Checkout

Branch: `feature/stage-3b-student-queue-eta`.
GitHub-verified base: `2f950fa600d72ac3b01486aaea0e07571f053feb`.
User-reported Windows acceptance of that base on 23 October 2026: analyze clean,
83 Flutter tests passed, 89 Firebase tests passed, zero Rules-budget diagnostics,
Pixel 6 checkout/tickets/FCFS/status/history/details accepted. These are BASE
results, not Stage 3B results.

## Privacy and authoritative progress

New `queueProgress/{vendorUid}` has exactly six fields: schemaVersion (1),
vendorUid, nextTicket (integer), preparing (boolean), revision (integer), updatedAt
(server timestamp copied from the authoritative cursor). It contains no order ID,
Student UID, food/item/payment information or private stall settings. Students
may GET aggregates for published stalls; collection LIST is denied. Private
vendorQueues, another Student's orders and source stalls remain inaccessible.
Students cannot write progress, statuses or cursors. Queue UI has no counter
mutation; the existing Rules-verified checkout allocation is the sole Student
counter-write protocol and is unchanged.

The Stage 3A order/cursor invariant is retained. Every Start/Ready commit now also
writes the projection. Cursor Rules require getAfter(projection) to match the
exact cursor revision, nextTicket, preparation occupancy and updatedAt. Projection
Rules independently require the same authoritative getAfter(cursor) values.
Updates require an actual +1 cursor revision in the same atomic commit and a
strictly increased projected revision, so detached writes, replay, decreases,
skipped advances and false occupancy are denied. Keys/types and the relation
`revision = 2*(nextTicket-1) - (preparing ? 1 : 0)` are validated. No client value
can advance the source cursor, bypass owner/FCFS checks or reveal its order ID.

A configured owning Vendor can CREATE a missing projection by mirroring an
existing Stage 3A cursor exactly, including its original timestamp, without
moving the cursor. If no cursor exists, creation can publish the verified initial
state (nextTicket 1, not Preparing, revision 0, server timestamp). This is the only
standalone initialization exception; it grants no advancement. Vendor Orders
performs this idempotent, transaction-based publication on the first confirmed
queue subscription in the isolated demo. An already existing mismatched projection
fails closed. Until publication, Students see unavailable progress, never an
invented zero queue. No migration, checkout-schema rewrite or production write
was performed. A future legacy client that omits projection updates is denied.

The cursor's own validator compares its requested values directly with its prior
state, removing duplicate self-reads while preserving every FCFS transition check.
The order's reciprocal claim/release validators remain. A static conservative
review gives at most 4 accesses for Start's order update, 7 for cursor+projection
validation, 4 for projected update, plus 2 transaction read-authorization checks
(17 total before caching). Each write is below 10 and the group below 20 in this
review. Exact expressions/access counts and emulator compilation are unverified;
the combined runner still fails for ANY budget diagnostic, including negatives.

## Deterministic position and approximate time until Ready

Use only a Student's OWN confirmed order and its stall's sanitized progress.
The preparation-time baseline is the canonical `preparationMinutes` snapshot
recorded at checkout, not a hardcoded value or fabricated historical average.
Changing stall settings later does not rewrite that order's baseline.

For a Pending ticket t and next never-started ticket n:

- Orders ahead = `t - n + (preparing ? 1 : 0)`.
- Approximate minutes until Ready = `(ordersAhead + 1) * preparationMinutes`.
- With no starts, n=1/preparing=false. Ready/Completed predecessors are excluded
  by the advanced cursor. A current Preparing predecessor counts exactly once.
- New later tickets do not change an existing ticket's position. Different stalls
  always have different progress and are never combined.

For the Student's own Preparing order, progress must indicate Preparing with
nextTicket=t+1. Orders ahead=0. Approximate remaining minutes are the rounded-up
positive remainder of the baseline from its protected preparingAt timestamp.
If the baseline has elapsed, show unknown Ready time / initial estimate elapsed,
never a false zero-minute promise. Device-clock inaccuracies affect this estimate.
There is no timer/countdown; estimates refresh with data/widget updates or an
explicit Refresh Queue. Pending estimates conservatively retain a full allowance
for another Preparing order because its start time is intentionally private.

Ready and Completed are no longer waiting: ahead=0, no wait ETA. Ready remains in
Active until collection; Completed appears in History. Out-of-order stream
snapshots (e.g. Pending with an already advanced cursor) display Synchronizing,
not a negative count. Missing/cached/error/loading progress does not produce a
current position/ETA. Cached own orders are labeled last-known. Server metadata
and session guards discard pending local writes and cross-session events.

## Accessible visual references

Both inline images attached to the Stage 3B request were actually accessible and
inspected: **My Cart** and **Checkout & Payment**. They are the primary visual
specification for these two screens. Also available: the earlier Full Design &
Decision Handover and Stage 3A card/badge implementation. No additional Student
Queue PNG has been claimed as viewed for this task.

Cart now uses the reference's orange #FF7A00 rounded header, stall context card,
white bordered rounded food cards, larger local pictures, prominent orange unit
prices, quantity pills with 48px controls, trash confirmation, item subtotals,
order summary and anchored Review Checkout. Clear Cart, Continue Browsing,
refresh, stale-selection review, warnings and retained-checkout resolution stay
functional. The business maximum of TWO foods overrides the reference's sample
three products. Existing 23 picture assets/IDs are reused unchanged.

Checkout uses the matching orange header and stall/summary cards, three full-width
selectable payment rows with orange selection, simulated-payment notice, prominent
Total Payment and anchored Confirm Order with amount. Pictures are included in
the summary as explicitly requested. The five existing Student navigation targets
are available through real route callbacks; all are disabled during confirmation.
Receipt styling is consistent. Existing retry identity, discard/server recovery,
Cart clearing and payment behavior remain in the unchanged controller/checkout
transaction. Only presentation test finders are adapted to the new cards/summary;
original business assertions and test cases are retained.

## Intermediate checkpoint verification

Cloud executed: existing launcher/budget/transport Node tests **11/11 passed**;
JavaScript syntax checks for the new queue security suite, updated FCFS helper,
FCFS suite and combined runner passed; git diff --check passed.

New security suite has 15 cases and includes all prior 89 in `npm run test:queue`
(expected total 104), with ignored raw coverage and student-queue budget evidence.
These emulator tests are written but NOT executed. Flutter/Dart SDK binaries,
Firebase CLI/npm dependencies and Android are unavailable in Cloud; no download
attempts were repeated. Flutter model/UI tests, final review and final Windows
instructions are pending at this checkpoint. No claim of compiled UI, executed
Rules proof or zero Stage 3B budget diagnostics is made.

Checkout and both Vendor deletion gates remain closed. The accepted isolated
emulator launcher and Stage 2C checkout transaction are retained. No deployment,
production data, real payment, billing or Stage 3C notification work is authorized
or performed.

## Final candidate status (supersedes checkpoint pending list)

Queue/ETA, Cart, Checkout/Payment and receipt presentation are implemented as a
candidate. Added 19 Flutter tests: 14 model/queue cases and 5 commerce UI cases.
All 83 earlier Flutter case declarations remain; presentation finders now target
the new summary value, trash control and full-width payment cards. The Stage 1
navigation test now expects the functional empty queue, replacing Coming soon.
No existing business assertion/test case was removed. Expected full Flutter
count is 102, subject to actual Windows execution.

The 15 new Firebase cases cover initial/legacy bootstrap, exact required paired
projection, omitted projection, forged numbers/flags/identity/timestamps, detached
updates, decreases/replay/delete, wrong roles/owners, read privacy, stale legacy
bootstrap, bootstrap/start races, duplicate starts, Ready/start contention,
independent stalls and a real-time Student listener. All original 89 cases remain
in the combined runner (104 expected). The FCFS transaction fixture now adds the
required projection; a metadata-negative raw fixture also includes a valid mirror
so its missing-field rejection is not hidden by a missing projection.

Cloud actually executed:

```text
node --test --test-concurrency=1 scripts/checkout_demo_launcher.test.mjs test/firebase/checkout_budget.test.mjs test/firebase/checkout_transport.test.mjs
11 passed, 0 failed (7 launcher, 1 budget detector, 3 transport)

node --check test/firebase/student_queue.test.mjs
node --check test/firebase/fcfs_helpers.mjs
node --check test/firebase/vendor_fcfs.test.mjs
node --check test/firebase/run_checkout_tests.mjs
All syntax checks passed.

git diff --check
Passed.
```

After final Rules edits, the 7 launcher tests were also rerun and passed. A
Pygments Dart lexical delimiter audit of all 14 changed/new Dart files passed;
that audit is NOT a Dart parser, analyzer, compiler or Flutter test run.
Source comparisons confirmed the checkout transaction/retry body, checkout
controller, StudentCart model, limits, emulator launcher, dependencies and the
earlier 70 security-case source files are byte-for-byte unchanged from Stage 3A.
The 19 FCFS case names and all prior Flutter case names were preserved.

NOT executed in Cloud: flutter analyze, any Flutter tests (including the new 19),
Firebase CLI/emulator tests, Rules compilation, measured Rules expression/access
budgets, Android rendering or pixel comparison with references. There is no
usable Flutter/Dart binary, Firebase CLI or Firebase npm dependency installation
in this environment. No repeated SDK downloads were attempted. The earlier
Chrome integration loading stall remains an unpassed historical gap.

## Windows verification

In your existing Windows clone, stop any running local Firebase emulators first.
Open PowerShell at the repository root (replace the example path):

```powershell
cd C:\path\to\FYP_Project
git fetch origin
git switch feature/stage-3b-student-queue-eta
git pull --ff-only origin feature/stage-3b-student-queue-eta
git rev-parse HEAD
flutter pub get
flutter analyze
flutter test
```

Compare HEAD with the exact final SHA in the delivery report. Preserve any local
changes separately if switching fails; do not force/reset. Require clean analysis
and all Flutter tests passing. Keep the actual test count and diagnostics; the
expected count after the reported 83-test base is 102.

Run ALL previous security cases plus the Stage 3B projection cases:

```powershell
cd test\firebase
npm ci
npm run test:queue
Get-Content artifacts\student-queue-budget-diagnostics.json
cd ..\..
node --test --test-concurrency=1 scripts/checkout_demo_launcher.test.mjs test/firebase/checkout_budget.test.mjs test/firebase/checkout_transport.test.mjs
```

Require 104/104 security tests, childExitCode 0, and an EMPTY budgetDiagnostics
array. The runner fails for missing/empty Firestore debug-log evidence and for
expression/access exhaustion, even if assertFails accepted a permission error.
Coverage/log silence does not measure an exact per-write expression count.
Retain ignored coverage/budget artifacts and logs for review. test:fcfs (89) and
test:checkout (70) still exist, but test:queue already includes those cases.
Do not treat any new failure as accepted or bypass a gate to get green results.

## Pixel 6 acceptance against local demo data

In terminal A at the repository root:

```powershell
.\scripts\start_checkout_demo.cmd
```

This unchanged launcher generates temporary rules/config outside the repository,
changes ONLY checkoutWritesEnabled() in that local copy and refuses a project
other than demo-smart-canteen. Both Vendor deletion gates remain closed. Do not
run firebase deploy. Start the Pixel 6 Android emulator in Android Studio, then
in terminal B:

```powershell
flutter devices
flutter run --debug -d emulator-5554 -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2 --dart-define=EMULATOR_CHECKOUT=true
```

Use the device ID shown by flutter devices if it differs. The explicit flag
retains the accepted strict debug/named-app/demo-project/local-endpoint gate for
checkout and Vendor processing. Normal main.dart, release, production Firebase
and runs without the flag remain closed.

1. Use synthetic Vendor/Student accounts only. Vendor: complete setup, open the
   stall, add a category and two available foods, and OPEN VENDOR ORDERS ONCE.
   This securely initializes missing queueProgress, including legacy Stage 3A
   cursors. There is no reset/migration of tickets or existing orders. A Student
   viewing a stall whose Vendor has not initialized progress sees Unavailable.
2. Student: compare **My Cart** with the actual attached Cart reference. Check
   orange rounded header, stall card, food pictures/name/orange unit price,
   steppers, trash confirmation, subtotals, summary and anchored Review Checkout.
   The reference's three products are intentionally replaced by the approved
   two-product maximum. Test quantity 1/20, Remove Cancel/Confirm, Clear Cart
   Cancel/Confirm and Continue Browsing. Verify stale/closed/unavailable warnings
   still block unsafe review/confirmation and price review retains explicit consent.
3. Compare **Checkout & Payment** with the actual attached payment reference:
   stall/summary cards, pictures with unit prices and quantities, orange total,
   three full-width payment choices and selected indicator, simulated-payment
   disclaimer, Confirm Order and the five real navigation targets. Change each
   method before confirming; while a request is retained it must stay locked.
   Confirmation/navigation are disabled while submitting. A successful ack clears
   the matching Cart; failure preserves it and Retry uses the same submission ID.
4. Confirm two orders for one stall. Queue → Active shows separate own tickets,
   status, orders ahead and approximate time until Ready. With baseline 15 minutes,
   no started orders means Ticket #1: 0 ahead/~15 min, Ticket #2: 1 ahead/~30 min.
   Use the preparation time you actually configured; code contains no fixed ETA.
5. Vendor: Start #1; #2 cannot start yet. Student sees Preparing for #1, 0 ahead,
   approximate remaining time based on its preparingAt; #2 still has one ahead.
   Mark #1 Ready: its ETA disappears, #2 now has zero ahead and becomes eligible.
   Start #2 while #1 remains Ready; Complete #1 after simulated collection. #1 moves
   from Student Queue Active to History with no waiting ETA. Repeat for #2.
6. Use a second local Android emulator/client for simultaneous live Student/Vendor
   observation. If using only one Pixel 6, switch accounts and verify fresh state
   on return; that alone is not proof of simultaneous listener delivery.
7. Place another order at a different synthetic stall. Even if its ticket number
   repeats, it must remain in its own stall card/position calculation. Log out
   and use another Student account: no old Student tickets or Cart may remain.
8. To observe an elapsed estimate, create a NEW order after setting a short legal
   preparation time (e.g. 1 minute), start it, wait beyond that baseline and tap
   Refresh Queue. It must say the initial estimate elapsed / Ready time unknown,
   not promise zero minutes. There is deliberately no continuously ticking ETA;
   phone clock differences and full allowance for another Preparing order limit
   precision. Older orders retain their own confirmed baseline snapshot.
9. Disconnect the local client/server. Label cached orders/progress as last-known;
   current position/ETA must become unavailable. Reconnect and Refresh Queue to
   reload both orders and progress. Ready/Completed rely on the own confirmed
   order and do not require another stall-progress read. Confirm no false offline
   checkout success, no duplicate tickets, and no enabled Food/Category Delete.
10. Check 412×915 Pixel 6 layout and a smaller 320×640 viewport for scrolling,
    readable labels and 48px quantity controls. Manual visual fidelity/accessibility
    remain acceptance checks, not a claimed Cloud screenshot result. Recheck
    Vendor Dashboard, Menu/picker, Profile, Open/Close, Auth, Logout, Student Home
    and the original four/five bottom tabs. Unrelated screens were not redesigned.

Stop Flutter with q, then stop terminal A with Ctrl+C and wait for emulator/temporary
file cleanup. Local demo data is disposable unless exported separately. If retaining
it, retain orders, counters, private cursors and projections together; never reset
individual ticket/progress documents. No production data/rules are touched.

## Remaining limitations and stop condition

Production gates remain closed; only the isolated flagged debug demo performs
checkout and Vendor transitions. Queue projection/FCFS/runtime budget safety
requires successful local tests and review of this exact candidate. No production
migration/deployment is included. Legacy progress publication requires a connected
owning Vendor; absent progress fails closed. No count/ETA is inferred from private
other-Student documents or an unverified cache. ETA is approximate, uses the
confirmation baseline rather than later settings/history, and is not a promise.
There are no background timers, historical statistics, averages, real payments,
paid services, Functions, Ready notifications or Stage 3C implementation.
