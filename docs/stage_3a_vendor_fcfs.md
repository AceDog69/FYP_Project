# Stage 3A Vendor FCFS candidate

Based on the GitHub-verified Stage 2C commit
`9da8298418eaeedbae002903504a6f5a84f59407`. Branch:
`feature/stage-3a-vendor-fcfs`. This is a review candidate, not a deployment.

## Policy and server invariant

One Preparing order per stall. The exact next Pending ticket must start first.
Pending → Preparing → Ready → Completed; Ready releases the preparation slot.
A Ready order may be completed after collection independently of later tickets.
There is no cancellation, priority change, reset, deletion, Student status write,
queue/ETA screen or notification functionality in this increment.

The new owner-only `vendorQueues/{vendorUid}` document contains schemaVersion 1,
vendorUid, nextTicket, preparingOrderId (null or an order ID), revision, updatedAt.
Absence means ticket 1, empty slot, revision 0. Creation can ONLY accompany ticket
1 becoming Preparing, with nextTicket 2, its ID in the slot, revision 1.

Inductive proof under the existing Stage 2C Rules:

1. Checkout creates contiguous, unique, immutable per-stall tickets starting at 1.
   No client can delete confirmed orders or change their stall/ticket.
2. Only the ticket equal to nextTicket can leave Pending, only with an empty slot.
   Its atomic cursor update increments nextTicket by exactly one and claims the slot.
3. The reciprocal cursor rule uses get(order) and getAfter(order) to require the
   actual same-stall Pending → Preparing transition. Advancing a cursor alone,
   inventing an order ID, skipping tickets or starting two orders cannot pass.
4. Preparing → Ready requires the slot to contain that exact order, and atomically
   clears it without changing nextTicket. The reciprocal cursor rule requires
   the actual Preparing → Ready transition. No standalone clearing/reset is allowed.
5. Ready → Completed cannot claim or release a slot. The cursor cannot be deleted.

Thus nextTicket is one plus the number of started orders; all lower tickets have
left Pending and all higher tickets are still Pending. The next start is FCFS,
and the single protected slot allows at most one Preparing order. Rules never
need a collection query or a client-supplied list of earlier tickets. Releasing
and starting another order require separate confirmed operations.

This proof assumes source data produced by accepted Stage 2C Rules. Existing
Pending records work without migration. Privileged/Admin edits are outside the
client security boundary; inconsistent imported data fails closed rather than
being repaired by weakening Rules. Do not manually reset/delete the cursor.

## Immutable history and client behavior

Only status, statusRevision, statusUpdatedAt and the appropriate transition
server timestamp may change on orders. Revisions are 1/2/3; legacy Pending has
implicit revision 0. preparingAt, readyAt and completedAt are recorded once and
retained. Header identity, owners, ticket, creation time, snapshots, totals,
payment and child item records remain immutable. Checkout code is unchanged.

The processing transaction reads the order and cursor, compares the displayed
status/revision and retries SDK transaction contention (maximum 8 attempts).
Stale actions fail; permission errors are never blindly retried. Duplicate
submissions are blocked in both service and UI. Server reads verify acknowledgement;
real-time streams discard pending local writes. Cached orders/cursors, loading,
errors and disabled environments block action buttons. Failed/uncertain writes
require refreshing/reviewing the server state before retrying; no optimistic
success badge or automatic second transition is used.

Only the isolated debug `main_emulator.dart` repository enables processing, with
the SAME strict synthetic named-app/demo-project/local-endpoint/explicit-flag
policy as accepted emulator checkout. Normal/release/production clients keep
processing disabled. The existing launcher still changes only the checkout gate
in its temporary local rules. Checked-in checkout and both deletion gates stay closed.

## Design sources

Inspected supplied V2-04 Vendor Orders Queued PNG and Full Design & Decision
Handover. Orange #FF7A00 actions, rounded white cards, prominent tickets, colored
readable badges, order time, foods/quantities and View Details are retained. The
current request overrides the older handover's concurrent-preparation policy and
hidden active-card totals. All/Pending/Preparing/Ready/History filters stay inside
Orders. The supplied ZIP does not contain later-state V3 PNGs; their written
color/action guidance is used without claiming a new screenshot approval.

## Verification checkpoint

Cloud: JavaScript syntax checks passed for new FCFS tests/helper and the extended
budget runner; git diff --check passed. Flutter/Dart SDK binaries and Firebase CLI
are unavailable. No candidate compilation, Flutter execution, Rules execution or
Android acceptance has occurred. The new emulator security suite is executable
but unverified; the FCFS invariant above is a design argument, not executed Rules
proof. Exact document-access/expression usage has not been measured.

`npm run test:fcfs` includes all previous 70 security cases plus FCFS cases. The
existing budget guard fails the whole run for access/expression exhaustion even
if a negative assertion observes permission-denied. Individual FCFS negative
cases also require permission-denied without a budget diagnostic. Raw coverage
and budget evidence are written to ignored test/firebase/artifacts.

Pending in this checkpoint: focused Flutter model/UI tests, final static review,
Cloud-supported regression checks, final Windows instructions and final backup.
Do not enable production processing or proceed to Stage 3B/3C without review and
successful local tests, including zero Rules-budget diagnostics.

## Final candidate verification (supersedes checkpoint pending list)

Implemented: all four Vendor states/actions, single-slot FCFS enforcement,
immutable snapshots/timestamps, live Student inbox/details, Vendor status filters,
loading/cache/error/refresh handling. Added 13 focused Flutter model/service/UI
cases and 19 Firebase security cases. Existing 70 security cases remain included
unchanged in `test:fcfs` (expected total 89). Earlier Flutter tests are preserved;
the old read-only Vendor test still verifies the normal closed environment.

Cloud actually executed:

- `node --test --test-concurrency=1 scripts/checkout_demo_launcher.test.mjs test/firebase/checkout_budget.test.mjs test/firebase/checkout_transport.test.mjs`:
  **11 passed, 0 failed** (7 launcher, 1 budget detector, 3 transport tests).
- `node --check` on fcfs_helpers.mjs, vendor_fcfs.test.mjs and
  run_checkout_tests.mjs: passed.
- `git diff --check`: passed.
- Compared the accepted checkout repository from its transaction/retry comment
  through the end of the file: unchanged byte for byte.

NOT executed: flutter analyze, flutter test (including the new 13 cases),
Firebase emulator security tests (all 89), Rules compilation, Rules-budget
measurement, Android/Pixel 6 acceptance. The source checkout lacks a usable
Dart/Flutter SDK binary; Firebase CLI/dependencies are unavailable. No SDK
installation/download was attempted. The earlier Chrome integration loading
stall remains a historical gap, not a passed test or a blocker for Android.

Static access-call review, counting repeated calls conservatively without
assuming cache savings: a start order write uses at most 4 document accesses,
its cursor write at most 9 (13 combined; first cursor creation uses fewer).
Release uses at most 3 + 7; completion uses the owner-profile access only.
Transaction reads add owner-profile checks; repeated paths are eligible for Rules
caching. This identifies bounded paths below the per-write 10 and atomic-write
20 limits for legitimate operations, but is NOT a measured expression count.
Emulator execution must still prove zero expression/access diagnostics for both
positive and adversarial cases; coverage/log silence alone is not an exact count.

New security coverage includes legacy records, two-food immutable receipts,
valid direct paired writes, skipped starts, single-slot blocking, cursor
forgery/reset/delete, unpaired writes, wrong role/owner/stall at every stage,
invalid states/revisions/timestamps, every immutable header field and child
items, direct stale replay, two starts in a batch, release/claim in one batch,
same-ticket and different-ticket concurrency, Ready/start races, independent
stalls, checkout/processing concurrency, same-ID recovery after processing,
Student real-time status delivery and a verified offline RPC transport cut.
Each race drains all submitted promises before cleanup. Offline verification uses
an independent connected client before bounded teardown; arbitrary errors,
permission failures, successful writes and timeouts cannot pass as offline proof.

The new JS transaction helper is an executable Rules-test counterpart of the
Dart service, not evidence that the actual Dart plugin compiled or ran. Flutter
widget tests use test doubles; only emulator tests can validate Rules. Production
processing remains client-disabled; demo processing is a local acceptance
candidate until all required local checks pass and are reviewed.

## Windows verification and Pixel 6 acceptance

Use synthetic accounts only, in your existing Windows clone. Stop previously
running demo emulators first so ports 8080/9099 are free. Open PowerShell at the
repository root (replace the path with your clone location):

```powershell
cd C:\path\to\FYP_Project
git fetch origin
git switch feature/stage-3a-vendor-fcfs
git pull --ff-only origin feature/stage-3a-vendor-fcfs
git rev-parse HEAD
flutter pub get
flutter analyze
flutter test
```

Compare HEAD with the exact final SHA supplied in the delivery report. If local
changes prevent switching/pulling, save them separately; do not reset or force.
Run the combined security suite before starting the interactive demo:

```powershell
cd test\firebase
npm ci
npm run test:fcfs
Get-Content artifacts\fcfs-budget-diagnostics.json
cd ..\..
node --test --test-concurrency=1 scripts/checkout_demo_launcher.test.mjs test/firebase/checkout_budget.test.mjs test/firebase/checkout_transport.test.mjs
```

Require **89/89 security tests** and an empty `budgetDiagnostics` array with
`childExitCode: 0`. The wrapper fails if the Firestore debug log is missing, even
if Node assertions pass. Keep artifacts/firestore logs for review. `npm run
test:checkout` remains the earlier 70-case regression entry point; `test:fcfs`
already includes it, so a separate repeated run is unnecessary when it passes.
Do not treat any new failure as accepted; share exact diagnostics.

In terminal A at the repository root, use the unchanged isolated demo launcher:

```powershell
.\scripts\start_checkout_demo.cmd
```

It generates disposable rules/config outside the repository, enables only the
checkout gate in that copy, refuses non-demo projects and leaves both Vendor
deletion gates closed. It starts Auth/Firestore for `demo-smart-canteen` only.
Never run `firebase deploy`. Do not use normal `main.dart` for this demo.

Start your Pixel 6 in Android Studio Device Manager. In terminal B:

```powershell
flutter devices
flutter run --debug -d emulator-5554 -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2 --dart-define=EMULATOR_CHECKOUT=true
```

Replace `emulator-5554` with the Android device ID from `flutter devices`. The
explicit flag enables both accepted local checkout and candidate local Vendor
processing through the already verified strict debug/demo gate. A run without
the flag, normal main.dart, release build or production project cannot enable
the real client actions. No additional Windows access is required.

1. Register a synthetic Vendor, complete setup, open the stall, create a category
   and one/two available foods. Register a synthetic Student; confirm two separate
   orders at that stall (quantities 1–20, at most two distinct foods each).
2. Vendor → Orders: tickets ascend; Pending badges are prominent; time, quantities
   and RM totals match the Student receipts. Only the earliest Pending start is
   enabled. Filtering does not change who is eligible.
3. Start Ticket #1. Its confirmed badge becomes Preparing; Ticket #2 stays disabled.
   A second tap or another stale Vendor client must not cause a second transition.
4. Mark #1 Ready. Its badge becomes green and #2 becomes eligible. Start #2 while
   #1 remains Ready; this is intentional. Mark #1 Completed ONLY after simulated
   collection. History retains its immutable receipt and ticket.
5. Student → Orders and an already open Order Details reflect Preparing, Ready
   and Completed from live streams. Students have no status actions. For a truly
   simultaneous demo, use a second local Android emulator/app client for the
   Student; otherwise switch accounts and verify fresh server state on return.
6. Disconnect a client from the local emulator. Cached orders/queue must be labeled,
   and mutations disabled once cache metadata arrives; an in-flight transaction
   cannot display a false acknowledgement. Reconnect, Refresh, review status and
   retry explicitly. Test another Vendor cannot see/process the first stall's orders.
7. Verify Dashboard/Open-Close, Menu, Stall Settings picture picker, Student Cart,
   Logout and the original four/five navigation tabs still work. Closing a stall
   blocks new checkout but does not block processing its already confirmed orders.

Stop Flutter with `q`, then stop terminal A with Ctrl+C and wait for emulator
shutdown/temporary-file cleanup. Demo data is disposable unless you explicitly
manage local export separately; no production data is involved. Preserve the
cursor and all orders together if retaining local demo data. Do not reset ticket
counters/cursors independently. Production checkout, Food Delete and Category
Delete remain closed. Stage 3B/3C require separate approval after these results.
