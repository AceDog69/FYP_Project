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
Students cannot write progress, statuses, cursors or ticket counters.

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
