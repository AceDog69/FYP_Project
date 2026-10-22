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
