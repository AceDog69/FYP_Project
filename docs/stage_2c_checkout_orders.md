# Stage 2C — checkout and immutable Pending orders

Required base verified through GitHub: `7ba35a219b5f3267d1b95941265a7166cc70b024`,
the user's latest Stage 2B verification-fix commit. Branch:
`feature/stage-2c-checkout-orders`. No main update, deployment or Stage 3 work.

## Original core checkpoint (historical)

Core schema, proposed Rules validation and Firestore transaction/recovery service
are implemented. **Checkout writes and real-client confirmation remain disabled**
until executable proof passes and is reviewed. Flutter/Dart SDK and Firebase CLI
are unavailable; the inherited network proxy fails to connect. No repeated SDK
download is attempted. UI, reproducible tests and final acceptance notes are pending
at that intermediate checkpoint. GitHub verified its backup at
`dc40fe4bb42c570caa42e291ae3ebfeddea39e48` before UI/tests work continued.

## Bounded schema and invariants

| Path | Contents / permissions |
| --- | --- |
| `users/{studentUid}/checkoutRequests/{submissionId}` | Durable bounded draft, owner, vendor, expected prices/revisions, simulated method, total, timestamps, pending/confirmed/cancelled terminal state. Owner-only reads. |
| `orders/{submissionId}` | Immutable header and first item snapshot, owner/vendor, sequential ticket, Pending status, simulated payment, total, time and preparation-time snapshot. Student owner / stall owner reads only. |
| `orders/{submissionId}/items/{1,2,3}` | Remaining immutable item snapshots, present exactly as required by header itemCount. Same parent ownership. No item 0 child or arbitrary extra children. |
| `checkoutCounters/{vendorUid}` | schemaVersion 1, vendorUid, lastTicket, random opaque lastOrderId, server update time. First confirmed ticket 1; updates exactly +1. No resets/deletes. |

Each item is a stable food ID plus immutable name, description, category ID/name,
picture ID, integer unit price, quantity, subtotal and food revision. Maximum four
distinct IDs, quantity 1–20, price 1–100000 sen. Requests contain bounded expected
snapshots; they are not confirmed orders. Confirmed orders are immutable Pending
records. No Ready/Preparing/Completed/Cancelled **order** transition exists.

The first item lives in the header to keep bounded verification below the
per-write access ceiling. Header validates that item canonically, requires every remaining
item after-state, and binds the total, authenticated Student, canonical Open stall,
immutable request and counter. Each remaining item's own create rule validates canonical
food/category/membership and the request. Header count requires every slot; child
rules forbid extra slots. Draft IDs are distinct and immutable, preventing duplicate
foods or mixed stalls. Food availability, ownership, name/description/picture,
price/revision, category name/ownership and membership must match canonical data.
Stale Cart data fails instead of silently changing the confirmed amount.

Students cannot read private raw stalls or membership documents. The transaction
reads the protected public listing, available foods and categories; **Rules** read
the canonical private stall and membership at commit. Existing publication rules
require canonical stall changes to update that listing atomically. Source validation
is not replaced by trusting the public listing or Flutter code.

## Ticket and idempotency protocol

A 20-character random submission ID is both request ID and immutable order ID.
The request is first prepared durably in its owner's namespace. Confirmation reads
that request plus current listing/foods/categories/counter, then atomically creates
the order/items, advances one stall's counter and marks the request confirmed.
No ticket is consumed by a draft. Repeating confirmation of a confirmed request
loads the same existing receipt, without another counter write or source revalidation.
An interrupted acknowledgement keeps the same identity for retry.

Counter update must point to an order whose ticket is exactly the new counter.
By induction, an existing order at that stall has ticket <= current lastTicket;
it cannot justify another increment. Counter creation is exactly 1 and counters
cannot reset/delete. An existing header cannot be rewritten. This blocks detached
increments, reused orders, duplicate tickets and multiple same-stall headers sharing
one increment. Different stalls have independent counters. No daily reset or queue
runtime initialization is added to Stall Setup; existing stalls lazily get a counter
only with their first confirmed checkout. Unexpected legacy counter shapes fail closed.

Safely discarding an **unconfirmed request** serializes on that same request doc.
If no request exists after interrupted preparation, a cancelled tombstone is created.
If pending, it becomes terminal cancelled only when no owning order exists. If
already confirmed, discard returns the existing receipt instead of cancelling it.
A concurrent prepare/confirm must retry or fail against the terminal request. This
is distinct from cancelling a confirmed order, which remains forbidden.

No success is returned from local pending snapshots. After transaction acknowledgement,
the service reads header/items from the server and verifies the complete receipt.
Network failure in that final read remains an unknown result requiring same-ID
recovery. Persistent pending requests support recovery after an app restart; confirmed
orders remain in Student Orders even when the in-memory Cart has disappeared.

## Budget / proof status — focused repair

The original static estimate did **not** establish feasibility: the user's Windows
run at `001555044cabb2ffad3f1e0c0b72961ede40e7c4` actually exhausted the
1,000-expression limit for three/four products and malformed batches. It also
reported contention, race cleanup and offline assertion failures. No claim that
the old design fits the Rules budget remains valid.

The repair retains the bounded schema and four distinct products. It reduces
repeated evaluation rather than trusting client data:

1. Preparation still enforces the exact eight-field draft item shape, all bounds,
   distinct IDs and the integer sum. Confirmation cannot change those fields.
2. Each snapshot uses a map diff to bind every draft field, and exact map equality
   against canonical food and category data to bind the entire ten-field shape,
   revision, picture, price, quantity and computed subtotal. Integer types remain
   explicit. Food owner/availability, category owner/name/nameKey/revision/timestamps
   and exact two-field membership are still checked. Missing sources fail closed.
3. The header validates its inline first item, requires slots 1–3 when applicable,
   and equals an exact canonical header map, including immutable draft total.
   Each child is validated canonically **once in its own create rule**. That rule
   binds the parent, owner, current creation time, slot and matching draft. It
   cannot create an orphan or extra slot; headers/items cannot be changed/deleted.
   Consequently every required child is a validated snapshot of its unique draft
   slot, each subtotal equals its unit price times quantity, and the header total
   equals their sum via the immutable prepared sum. Recomputing the same checks
   in the header is unnecessary. This inductive invariant assumes data written
   through these rules, not arbitrary privileged/Admin-created corrupt orders.
   Tests explicitly reject detached/extra children and exercise reversed write order.
4. Counter/header exact maps and helpers bind after-state maps once. Ticket 1,
   increments of exactly 1, upper bounds, owner, linked order and immutable fields
   remain protected. No separate ticket reservation can consume a ticket.

The four-distinct-category write authorization still has a conservative static
estimate of ten header accesses and twenty distinct document states overall,
**assuming cache reuse**: twelve item source documents, profile, raw stall,
request-after, counter-after, header-after and three child existence-after states.
No lookup or expression total is measured here; transaction read authorization
also needs runtime verification. This repair is a candidate, not proven to fit.
Do not enable it until the entire local runner passes with no budget diagnostics.

`npm run test:checkout` now runs through `run_checkout_tests.mjs`. It preserves
all earlier 46 cases, captures client output and checks new Firestore debug-log
bytes for expression/access exhaustion. A missing/empty debug log fails verification.
Thus an `assertFails` that merely encounters the budget ceiling cannot produce
successful suite proof. Checkout negative assertions additionally require
`permission-denied`, reject budget text, and have maximum-size positive controls.
Raw per-case coverage and a budget diagnostic summary are ignored artifacts, not
fabricated per-request measurements. A clean log alone is not proof: all positive,
negative and concurrency assertions must also pass. Coverage absence is reported.

Checked-in `checkoutWritesEnabled()` and real repository `canCheckout` remain
false. Both Vendor delete gates are unchanged. No deployment, migration, billing
change or paid service is introduced.

## UI, lifecycle and local acceptance status

Checkout Review is reachable only for a current eligible Cart (or to resolve an
existing request). It displays stall/items/quantities/unit prices/integer total,
three simulated methods and an explicit no-money-charged message. **Confirm Order
is disabled in the real app in this commit**, with the security-verification reason.
There is no runtime/Dart-define bypass. A test-only fake enables confirmation for
widget/controller tests; the security suite opens only the literal gate in an
in-memory emulator rules string, never the checked-in file or live rules.

The implemented controller retains the same request identity across route retries,
prevents repeated submits, locks Cart mutations while an outcome is unresolved and
preserves all items on failure. Safe server discard unlocks that Cart without
removing its contents. Only a complete server-confirmed receipt clears a matching
local Cart version. Resuming a persisted draft from Orders preserves an unrelated
new Cart on success. Disposed sessions ignore late responses and cannot clear a
different Student's Cart. A committed-but-unacknowledged request is recovered by
same-ID retry or safe discard returning the existing receipt.

Student Orders reads only own orders and pending requests, shows ticket/stall/
immutable items/quantities/confirmed total/time/Pending status, details, empty,
loading, cached and error/Retry states. Pending requests are explicitly not tickets;
cached pending requests cannot be resumed until current. After restart, use Resume
on a server-confirmed pending request. Confirmed requests disappear from that list
and their immutable orders remain in history. Real checkout writes remain gated,
so no new order can be demonstrated through this build until proof/review/enabling.

Vendor Orders reads only its own stall's confirmed Pending orders in ticket order,
with snapshots, quantities, total, timestamp, details and live arrival. It is read-only.
No Start Preparing, Ready, Completed, Cancelled, queue position, ETA or notifications.
Student Queue remains its existing placeholder. Dashboard/Menu/Profile, Student
Profile layout and both navigation tab counts are preserved. UID-scoped routing
from the verified Stage 2B base remains unchanged.

All 23 PNGs, picture IDs, dependencies/lockfiles, Stage 1 setup/authentication code,
Dashboard/status/settings implementations, menu/catalog implementations, normal/
emulator entry points, debug cleartext permission and Windows launcher are preserved.
Auth repository only exposes the new order service. The inherited Student food
selection nullability fix, targeted fake-stream error fixes and Stage 1 Closed
setup fixtures are retained. S2-04/05/06/07 PNGs are absent from supplied ZIPs; the
approved written handover was inspected. Pending status and Vendor inbox total
follow this request's explicit behavior. Missing screenshots are not claimed reviewed.

## Reproducible tests and actual results

New Flutter tests: **8 controller/model + 6 UI cases**. Coverage includes eligibility/
proof gates, simulated review, exact totals, pending/double taps, acknowledgement,
failure/same-ID retry, committed-but-unacknowledged recovery, safe discard, restored
request isolation, disposed sessions, immutable lists, Student order/details,
Vendor live inbox, logout, loading/cache/error/Retry. Previous tests now expect the
functional Orders empty state and disabled **Confirm Order** on the review screen.
They retain Vendor/auth/Student Cart behavior assertions and all user fixes.

`checkout_orders.test.mjs` registers **23 security cases** (four positive item-count
cases are generated by a loop). It includes four distinct categories at the maximum
size, malicious draft/snapshot/price/total/timestamp/ownership changes, missing child/
request/counter writes, fifth/duplicate/quantity bounds, Closed/unavailable/mixed
Vendor cases, missing/forged membership/category, private order/request reads,
immutable order/counter protection, same-ID parallel retries, parallel Students with
unique per-stall tickets, independent stalls, confirm/discard races, tombstones,
offline transactions, immutable history after Vendor edits and closed-gate regressions.
Tests deliberately bypass Flutter stale-data checks and issue direct malicious
batches. Unconfirmed draft snapshots are permitted but must independently pass
canonical validation when promoted to orders.

`npm run test:checkout` runs all five security modules sequentially: Stage 1,
Vendor Operations, Vendor Menu, Student Catalog and Checkout (**69 registered cases,
not executed in Codex**). Original Vendor deletion gates stay closed. The historical
menu candidate proof still opens only its own in-memory food gate. Checkout proof
opens only the checkout gate and separately checks the unchanged gated rules.

After an emulator run, the new suite attempts to save raw Rules coverage to
`test/firebase/artifacts/checkout-rule-coverage-<case>.json` (gitignored). This aggregate
report is not a measured per-write access count or automatic proof of the 1000-
expression ceiling. Review the per-case executed branches and emulator errors, especially
the four-distinct-category transaction. Missing coverage is reported, not replaced
with fabricated counts. Any candidate failure keeps confirmation disabled.

Original implementation Codex verification (historical, before the user Windows run):

| Check | Observed result |
| --- | --- |
| Flutter/Dart tooling | Dart SDK/executable absent; analyze/test not run; no repeated bootstrap attempt |
| Network probe | Proxy port 8080 unreachable, exit 7 |
| `npm run test:checkout` | Did not launch tests: `firebase: not found`, exit 127 |
| `node --check` on every Firebase `.mjs` module | Passed JavaScript syntax only |
| `git diff --check` | Passed |
| 42 protected source/config/test/assets compared byte-for-byte with `7ba35a2` | Passed, including all 23 PNGs and retained Stage 2B fixes |

**Zero new Flutter/security cases executed in that original Codex run.** New Dart and Rules were uncompiled,
Android acceptance is pending, no race or ticket proof is reproduced, and document-
access/expression limits are unmeasured. User-reported base acceptance: Flutter
tests/analyzer passed, 46/46 security tests and core Pixel 6 browsing/Cart acceptance;
simultaneous-account manual Cart scenario remains deferred. Do not attribute those
historical results to this new code. The old Chrome/Dart loading gap remains and
does not block ordinary Android testing.

## Windows commands and Pixel 6 checklist

Use the accepted Flutter 3.44.4/Dart 3.12.2, Node/npm and Android Studio Java setup.
From a clean working tree:

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
node checkout_budget.test.mjs
npm run test:checkout
Pop-Location
```

If the branch does not exist locally, use `git switch --track
origin/feature/stage-2c-checkout-orders` instead of the switch/pull lines. Stop on
divergence. Stop prior emulator processes before npm runners. Preserve the output
and coverage artifact. No rule deployment is needed for these local demo tests.
Do not flip either gate merely to make a demonstration work; share passing proof
and review results before a separate enabling change.

For manual gated-build acceptance, start Firebase from repository root in terminal A:

```powershell
.\test\firebase\node_modules\.bin\firebase.cmd emulators:start --project demo-smart-canteen --only auth,firestore --config firebase.json
```

In terminal B, start Pixel 6 and run:

```powershell
flutter devices
flutter run --debug -d <pixel-6-emulator-id> -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2
```

1. Sequentially create synthetic Vendors/Students; retain the working local demo
   setup, Closed initial stalls, safe publication and available-food Cart journey.
   Check four products, quantity bounds, precise prices and all Stage 2B safeguards.
2. Open eligible Cart → Review Checkout. Check itemized amounts, all simulated
   methods and no-money message. Confirm Order must be visibly disabled here.
   Empty/cached/Closed/unavailable/changed selections must not enable a new checkout.
3. Student/Vendor Orders must have correct empty/loading/cache/error behavior.
   New orders cannot be created through this gated client. Test populated read-only
   Orders against emulator fixtures or after a separately reviewed enabling change.
4. After security proof and an approved gate change: confirm once, verify server
   receipt/ticket/immutable total, then clear Cart; check Student Orders/details and
   Vendor inbox by sequentially signing in on the same Pixel 6. Another Student
   or Vendor must not see those orders. No Stage 3 controls should appear.
5. Under that reviewed build, interrupt confirmation, retry the same identity and
   safely discard/check an unresolved request. Verify exactly one order/ticket or
   terminal no-order request, Cart preservation on failure and no pending-write
   success. Restart to recover persisted pending requests from Orders.
6. Regress logout with routes open/account changes, picture pickers, Dashboard,
   stall settings/status, menu availability, both disabled Vendor deletes, Student
   Profile and exact navigation. The automated concurrent-account/race tests are
   required; simultaneous manual devices are not required for ordinary acceptance.

## Stage 3 integration contract / remaining blockers

Use immutable `orderId/submissionId`, vendorUid/studentUid, assigned lifetime ticket,
createdAt, itemCount, integer total, firstItem and numbered child snapshots as the
confirmed input. Status is currently **Pending**. preparationMinutes is an immutable
confirmation-time starting value, not a promised ETA. No queue position exists.
Counter lastTicket is monotonic, per stall, and never a public Student identity.
Requests are checkout recovery records, not queue entries. Their cancelled state
does not mean an order was cancelled.

Stage 3 must design and prove secure FCFS claims/transitions and any head-of-line
runtime; cannot treat a client sort or ticket display as FCFS enforcement. It must
preserve all order ownership, original prices/quantities/snapshots/tickets/timestamps
and idempotency. Any Preparing/Ready/Completed fields, server timestamps, waiting-
time calculations and in-app notification writes need separate rules/proof/UI work;
current order mutations are denied. No such implementation is included here.

**Stage 2C remains a protected partial delivery, not a proven demonstrable checkout.**
The precise blockers are unavailable Rules/Flutter execution, unmeasured boundary
budgets (including transaction read authorizations), uncompiled new Dart/Rules,
missing Android acceptance and the intentionally closed confirmation/write gates.
Stage 3 should not begin until proof passes, limits are reviewed, confirmation is
separately enabled and the complete checkout/order journey passes local acceptance.

## Stage 2C focused security repair — core checkpoint

Remote starting HEAD verified as `001555044cabb2ffad3f1e0c0b72961ede40e7c4`.
User-reported Windows results for that version: analyzer clean, Flutter 63/63;
checkout command 65 total, 58 passed, 7 failed. Failures include 3/4-product
expression exhaustion, malformed-batch budget errors, same-ID and multi-Student
contention, race cleanup lock timeout and an invalid offline rejection assertion.
These results supersede the earlier unexecuted-proof status for that version;
they do not establish the security of this repair.

Core repair preserves the schema, four products and every canonical source check.
Exact map equality/diff replace repeated field comparisons; child/request helpers
bind after-state maps once. Draft bounds are established at preparation and stay
immutable. Canonical food/category/membership are still checked at confirmation.
Integer snapshot/total checks remain explicit. No rules limit is claimed measured.
Client and test helper use bounded SDK retries, plus permission-error recovery
ONLY after server reads demonstrate changed request state or an advanced counter.
Stable-input permission failures propagate; same submission ID is always retained.
Checkout Rules and real `canCheckout` remain false; both Vendor deletion gates
remain closed. Emulator tests, isolation/offline repairs and final documentation
are pending at this intermediate checkpoint. No feature batch, migration or deploy.

## Focused repair final source — local verification required

Intermediate backup was confirmed on GitHub at
`87b8d45fbc8561cee0ea2597cdae6d8a87d4cad2` before further test repairs.
The final commit descends from it on `feature/stage-2c-checkout-orders`; its exact
verified SHA is in the final report/GitHub history. Resume from that verified HEAD.

Contention handling uses at most eight SDK attempts per transaction and five
outer attempts. The outer retry is exclusively for `permission-denied` with an
independently server-observed request state change or advanced stall counter.
Stable-input authorization errors propagate; no fresh submission ID is generated.
Confirmed state recovers the same receipt; cancelled state prevents confirmation.
Network errors remain errors, including lost acknowledgement/server receipt reads.
The Dart repository retains its session/gate checks and server-only receipt reads.
Recovery probes, preparation acknowledgement and receipts also reject pending-write
metadata, so local overlays cannot masquerade as server confirmation.
The JS proof helper mirrors the protocol; malicious direct batches bypass recovery.
This fallback addresses a possible stale-authorization path and is not evidence
that all reported contention failures have been resolved at runtime.

Each checkout test uses a fresh random demo project/database. There is no
`clearFirestore()` between checkout races. Parallel submissions drain through
`allSettled` before any failure is reported; confirm/discard inspects both results
and permits only the appropriate successful/explicit-cancelled terminal outcome.
Same-ID, four concurrent Students and the discard race now use four products.
No permission, timeout or lock failure is accepted as a successful race outcome.

The old offline test was a read-only transaction, which need not fail merely
because the listener network was disabled. The replacement proves a local TCP
forwarder works, disables SDK networking, cuts all RPC connections and attempts
the real write-producing checkout transaction. Only connectivity errors count;
permission errors fail. It terminates that client before removing the transport
and verifies through a separate connected client: pending request, no order and
no ticket. A test timeout fails; it does not manufacture an expected rejection.
This is JS/emulator transport coverage, not Android offline acceptance.

Final Codex checks on this repair:

| Check | Actual result |
| --- | --- |
| `node checkout_budget.test.mjs` (from `test/firebase`) | 1/1 passed; six diagnostic assertions |
| `node --check` on every Firebase `.mjs` file | Passed syntax checks |
| `git diff --check` | Passed |
| Original four security modules / 46 cases | Source unchanged byte-for-byte; not rerun |
| 107 protected app files/config/assets outside checkout repository | Unchanged from the starting commit |
| Flutter analyze/test, Rules compilation, 69-case emulator runner | Not run: Flutter/Dart SDK, Firebase CLI and Node dependencies unavailable |
| Android acceptance / actual expression and access measurements | Not run/unmeasured |

No SDK download or failed bootstrap was retried. Your **63/63 Flutter and clean
analyzer, 58/65 old security results** remain reported historical Windows results,
not results of this revision. All 69 security cases, the revised Dart repository
and Android remain pending local verification. Keep both checkout gates and both
Vendor deletion gates closed even if tests pass, until review authorizes enabling.
The historical Chrome/Dart browser-loading gap is unchanged.

Run the Windows commands above. `npm run test:checkout` must report **69 passed,
0 failed** and exit zero from the budget guard. Preserve all output,
`test/firebase/firestore-debug.log` (or the root log if emitted there),
`artifacts/checkout-budget-diagnostics.json`, and per-case coverage JSON. If the
runner reports missing logs, do not bypass it or call proof complete: retain the
Firebase output and resolve the log location first. The extra unit test is 1 case
outside the combined 69. No dependency or SDK version changes are needed.

Manual Pixel 6 checks use only `main_emulator.dart` and the local demo project as
shown above. Confirm the four-product Cart/review still works, Confirm Order and
both Vendor deletes remain visibly disabled, and Vendor/Student navigation/logout
remain intact. Successful real-client checkout cannot be accepted with gates shut.
Stop here: no Stage 3 queue/FCFS/ETA/notifications or production rules deployment.
