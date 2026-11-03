# Stage 4 integrated pilot — review candidate

3 November 2026 (Asia/Singapore). Branch: `feature/stage-4-integrated-pilot`.
Verified GitHub base: `a4c1e2f5825533522a988d0270f9ae46c67bbf81` on
`feature/stage-4b-public-queue-count`, including the Windows queue-count widget-test correction.
User-reported acceptance of that base: 186/186 Flutter tests and 149/149 Firebase emulator tests.
The delivery report identifies the exact integrated commit; verify it before local acceptance.

This candidate combines existing public queue counts and paired Vendor Food Delete. It removes the
Category Delete button/explanation without changing category records, repository behavior or Rules.
Add/Edit Category remain available. No other feature, checkout/FCFS transaction or queue/ETA calculation changed.

## Combined Rules and default safeguards

- New `pilot/firestore.stage4-integrated.rules` is **byte-for-byte the Stage 4B ordering candidate except**
  `function menuDeletesEnabled() { return false; }` becomes `return true;`.
- `firebase.stage4-integrated.json` selects only that candidate, with loopback demo emulator endpoints.
- `node scripts/prepare_stage4_integrated.mjs` generates the candidate locally. It checks that the Stage 4B
  input still equals its original generator output. It accepts no project/deploy arguments and contacts nothing.
- Default `firestore.rules`, default config, Stage 4A/4B candidates/configs and old launchers remain unchanged.
- Category document deletion remains unconditionally denied. The existing name-reservation deletion allowed
  during an atomic rename remains intact; it does not authorize category deletion.
- Food Delete still requires a configured owning Vendor, matching existing food/membership/category,
  and absence of BOTH food and membership after the same atomic request. An orphan cannot be deleted or
  silently repaired by this operation. A direct owning-client paired delete is authorized; the application
  transaction additionally rejects stale displayed revisions, rechecks membership and retries concurrent reads.
- No order path is deleted. Confirmed immutable food/price/quantity/payment snapshots survive menu deletion.
  Missing/deleted food invalidates an outdated Cart or prepared checkout, even if a payload was built earlier.

All Stage 4B count/privacy/counter/FCFS checks are identical. Public schema remains exactly
`stallQueueCounts/{vendorUid}`: schemaVersion, vendorUid, lastTicket, nextTicket, preparing, count, updatedAt.
`count = lastTicket - nextTicket + 1 + (preparing ? 1 : 0)` counts Pending + Preparing.
Checkout increases it once, Start leaves it unchanged, Ready decreases it once, Completed leaves it unchanged.
One/two distinct foods, quantities 1–20, integer sen, single-stall Cart, idempotency and simulated payment remain.
See [the accepted Stage 4B proof/bootstrap specification](stage_4b_public_queue_count.md) for the invariant.

## Client activation remains explicit

All real-project flags default off. Existing real-ordering project, Auth/default-app, Android, canonical
Firestore host and TLS checks are unchanged. A later authorized integrated build requires all four defines:

```text
REAL_ORDERING_PILOT=true
REAL_ORDERING_PROJECT=fyp-app-9d78a
STAGE4B_QUEUE_COUNTS=true
REAL_MENU_DELETION_RULES_ACTIVE=true
```

These are operator attestations, **not proof of deployed server Rules**. A server rejection preserves the menu
and displays a failure, not success. Rules grant eligible project users the reviewed operations; client flags
are not an access allowlist. Never distribute an integrated ordering build before the matching server policy.

For local Android acceptance only, `main_emulator.dart` now provides a guarded menu repository when
`EMULATOR_FOOD_DELETE=true`. It also requires the existing emulator checkout eligibility and Stage 4B mode:
debug build, synthetic named app/options, `demo-smart-canteen`, completed emulator routing, permitted local
non-TLS endpoint, `EMULATOR_CHECKOUT=true` and `STAGE4B_QUEUE_COUNTS=true`. Without any prerequisite,
Food Delete remains disabled. The real-project wrapper never reads the emulator flag. Ordinary main.dart,
normal/release builds and real projects cannot activate deletion through this synthetic flag.

## Verification evidence

Cloud final complete run: **223/223 case executions passed, zero failures/skips**, comprising the complete
149-case accepted Stage 4B baseline and 74 combined-policy executions (19 menu + 44 public-count + 11 new
integration cases). The 63 menu/count cases are reruns against the combined policy, not 63 new unique tests.
Both phases exited zero; nonempty debug-log evidence was present; **zero Rules-budget diagnostics**.
Additional Node generator/launcher/transport/budget checks: **25/25 passed**. JavaScript syntax and
`git diff --check` passed. Existing locked dependencies were installed; no dependency versions changed.
No Flutter/Dart executable SDK or Android runtime is usable in this Cloud workspace; the Flutter source checkout
has no Dart binary. Analysis, compilation, Flutter tests and Android acceptance must run on Windows. No SDK
download or APK build was attempted. Prior Windows results describe the base, not this new commit.

The new runner first runs every accepted Stage 4B security case with its original policies. It then runs the
entire menu and public-count suites again against the combined candidate plus explicit integration attacks.
The separate closed/default/legacy fixtures intentionally retain their policies to prove gates and bootstrap.
An environment selector changes only the candidate loaded by two existing suites; default invocation is unchanged.
Negative integration assertions require permission-denied without budget exhaustion. No arbitrary exception,
timeout or failed security check is accepted as success. Races settle all sibling operations before cleanup.

The integration cases cover available/unavailable paired deletion, partial/mismatched/foreign deletion,
unchanged categories/order snapshots, deleted-food and edited-food stale checkout, stale revision rejection,
delete/checkout races, exact count progression after deletion, same-ID recovery, independent stalls,
old incompatible writes, privacy and forged order/count changes combined with deletion. Rerun menu/count
cases additionally cover edit/reassignment races, canonical snapshot integrity, concurrency, legacy bootstrap,
malformed mirrors, integer types and closed deletion/checkout gates.

Runner budget guard scans client output and new Firestore debug-log bytes, requires nonempty log evidence,
and fails on any Rules expression/document-access budget diagnostic even if a negative test would accept it.
Artifact: `test/firebase/artifacts/stage4-integrated-budget-diagnostics.json` (ignored, not committed).
No exact per-request expression/access count is inferred from log silence. Emulator success is not live acceptance.

## Windows CMD verification — local only

Save personal changes before switching branches. Match HEAD with the delivered GitHub SHA:

```bat
cd /d C:\path\to\FYP_Project
git status
git fetch origin
git switch feature/stage-4-integrated-pilot
git pull --ff-only origin feature/stage-4-integrated-pilot
git rev-parse HEAD
flutter pub get
flutter analyze
flutter test test/vendor_menu_test.dart test/vendor_ui_polish_test.dart test/emulator_checkout_policy_test.dart test/real_ordering_pilot_test.dart test/public_queue_count_test.dart test/student_cart_test.dart test/checkout_orders_ui_test.dart
flutter test
node scripts/prepare_stage4_integrated.mjs
git diff --exit-code -- firestore.rules pilot/firestore.stage4b.rules pilot/firestore.stage4b.closed.rules pilot/firestore.stage4-integrated.rules
node --test --test-concurrency=1 scripts/*.test.mjs test/firebase/checkout_budget.test.mjs test/firebase/checkout_transport.test.mjs
```

Stop any manually running local emulators. From the repository root:

```bat
cd test\firebase
npm ci
node node_modules\firebase-tools\lib\bin\firebase.js emulators:exec --project demo-smart-canteen --only auth,firestore --config ..\..\firebase.stage4-integrated.json "node run_stage4_integrated_tests.mjs"
type artifacts\stage4-integrated-budget-diagnostics.json
cd ..\..
```

Require every phase passing, every childExitCode zero, debugLogEvidence true, and budgetDiagnostics empty.
The runner refuses any non-demo project or non-loopback service. Do not substitute `--focused` for final verification.

## Pixel 6 synthetic acceptance — no APK build

Terminal A at repository root:

```bat
node test\firebase\node_modules\firebase-tools\lib\bin\firebase.js emulators:start --project demo-smart-canteen --only auth,firestore --config firebase.stage4-integrated.json
```

Terminal B, Vendor client (replace IDs using `flutter devices`):

```bat
flutter devices
flutter run --debug -d emulator-5554 -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2 --dart-define=EMULATOR_CHECKOUT=true --dart-define=STAGE4B_QUEUE_COUNTS=true --dart-define=EMULATOR_FOOD_DELETE=true
```

Run the same command in Terminal C with `-d emulator-5556` for the Student. Use only synthetic local accounts.

1. Vendor sets up a stall, adds/renames categories, adds foods, opens the stall and visits Orders to initialize.
   Confirm Manage Categories has Add/Edit and no Delete button or unavailable-delete explanation.
2. A never-ordered Student sees verified zero on Home. Check search, filter scrolling and View Menu navigation.
3. Student adds a food to Cart; test individual removal and clear Cart. Add it again, then Vendor deletes it:
   Cancel changes nothing; Confirm removes it only after acknowledgement. Category remains. Stale Cart cannot order it.
4. Create two confirmed orders before deleting their food. Verify immutable details/items/totals still display.
   Home count 0→1→2; Start stays 2; Ready becomes 1; Completed stays 1. Finish the second to reach zero.
   Confirm existing Student Queue/ETA and foreground Ready notification behavior, without logging Student out.
5. Check another stall is independent; a different Vendor cannot edit/delete the first stall's foods.
   Cached/offline menu disables destructive actions. Cached/absent/unverified Home count says Queue unavailable.
6. Stop local emulators before a fresh menu delete and confirm no false success. Restart, reload and inspect actual
   server state before retrying. Rebuild/run without EMULATOR_FOOD_DELETE: Food Delete is disabled again.
7. Check Pixel 6 and smaller/enlarged-text layouts. Orders single-slot FCFS, two-food limit and navigation must remain.

Press q in each Flutter terminal and Ctrl+C in the emulator terminal. No real Firebase connection is required.

## Future live transition — separate explicit approval REQUIRED; do not execute now

This is an operator review plan, not current permission. No live deployment, connection, migration, data
deletion, ticket reset, APK build or publication occurred in Cloud. Execute no step below until approved.

1. **Accept the exact commit locally.** Complete the commands/checklist above. Schedule a maintenance window,
   identify every required stall/client/operator, stop new ordering and menu changes by agreement, and record
   the exact project/database. Do not assume repository Rules are the currently deployed Rules.
2. **Back up actual active Rules.** After approval, open Firebase Console for the verified project, Firestore →
   Rules. Save the complete currently published source and version/publication timestamp outside this repository.
   Compare with pilot files; record SHA-256 (`certutil -hashfile C:\private-backup\active.rules SHA256`). Keep
   a second private copy and confirm the exact source is available for recovery. Do not publish local default
   Rules as a presumed rollback. A config/Rules candidate is not a deployed-policy backup.
3. **Protect existing data.** Record and retain an approved private recovery copy of menu food/membership pairs,
   categories/name reservations and canonical checkoutCounters/vendorQueues/queueProgress/orders, including
   immutable order items. Use existing approved backup procedures; this task supplies no live export/backfill
   tool and adds no paid service. If a reliable recovery copy is unavailable, postpone activation, especially Food
   Delete. Preserve Auth/users/roles and all IDs/timestamps. Never put private data or credentials in Git.
4. **Enter closed-checkout maintenance.** Once authorized, an operator may activate the existing
   `firebase.stage4b.closed.json` candidate (checkout false, Food Delete false, Stage 4B integrity/privacy intact).
   Verify the actual published source/version. Pause order processing briefly for reconciliation. Closed Rules
   preserve reads, existing orders, guarded owner bootstrap and secure status transitions; they do not erase
   pending requests or stop every possible Vendor write. Coordinate the pause rather than assuming it is a lock.
5. **Initialize as each owner.** Use the updated Android client with REAL_ORDERING_PILOT, exact project and
   STAGE4B_QUEUE_COUNTS flags; keep the real deletion flag false during maintenance. The owning Vendor opens
   Orders. Its existing guarded server transaction checks actual counter/cursor/boundary orders and publishes
   only the mirror. Never infer zero from a missing mirror or reset a counter. Inconsistent/missing boundary
   authority halts that stall; investigate the private backup. No Admin mass backfill is supplied.
6. **Validate every stall.** Maintain a private checklist of stall, owner verification, lastTicket, nextTicket,
   preparing, resulting count and acceptance time. Compare with that owner's actual Pending/Preparing tickets
   under the agreed pause; Ready/Completed must be excluded. Verify a different, never-ordered Student can see
   the count but cannot read private counters/orders/requests. Any unavailable/mismatched required stall blocks
   general reactivation. Bootstrap assumptions require canonical records maintained by the accepted no-delete
   Rules; it does not reconstruct arbitrary privileged corruption.
7. **Activate the combined policy only after another explicit go decision.** The future operator must select
   `firebase.stage4-integrated.json`, verify its exact source/hash and the displayed project before publishing,
   then verify the actually published Rules. The only difference from Stage 4B ordering is paired Food Delete.
   This document intentionally supplies no automatic live deployment launcher. Category Delete stays denied.
8. **Prepare updated clients after approval.** Review the existing Android signing configuration and use the
   accepted artifact/commit. A future approved build command at repository root is:

   ```bat
   flutter build apk --release --dart-define=REAL_ORDERING_PILOT=true --dart-define=REAL_ORDERING_PROJECT=fyp-app-9d78a --dart-define=STAGE4B_QUEUE_COUNTS=true --dart-define=REAL_MENU_DELETION_RULES_ACTIVE=true
   ```

   Do not run it for this task. Signing is unchanged. Privately record the resulting APK hash/version/commit;
   do not include EMULATOR flags or synthetic entry points in a real pilot APK. Test on approved Android devices
   before distribution; this preparation neither builds nor publishes an artifact.
9. **Replace incompatible APKs.** Old pilot clients read private counters, omit queue-count checkout writes and
   omit count writes during Vendor transitions. Stage 4B/combined Rules deny those reads/writes safely. New
   clients with Stage 4B flag off are also incompatible. Old Rules with new Stage 4B flag on reject the new
   projection protocol. Retire ordering-capable old APKs; do not weaken Rules to support both. Retain pending
   submissions and revalidate/retry/discard using the updated UI; never manually mark them confirmed or
   allocate a replacement ticket. Same-ID confirmed recovery remains supported after food deletion.
10. **Controlled manual acceptance.** After authorization, use explicitly approved pilot accounts/data and the
    two-client scenarios above: counts, FCFS, preserved historical snapshots and deliberate Food Delete.
    Actual deletion is irreversible without the private recovery copy. No real data deletion is authorized now.
    Observe failures and stop if counters/progress/count disagree; never repair by assigning zero.

## Safe stop and rollback — preserve data and protocol

- Stop new checkout and Food Delete by restoring the reviewed Stage 4B CLOSED candidate, subject to operator
  approval. Verify published source. Disable/distribute client ordering/deletion flags as appropriate; build
  flags alone do not revoke a previously installed client's server permission.
- For a Food Delete-only rollback while ordering remains approved, the unchanged Stage 4B ordering candidate
  closes deletion while preserving the new queue-count/private-counter protocol. Reconcile count state before
  reopening any checkout. No data migration is needed between these policies.
- Keep the updated Vendor client for guarded mirror inspection/repair and secure processing during a coordinated
  stop. Do not delete counts, counters, cursors, pending requests or orders. Never renumber tickets.
- A full legacy Rules rollback restores its older counter-read exposure, loses Stage 4B write coupling and denies
  count reads. It requires a separate security review and coordinated compatible clients. Stored summaries can
  become stale under legacy writes; do not display them as current or reopen Stage 4B without owner verification.
- Rules rollback does **not** restore deleted foods, memberships or APKs. Any recovery of actual menu data needs
  a separately reviewed private-backup restore preserving IDs and revisions; this task provides no restore tool.
- Halt and investigate unexpected authority loss/corruption. Neither client flags nor changing Rules repairs
  data. Keep both backups and an audit of the published versions; do not bypass security checks to resume.

Stop after the integrated candidate. No Home ETA, Category Delete, parallel preparation, four-food checkout,
background notifications, live Firebase access or production action is included in this authorization.
