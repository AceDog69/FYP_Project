# Stage 2C — checkout and immutable Pending orders

Required base verified through GitHub: `7ba35a219b5f3267d1b95941265a7166cc70b024`,
the user's latest Stage 2B verification-fix commit. Branch:
`feature/stage-2c-checkout-orders`. No main update, deployment or Stage 3 work.

## Core checkpoint

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
per-write access ceiling. Header validates that item canonically, all remaining
item after-states, total, authenticated Student, canonical Open stall, matching
request and counter. Each remaining item's own create rule validates canonical
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

## Budget / proof status

**Static design estimate, not runtime evidence:** a worst-case four-item order in
four distinct categories needs 12 canonical item documents (four each of food,
category and membership), Student profile, canonical stall, request after-state,
counter after-state, header after-state and three child after-states: 20 distinct
document-state lookups across the atomic request, assuming repeated identical
lookups are cached. Header authorization has ten access invocations including the
Student check; each child uses header/request and three canonical documents.
Document access is therefore at the documented limits, not a comfortable margin.
Actual Rules cache/access and 1000-expression-budget behavior must be measured with
the four-distinct-category case, adversarial batches and races. No runtime budget,
rule compilation, successful security case or safe-checkout proof is claimed here.
Any limit failure must be fixed architecturally, not by weakening validation.

This is a **write-authorization estimate only**, not a measured full-transaction
budget. Client transaction reads have separate authorization evaluations (including
Student profile/public-listing checks). Their interaction with transaction-wide
quotas and cache reuse must also be checked in the emulator. Student menu/counter
read branches now check the Student condition first to avoid unnecessary lookup
of a Vendor profile during a permitted Student read; the permission sets are unchanged.
Exact access and expression counts have not been established. Consequently this
candidate cannot be declared safe or enabled based on these estimates.

The checked-in `checkoutWritesEnabled()` and real repository `canCheckout` are
false. Both previous Vendor delete gates are unchanged. Pending request/order/counter
write rules are gated together. No paid Firebase service, production data change,
migration, billing change or deployment is part of this work.

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

`checkout_orders.test.mjs` registers **19 security cases** (four positive item-count
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
Vendor Operations, Vendor Menu, Student Catalog and Checkout (65 registered cases,
**not observed passes**). Original Vendor deletion gates stay closed. The historical
menu candidate proof still opens only its own in-memory food gate. Checkout proof
opens only the checkout gate and separately checks the unchanged gated rules.

After an emulator run, the new suite attempts to save raw Rules coverage to
`test/firebase/artifacts/checkout-rule-coverage.json` (gitignored). This aggregate
report is not a measured per-write access count or automatic proof of the 1000-
expression ceiling. Review its executed branches and emulator errors, especially
the four-distinct-category transaction. Missing coverage is reported, not replaced
with fabricated counts. Any candidate failure keeps confirmation disabled.

Actual Codex verification, 22 October 2026 (Asia/Singapore):

| Check | Observed result |
| --- | --- |
| Flutter/Dart tooling | Dart SDK/executable absent; analyze/test not run; no repeated bootstrap attempt |
| Network probe | Proxy port 8080 unreachable, exit 7 |
| `npm run test:checkout` | Did not launch tests: `firebase: not found`, exit 127 |
| `node --check` on every Firebase `.mjs` module | Passed JavaScript syntax only |
| `git diff --check` | Passed |
| 42 protected source/config/test/assets compared byte-for-byte with `7ba35a2` | Passed, including all 23 PNGs and retained Stage 2B fixes |

**Zero new Flutter/security cases executed.** New Dart and Rules are uncompiled,
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
git switch --track origin/feature/stage-2c-checkout-orders
git rev-parse HEAD
flutter pub get --enforce-lockfile
flutter analyze
flutter test
Push-Location test/firebase
npm ci
npm run test:checkout
Pop-Location
```

If the branch exists locally, switch to it and `git pull --ff-only`; stop on
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
