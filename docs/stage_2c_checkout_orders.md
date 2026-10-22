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
at this intermediate checkpoint; it must be backed up before continuing.

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

The checked-in `checkoutWritesEnabled()` and real repository `canCheckout` are
false. Both previous Vendor delete gates are unchanged. Pending request/order/counter
write rules are gated together. No paid Firebase service, production data change,
migration, billing change or deployment is part of this work.
