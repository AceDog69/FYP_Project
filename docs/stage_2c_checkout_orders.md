# Stage 2C — secure two-food checkout, verification pending

Branch: `feature/stage-2c-checkout-orders`.
The two-food implementation preserved the user's compile and widget fixes at
`341e7c2d051a15a2f19fe47e26862cac0e048df0`. The focused offline correction
starts from verified GitHub HEAD `1ace379bc02c8bb0d33b3aa131fc99e36d81d9cf`. Historical Stage 2B base:
`7ba35a219b5f3267d1b95941265a7166cc70b024`.

## Approved limit and evidence — 22 October 2026

The user approved **two distinct foods per Cart/order**, one stall, **1–20 units
per food**, integer-sen prices/totals and simulated payment. No money is charged.
Do not expand the limit or enable checkout before successful proof and review.

User-reported Windows results at `1ace379bc02c8bb0d33b3aa131fc99e36d81d9cf`:
Flutter analyze passed, Flutter **67/67**, security **69/70**, and **zero Rules-budget
diagnostics**. One/two-food checkout, three/four/five-food rejection, same-ID
recovery and sequential concurrent tickets passed. The only failing case was the
offline integration assertion: the cut RPC returned `1 CANCELLED: Call cancelled`
instead of one of the previously accepted errors. The standalone transport test
passed. These are user-reported prior-commit results, not Cloud reruns or a
verified 70/70 result for this correction. Earlier four-food/53-budget-diagnostic
failures are historical and were superseded by the approved two-food limit.

Checked-in `checkoutWritesEnabled()` is false. Real
`FirebaseOrderRepository.canCheckout` inherits false. Both Vendor Food Delete and
Category Delete stay disabled. No deployment, production data change, migration,
main update, paid service, Blaze requirement or Stage 3 work is included.

## Implementation and schema

`lib/constants/checkout_limits.dart` supplies the two-product / twenty-unit
contract to Cart eligibility, validation, models, controller, repository and the
Cart/Checkout Review labels. Adding another unit of an existing food is allowed
at the product ceiling, up to twenty units. Adding a third distinct ID fails
without discarding the Cart. One-stall replacement and session isolation remain.

| Path | Contents / integrity |
| --- | --- |
| `users/{studentUid}/checkoutRequests/{submissionId}` | Exact bounded owner-scoped draft, one/two distinct IDs, canonical expectations, simulated method, integer total, timestamps, pending/confirmed/cancelled request state. |
| `orders/{submissionId}` | Immutable Pending header, first canonical snapshot inline, owner/vendor, total, preparation-time snapshot, ticket, method, simulated payment and server time. |
| `orders/{submissionId}/items/1` | Only possible second canonical snapshot. Required when itemCount is two. All other child write indices denied. |
| `checkoutCounters/{vendorUid}` | schemaVersion, vendorUid, lastTicket, random opaque lastOrderId, server time. First ticket one, then exactly +1; no resets/deletes. |

Order item maps preserve stable ID, name, description, category ID/name, picture
ID, integer unit price, quantity, subtotal and revision. Existing price bounds
remain 1–100000 sen. Snapshot, request and receipt model validation reject
oversized orders. The repository writes only optional child `1`; third/fourth
slot authorization and draft sum/uniqueness branches have been removed.

Preparation Rules reject more than two entries before item validation. They
validate both exact draft shapes, nonduplicate IDs, quantities, types, bounds,
picture IDs and `totalSen == sum(priceSen * quantity)`. Draft fields cannot change
after preparation. An independent header bound rejects oversized confirmation,
including a legacy/privileged-seeded oversized draft that bypasses preparation.
There is no automatic migration or privileged repair of such test records.
Models fail closed on old oversized requests/orders; gated production writes
have never been authorized by this work. Do not delete real history or reset
production data to accommodate test fixtures.

At confirmation each snapshot is bound to its immutable draft and exact canonical
food/category values. Rules independently verify food ID/owner/revision/name/
description/picture/price/availability, category ownership/name/nameKey/revision/
timestamps, and exact private membership. Canonical source stall must belong to
the vendor and be Open, with matching name/preparation time. Students still cannot
read private raw stall or membership documents.

The header validates its first snapshot and requires its second child when needed.
The child rule binds the same current parent, owner and draft slot and performs
canonical validation once. No orphan/extra child can be created, and existing
headers/children cannot be updated/deleted. Thus the exact immutable prepared sum
is the header total and each snapshot subtotal is the canonical unit price times
quantity. This inductive invariant concerns rule-written data, not arbitrary
privileged/Admin-created corrupt order histories. Tests reject orphan/extra slots,
missing required documents, forged slots/totals and reversed-order atomic writes.

## Atomicity, retries and receipts

Submission ID is the same random twenty-character request/order ID across retry,
acknowledgement loss, restart recovery and safe discard. Preparation precedes
confirmation. One transaction creates the header/optional child, advances the
stall counter and confirms the request. No ticket is consumed by a draft.
Counter linkage plus exactly-one increments and immutable headers prevent detached
increments, duplicate tickets or a second order for the same ID. Different stalls
have independent counters.

SDK transaction retry is bounded at eight attempts. Up to five outer attempts
handle a permission error only when independent server reads prove the request
state changed or the counter advanced. Stable-input permission errors propagate;
direct adversarial batches bypass this recovery. The two-food change preserves
this protocol rather than weakening concurrency/idempotency assertions.

Discard of an unconfirmed request is terminal, preserves unpaid Cart contents and
serializes on the same request. An absent request gets a cancelled tombstone,
blocking delayed prepare/confirm. Already confirmed state recovers the receipt,
never cancels a confirmed order. Race tests inspect both operations and permit
only the appropriate terminal result, not arbitrary permission/timeout failures.

Success requires acknowledged commit and server-only reads of complete immutable
receipt data, with pending-write metadata rejected. Unknown results preserve the
identity and locked Cart for retry/discard. Only a complete receipt clears the
matching Cart version. Logout/session change cannot clear another user's Cart.
Confirmed request recovery returns its existing receipt without another ticket.

## Rules budget guard and security coverage

Two-food authorization has a **static estimate only** of eight header accesses and
twelve distinct document states across writes assuming cache reuse: six canonical
item sources, profile, raw stall, request-after, counter-after, header-after and
one child existence-after. Four writes maximum: header, child, counter, request.
Preparation is separate. These are not measured expression/access totals and do
not establish the complete transaction's runtime budget.

`npm run test:checkout` preserves all earlier **46** security cases unchanged and
runs **24** checkout cases: **70 expected cases**, not observed passes here.
It includes:

- Legitimate one/two foods in distinct categories, including twenty units each.
- Explicit separate three/four/five-food rejection, including seeded oversized
  drafts, duplicate IDs, bad quantities in either slot, totals and header bounds.
- Every forged/missing/extra snapshot field at both slots, stale price/revision,
  malformed category/membership, missing request/counter/child, Closed/unavailable
  canonical data and cross-vendor changes.
- Authenticated ownership/read privacy, immutable history/counters/requests,
  same-ID parallel submissions, four parallel Students ordering two foods each,
  unique sequential tickets, independent stalls, discard races and tombstones.
- Actual transport disconnection and checked-in checkout/Vendor deletion gates.

The wrapper inspects client output and new Firestore debug-log bytes for budget
exhaustion, including errors concealed as permission-denied. Missing/empty log
evidence fails verification. All positive and negative assertions must pass and
there must be **zero** budget diagnostics. A clean log alone is insufficient.
Per-case raw coverage and `artifacts/checkout-budget-diagnostics.json` are ignored
artifacts, not committed source or fabricated per-request measurements.

## Offline investigation

A read-only transaction plus `disableNetwork()` alone does not establish that a
write-producing transaction is offline: some JS SDK transaction RPCs can bypass
the listener switch. The security test uses a local TCP forwarder and proves the
online server read actually used it via connection/byte counters. It then disables
SDK networking, destroys existing forwarded sockets, blocks new sockets and calls
the real checkout transaction with one SDK attempt.

The locked **grpc-js 1.9.16** [HTTP/2 stream close handler](https://github.com/grpc/grpc-node/blob/%40grpc%2Fgrpc-js%401.9.16/packages/grpc-js/src/subchannel-call.ts)
explicitly maps `NGHTTP2_CANCEL` to `Status.CANCELLED` with details `Call cancelled`.
The [current handler](https://github.com/grpc/grpc-node/blob/master/packages/grpc-js/src/subchannel-call.ts)
also explains that Node can synthesize cancellation resets after connection drops.
[Firebase's Node adapter](https://github.com/firebase/firebase-js-sdk/blob/main/packages/firestore/src/platform/node/grpc_connection.ts)
maps gRPC status and preserves its error message. Thus this deliberate cut can
legitimately yield the exact observed cancellation; it does not indicate order
confirmation or permission failure. This source finding plus the user's observed
error supports a narrowly scoped test correction, not a claim of Cloud reproduction.

The matcher requires both the verified online path and completed deliberate cut.
It accepts `unavailable`, or **only** code `cancelled` with the exact message
`1 CANCELLED: Call cancelled`. Generic cancellation, numeric/unknown codes,
permission errors, arbitrary exceptions and `deadline-exceeded` are rejected.
A successful checkout fails `assert.rejects` and an explicit success flag check.
The overall test timeout remains a failure, not acceptable offline evidence.

After that rejection, before any teardown can cancel calls, the independent
connected client uses server-only reads to verify: no order, counter absent and
unchanged from baseline, and the complete request unchanged/still pending.
Query reads use `getDocsFromServer`, not a cache fallback. These checks are not
conditional on which allowed connectivity error occurred. Only after those
assertions does teardown close the already-cut listener, then terminate the SDK
client. Each step is bounded at five seconds, both are attempted even on cleanup
failure, and a cleanup deadline fails the test. The transport is never restored.

Standalone unit tests prove the cut, exact-error/context discrimination and
normal versus failed/deadline cleanup. The Firebase offline case remains unrun in
Cloud; 70/70 and Android offline acceptance must still be verified locally. Do
not broaden the matcher if another failure appears: retain its exact code/message
and transport-control/server-state evidence.

## Actual checks for this revision

| Check | Result in Codex |
| --- | --- |
| `node test/firebase/checkout_budget.test.mjs` | 1/1 passed, six diagnostic assertions |
| `node test/firebase/checkout_transport.test.mjs` | 3/3 passed, including real loopback cut, exact cancellation/context matcher and bounded cleanup |
| Every Firebase `.mjs` via `node --check` | Syntax passed; 12 modules |
| Git whitespace and scope comparisons | Passed; all production source, Rules, dependencies and the other 69 security cases unchanged |
| Flutter analyze/test | Not rerun; SDK unavailable; no Dart or Flutter changes in this correction |
| 70-case Firebase suite / Rules compiler | Not run; Firebase CLI and dependencies unavailable |
| Actual budget diagnostics, ticket/race/offline Firebase proof | Unverified for this revision |
| Android acceptance | Not run |

No SDK bootstrap or dependency download was retried. Your preceding clean analyzer,
67 Flutter passes, 69 security passes and zero-budget report are historical user
evidence, not a Cloud runtime verification of this correction.
The old Chrome/Dart test-loading gap remains open. All checkout and deletion gates
stay disabled pending successful exact-commit local testing and review.

## Windows verification and Pixel 6

From a clean repository, fetch/switch/pull this feature branch only. If it is not
local, use `git switch --track origin/feature/stage-2c-checkout-orders` instead.
Stop on divergence. Compare HEAD to the verified SHA in the delivery report.

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
node checkout_transport.test.mjs
npm run test:checkout
Pop-Location
```

Expect **70 security cases passed, zero failed and zero budget diagnostics**.
The four standalone Node unit cases (three transport/helper and one budget case)
are outside that total. Preserve full output,
`test/firebase/artifacts/checkout-budget-diagnostics.json`, per-case coverage and
`test/firebase/firestore-debug.log` (or the root log if emitted there). Stop prior
emulator processes before the combined runner. Resolve missing log evidence;
do not bypass the guard. No production Firebase operation is needed.

To isolate the Firebase offline case after `npm ci`, run from `test/firebase`:

```powershell
.\node_modules\.bin\firebase.cmd emulators:exec --project demo-smart-canteen --only auth,firestore --config ../../firebase.json "node --test --test-name-pattern=actual.offline.checkout checkout_orders.test.mjs"
```

That filtered command is diagnostic only. It does not replace all seventy cases
and the full budget guard above.

For gated manual acceptance, terminal A at repository root:

```powershell
.\test\firebase\node_modules\.bin\firebase.cmd emulators:start --project demo-smart-canteen --only auth,firestore --config firebase.json
```

Terminal B, with Pixel 6 running:

```powershell
flutter devices
flutter run --debug -d <pixel-6-emulator-id> -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2
```

Use synthetic demo accounts only. Add two different available foods from one Open
stall, increase each to twenty units, check integer RM totals, then attempt a
third distinct food: it must be rejected while the Cart survives. Review Checkout
must show the new limit. Confirm Order and both Vendor deletion actions remain
disabled. Check navigation/logout, Closed/unavailable/cache handling and previous
Vendor/Student behavior. Do not enable real-client confirmation to run these checks.
Successful real-client checkout and Android offline acceptance remain pending
separate proof/review/enabling.

## Stop condition / future handoff

Final commit and exact tree must be verified on GitHub before resuming. Resume
from that branch HEAD, never rebuild from Stage 1. No Stage 3 implementation is
authorized here. Future queue/FCFS/ETA/notifications must consume immutable order
snapshots and tickets, preserve order history and enforce separate status rules.
Only after all exact-commit tests, zero budget diagnostics and review may a later
change enable checkout. No production deployment or merge occurs in this batch.
