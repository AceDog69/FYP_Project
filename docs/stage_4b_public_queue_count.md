# Stage 4B — Student Home Orders in queue

29 October 2026 (Asia/Singapore).
Branch: `feature/stage-4b-public-queue-count`.
Verified GitHub base: `68d15b6d3d366ad102e8dc274f639cc97019d5f9` on
`feature/real-firebase-apk-pilot`, including Stage 4A Food Delete preparation and Student Orders repairs.
The delivery report gives the exact verified final GitHub SHA.

Only one new feature: each Student Home stall card shows **Orders in queue: N** from a confirmed,
privacy-safe aggregate. No Home ETA was added. Existing preparation-time text, card styling, search,
categories, Closed-stall browsing and View Menu navigation remain intact.
Absent, cached, malformed, denied, loading, pending-write or detached count streams show **Queue unavailable**.
An authenticated Student needs no order history to read a published stall's count.

## Exact public schema

Document: `stallQueueCounts/{vendorUid}`. Exactly seven fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | integer, exactly 1 | Projection schema |
| `vendorUid` | string | Same stall ID already used by the public listing |
| `lastTicket` | integer 0–2147483647 | Last confirmed ticket, mirrored from private counter; zero only after verified initialization |
| `nextTicket` | integer 1–lastTicket+1 | Next never-started ticket from the private FCFS cursor |
| `preparing` | boolean | Whether the single preparation slot is occupied |
| `count` | integer 0–lastTicket | Pending plus Preparing orders, not food quantities |
| `updatedAt` | server timestamp | Last projection publication/mutation; not an ETA or expiry clock |

There are no Student IDs, checkout/submission/order IDs, names, food snapshots, payment details or private
cursor references. Rules reject extra fields. Integer types are checked explicitly because Firestore numeric
equality alone can equate `1` and `1.0`. Client decoding is also strict.

Let L = lastTicket, N = nextTicket and P = preparing ? 1 : 0:

```text
count = L - N + 1 + P
```

This follows the existing contiguous-ticket, no-skips, single-slot FCFS invariant:

| Operation | Effect | Count |
| --- | --- | --- |
| Confirm new checkout | L increases by one | +1 |
| Retry same confirmed submission | No new writes/ticket | unchanged |
| Pending → Preparing | N increases by one; P 0→1 | unchanged |
| Preparing → Ready | N unchanged; P 1→0 | −1 |
| Ready → Completed | Counter/cursor unchanged | unchanged |

Tickets, snapshots, quantity limits and Student Queue/ETA calculations retain their original meanings.

## Consistency and privacy

Stage 4B checkout reads this sanitized document instead of `checkoutCounters`. It uses L to allocate the
next ticket and writes the private counter blindly in the SAME transaction as the existing order/request/items
and the new public projection. Rules still validate `resource.lastTicket + 1`, the canonical pending order,
prepared request, ownership, prices, membership, snapshots and total. A counter write additionally requires
the corresponding projection version/timestamp in that atomic request.

Vendor Preparing/Ready transactions read the same public document along with the existing order/private
cursor and atomically write cursor, existing queueProgress, status and projection. Cursor Rules require the
matching projection. Completion needs no count write. Thus checkout and processing contend on the same
document and cannot lose each other's updates. SDK transaction retries remain enabled; extra retries of
permission-denied require independently confirmed source version changes, not arbitrary authorization failures.

Projection Rules independently match the entire public map to the counter and private cursor AFTER the
atomic request. Student updates require a real +1 counter advance in that request. Vendor publication/repair
requires configured ownership and verified boundary-order authority. Direct partial/forged writes fail.
Deleting or listing projections is denied. Counter reads become **owning configured Vendor get only**;
Students cannot read/list the private lastOrderId, including during checkout or retry recovery.

Student projection gets also check agreement with the CURRENT counter/cursor. An old-client write under a
rolled-back policy therefore cannot leave a stale summary that passes a later Stage 4B server read. Cached
snapshots are unavailable regardless of their numbers. A timestamp can be old while the count remains correct:
agreement with current authority, not wall-clock age, defines validity. Owner gets can inspect an invalid public
mirror so the guarded owner publication transaction can repair that mirror without modifying authority.

Existing `queueProgress` data/schema, FCFS policy and Student queue/ETA formulas are unchanged. This adds
one per-stall contention point and dependent Rules reads/listeners; it is an FYP-scale client/Rules design,
not a claim of unlimited throughput. No Functions, paid services, billing changes or new dependencies.

## Existing-stall initialization — implemented, not performed live

With Stage 4B mode explicitly enabled, the owning Vendor opens **Orders**. On a server-confirmed cursor,
the existing progress publication runs first, then an idempotent transaction initializes/repairs the count.
It reads the private counter, private cursor and existing summary from the server. It verifies the counter's
last-order boundary and any Preparing-order boundary, cursor revision and numeric bounds before publication.
Rules verify the same authority relationship. No order scan, counter reset, ticket rewrite or source migration.

- Both authoritative documents absent under the accepted no-delete Rules: verified initial L=0/N=1/P=0, zero.
- Counter present/cursor absent: verified confirmed tickets have not started; count is L.
- Existing Preparing/Ready/Completed states: use the actual counter/cursor; preserve all IDs and history.
- Malformed/inconsistent authority or missing referenced boundary order: fail closed; investigate manually.
- Missing summary alone: NOT zero. Student Home stays unavailable; Stage 4B checkout asks for Vendor initialization.

Publication is serialized with checkout/processing and can repair only the public mirror. It is not a tool for
reconstructing arbitrarily deleted/edited Admin data. The proof assumes canonical authorities maintained by
the accepted Rules; a human administrator can bypass any client Rules. Halt and review backups if authority
documents were manually changed or lost. No live backfill, reset, migration or initialization occurred in Cloud.

## Separate opt-in and Rules candidates

The existing default Rules, ordering pilot Rules, Stage 4A deletion candidate/config and their generators
are byte-for-byte unchanged. Their currently deployed behavior has not been altered or inspected in Cloud.
In particular the existing live counter-read concern is not fixed until a later reviewed Stage 4B activation.

New review artifacts:

- `pilot/firestore.stage4b.rules` / `firebase.stage4b.json`: Stage 4B with checkout true, Food Delete false.
- `pilot/firestore.stage4b.closed.rules` / `firebase.stage4b.closed.json`: same feature/integrity/privacy,
  checkout false, Food Delete false.
- `scripts/prepare_stage4b.mjs`: reproducibly generates both candidates from the conservative default;
  refuses changed anchors/deletion-enabled input. It never connects to or deploys Firebase.

Client opt-in: `--dart-define=STAGE4B_QUEUE_COUNTS=true`, in addition to the existing appropriate ordering
activation. Default false preserves existing pilot and emulator ordering behavior. The flag alone cannot
enable checkout/processing or deletion. Home attempts only the sanitized get and degrades to unavailable
when the backend does not support it. No fallback to a private counter is permitted in Stage 4B checkout.
The existing emulator launcher is unchanged and still runs the old workflow; use the new config below for 4B.

Do NOT mix old ordering clients with Stage 4B Rules: old Student counter reads and old writes omitting the
projection fail closed. Do NOT use the new write flag against old Rules; publication/checkout will fail.
Do not pass the Stage 4A Food Delete activation flag for this batch. Category Delete remains denied.

## Cloud tests actually executed

Final complete emulator run: **149 passed / 0 failed**, comprising **105 preserved emulator cases + 44
Stage 4B cases**, with **zero Rules-budget diagnostics**, child exit code zero and debug-log evidence present.
The user reported 111 previous security tests; this repository's unchanged emulator runner registers 105.
The handover distinguishes emulator counts from separate Node unit checks rather than assuming 111 ran.
All existing security source files were preserved, including Stage 4A additions.

Covered: verified empty/no-order-reader, one/two-food and max-quantity checkout, same-ID/parallel retries,
sequential tickets, multiple stalls, Start/Ready/Completed counts, concurrent processing/checkout/bootstrap,
missing/forged summary/counter/snapshot/price/category/quantity/owner/total, missing canonical food/category/
membership, unavailable food, FCFS skipping/second slot, direct writes, private reads, legacy state bootstrap,
malformed/stale mirrors and integer-vs-double fields. Negative assertions require permission-denied without
budget exhaustion. Fresh synthetic databases isolate races; no clearFirestore during active transactions.
The migration fixture was corrected to use the installed test library's initialization API; final run passed.

Additional Node checks: **21/21 passed**, including unchanged launcher, Stage 4A/pilot, budget-detector and
transport tests plus Stage 4B generation/equivalence tests. Existing canonical snapshot and progression
functions are compared to their original bytes; no security validation was removed to fit budgets.

Installed existing locked Node test dependencies and Firestore emulator 1.22.0 in Cloud (Node 24, Java 21).
Every execution used loopback-only services and synthetic `demo-*` projects. No live Firebase access.
Runner: `test/firebase/run_stage4b_tests.mjs`; diagnostic output:
`test/firebase/artifacts/stage4b-budget-diagnostics.json`; raw per-test coverage is also saved under artifacts.
Logs/coverage are local ignored artifacts, not credentials or a production export. They do not provide exact
per-request expression counts; no such numeric claim is made. Rules limits remain 1,000 expressions and
10/20 document accesses as applicable. Observed tests/logs, not UI passes, supply the security evidence.

**Not executed:** Flutter analyze, Flutter tests, Dart compilation, Android build/manual acceptance or APK
publication. Flutter/Dart/Android tooling is unavailable. Ten new Dart tests (4 model/default-gate and 6 widget)
are written but unexecuted. All previous 176 Flutter test sources are preserved. Lexical delimiters,
whitespace and source scope were checked; these are not a substitute for Dart analysis.

## Windows CMD verification (local demo only)

Save personal work before switching. Match HEAD to the delivery SHA:

```bat
cd /d C:\path\to\FYP_Project
git status
git fetch origin
git switch feature/stage-4b-public-queue-count
git pull --ff-only origin feature/stage-4b-public-queue-count
git rev-parse HEAD
flutter pub get
flutter analyze
flutter test test/public_queue_count_test.dart
flutter test
node scripts/prepare_stage4b.mjs
git diff --exit-code -- firestore.rules pilot/firestore.stage4b.rules pilot/firestore.stage4b.closed.rules
node --test --test-concurrency=1 scripts/*.test.mjs test/firebase/checkout_budget.test.mjs test/firebase/checkout_transport.test.mjs
```

Stop any manually running demo emulators, then run the complete preserved + Stage 4B security suite:

```bat
cd test\firebase
npm ci
node node_modules\firebase-tools\lib\bin\firebase.js emulators:exec --project demo-smart-canteen --only auth,firestore --config ..\..\firebase.stage4b.json "node run_stage4b_tests.mjs"
type artifacts\stage4b-budget-diagnostics.json
cd ..\..
```

Require every case passing, childExitCode zero, empty budgetDiagnostics and the runner's log-evidence check.
This runner includes the same seven baseline security files; do not substitute an UI test for Rules proof.
It refuses a non-demo project/non-loopback emulator environment.

For Pixel 6 local acceptance, start two Android clients for Vendor and Student. Terminal A at repository root:

```bat
node test\firebase\node_modules\firebase-tools\lib\bin\firebase.js emulators:start --project demo-smart-canteen --only auth,firestore --config firebase.stage4b.json
```

Terminal B (replace the device ID if needed):

```bat
flutter devices
flutter run --debug -d emulator-5554 -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2 --dart-define=EMULATOR_CHECKOUT=true --dart-define=STAGE4B_QUEUE_COUNTS=true
```

Run the same command in Terminal C with `-d emulator-5556` for the other Android client.
Use only synthetic local accounts. Vendor sets up/publishes a stall, opens it and visits Orders once to
initialize. Student who has NEVER ordered should see verified zero on Home after server confirmation.
Confirm two orders: Home 0→1→2; Vendor Start leaves 2; Ready gives 1; Completed leaves 1. Finish the second
ticket to reach zero. Repeat across two stalls; verify search/category/scroll/navigation at Pixel 6 and small/
large-text settings. Disconnect the Student transport: cached counts must become unavailable, never zero.
Reopen Home after a terminal listener error to retry. Confirm existing Orders, Queue/ETA and Ready alerts,
two-food/quantity bounds, both deletion gates and account isolation. Windows/Android acceptance is pending.
Stop Flutter with q and local emulators with Ctrl+C. Do not build/publish an APK or run a deployment command.

## Future activation/bootstrap plan — review only, no live steps authorized now

1. Complete Windows tests and manual acceptance on this exact commit. Back up the actually deployed Rules
   and canonical authorities using approved project procedures; do not overwrite them with assumed zeros.
2. Coordinate a short maintenance window and updated clients. A future approved deployment can first use
   the Stage 4B CLOSED candidate to block new checkout while retaining privacy and reciprocal validations.
3. Each owning Vendor, using an explicitly activated updated ordering build plus Stage 4B flag, visits Orders
   to verify/publish its own mirror. Compare the result with its real Pending/Preparing orders. Any inconsistency
   stops that stall's migration; no batch Admin backfill or counter rewrite is supplied by this feature.
4. Only after all required stalls and clients are accepted should a separately authorized deployment consider
   the Stage 4B ordering candidate. Retain old clients only for read-only uses; their incompatible writes fail.
5. A safe stop uses the Stage 4B CLOSED candidate and disables client ordering as appropriate. A full legacy
   rollback restores that policy's former counter visibility and disables Home count reads; coordinate client
   flags and do not treat old stored projection data as current. Never delete/reset counters to roll back.

This is a review plan, not permission to execute live deployment/backfill. Default conservative Rules and the
existing deployed ordering pilot are unchanged. Stop after Stage 4B; no Category Delete, four-food checkout,
parallel preparation, Home ETA, background push, billing change, merge or APK publication.
