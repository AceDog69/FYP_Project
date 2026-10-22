# Stage 2A-03 deletion review — 22 October 2026

Base verified through GitHub: `14a9ff6f0885de8cb47b26f18efbd9a8580b920d`,
on `feature/stage-2a-03-vendor-menu`. This continues the accepted implementation.
No schema migration, production writes, rule deployment or new milestone.

## Release state

**Both Delete controls remain disabled.** `canDeleteFood` remains false in the
real repository and `menuDeletesEnabled()` remains false in checked-in rules.
There is no runtime flag or Dart define that opens these gates. Category Delete
is additionally denied unconditionally in rules, independent of the food gate.

The proposed paired Food Delete rule and transaction are prepared for testing,
not declared proven. The menu security suite replaces only the literal closed
food gate in an in-memory rules string, then tests the candidate. A separate
demo-project test loads the unchanged checked-in rules and verifies the closed
gate. It does not edit/deploy the file or enable app controls. The test loader
fails if it cannot find exactly one expected closed gate. Passing that candidate
suite still requires review before a later gate change; it does not prove safe
Category Delete. The existing Stage 1 and Vendor Operations suites run first
against the unchanged checked-in rules through `npm run test:menu`.

## Invariant and operations

For each existing `stalls/{uid}/menuFoods/{foodId}`, exactly one canonical
`menuMemberships/{foodId}` has the same Vendor and category. The referenced
`menuCategories/{categoryId}` belongs to that Vendor. Availability does not alter
this relationship. These invariants assume creation/update through the rules;
malformed admin-created records fail closed and are not automatically repaired.

| Operation | Transaction reads | Atomic writes / authorization |
| --- | --- | --- |
| Create category | User, stall, absent category, name reservation | Category + unique normalized name reservation; existing rules unchanged |
| Rename category | User, stall, category revision, new name reservation | Same category ID/revision + old/new name reservations; existing rules unchanged |
| Create food | User, stall, food ID, destination category | Food + canonical membership; rules require matching after-states |
| Edit / availability / reassign | User, stall, food revision, destination category | Food + same membership ID; reassignment replaces its category atomically |
| Candidate Food Delete | User, stall, food revision, membership, category | Delete exactly the selected food and its membership; rules require matching before-states and both absent after |
| Category Delete | None implemented | Always denied, even if the client sees zero food items |

The new deletion helper checks both documents' before-state ownership, membership
keys, category equality and category ownership, then requires both after-states
to be absent. A single deletion, wrong membership ID, orphaned membership,
foreign-owned record, mismatched category or unrelated extra membership field
cannot satisfy it. Deletion does not depend on availability.

The repository reads all documents before writing, checks the displayed food
revision, and validates membership/category before deleting. A transaction retry
after a concurrent edit, reassignment or delete rechecks that original revision.
Repeated or stale screen actions fail rather than silently deleting newer data.
Firestore DELETE requests have no `request.resource` containing a draft revision:
rules enforce pair integrity, not the age of an owning client's UI. An owning
direct-client atomic pair deletion has no UI revision to validate; this is not
presented as a server-enforced optimistic concurrency token.

UI preparation locks repeated confirmation openings and repeated submissions,
Cancel calls no repository method, failure retains confirmed item data and shows
an error, and success feedback follows completion of the transaction. The live
menu stream skips pending local writes. A test-only fake enables this UI path;
the real repository and checked-in rules stay gated.

No order documents are created as fixtures or workflows. The delete transaction
only writes two menu paths. Existing default-deny rules for order namespaces are
unchanged. A security test attempts an order write in the deletion batch and
expects the entire batch to fail, then deletes only the pair. This is a boundary
test, not runtime proof of existing order snapshots. Future confirmed checkout
must store immutable food name, integer price, quantity and item snapshots rather
than resolve historical order contents from mutable menu documents.

## Why Category Delete remains blocked

1. Required invariant: category emptiness must mean **zero food references**, not
   merely zero available foods or a client query returning no documents.
2. The current four-collection schema has no trusted per-category aggregate.
   Rules can verify a food's canonical membership by known food ID, but cannot
   query every membership to prove that none references a category.
3. Adding a mutable counter is insufficient. Every create, delete and reassignment
   would need a rules-verifiable transition witness tied to that exact food's
   before/after state, including both categories on reassignment. A client could
   otherwise omit or forge decrements or count several foods as one change.
   Multiple transitions in one batch must also be rejected or accounted for.
4. A proven aggregate design would have to read/write each affected category on
   every membership transition so create/reassign and empty-category deletion
   serialize on the same document. The present design does not do this, so no
   counter or category-deletion permission is added here. Current race tests
   expect category deletion to lose unconditionally, not a positive safe-delete.
5. Unavailable foods still have a canonical membership. Any future aggregate
   must count them identically; availability changes must never decrement it.
6. A future witness/counter protocol needs emulator evidence for document-access
   and expression limits, including malicious multi-food batches. No executable
   proof for such a protocol is available in this environment.
7. Existing populated categories have no verified count. Initializing a counter
   to zero or trusting a client count would introduce false emptiness. Rules
   cannot certify a backfill query. A separately reviewed trusted migration or
   compatible versioned protocol is required before existing categories gain
   delete permission. Neither a migration nor a schema change is performed here.

This is a limitation of this implementation/proof, not a claim that all possible
client-only protected aggregate designs are impossible. Renaming and all accepted
menu operations remain available; category/name reservations remain protected.
Forged counter fields are rejected by existing exact-key validation.

## Security suite and budgets

`test/firebase/vendor_menu.test.mjs` now has 18 top-level tests, including:

- Existing food/category creation, editing, names, availability, reassignment,
  malicious fields/prices/pictures/timestamps/revisions and role isolation.
- Candidate authorized paired deletion, unavailable-food deletion, rejection of
  individual, wrong-ID, orphaned, mismatched and foreign-owned deletions.
- Stale/repeated transaction requests, edit/delete and reassignment/delete races.
- Blocked empty/nonempty/unavailable category deletion and reservation cleanup,
  create/delete and reassign/delete races against the closed category gate.
- Forged counts and name/revision/timestamp writes; order namespace isolation;
  and a separate checked-in-rules closed-gate regression.

These are runnable scenarios, **not observed passes**. In the candidate delete
write authorization, source inspection finds six document-access invocations per
write (profile + food before + membership before + category + two after-existence
checks), twelve for the two deletions before caching. This is a static estimate,
below the documented 10-per-write / 20-per-atomic-request limits. Client transaction
reads also undergo their read rules; no runtime access counts or total expression
counts were measured. The 1000-expression limit is unmeasured. Source estimates
do not prove that rules compile or fit runtime limits. Inspect emulator evaluation
reports after running both ordinary operations and races; investigate any limit
failure rather than increasing permissions.

## Verification and Windows acceptance

User-reported results **before this finalization**, at `14a9ff6`:
37/37 Flutter tests, 28/28 combined menu security tests, Pixel 6 core menu acceptance,
and analysis with 0 errors, 0 warnings and four informational lints. These are not
new Codex results. All four diagnostic sites have minimal fixes: braces at Dashboard
status feedback, Menu save feedback and category-load error, and `?action` in the
profile widget collection. The added delete feedback also uses braces. No broad
formatting or SDK/dependency changes.

Actual finalization checks here:

| Check | Observed result |
| --- | --- |
| `flutter analyze` | Did not start; Dart SDK download fails connecting to proxy port 8080; exit 7 |
| `flutter test` | Did not start; same SDK/proxy failure; exit 7 |
| `npm run test:menu` | Did not start; `firebase: not found`; exit 127 |
| `node --check` on Stage 1, operations and menu security modules | Passed syntax only |
| `git diff --check` | Passed |

No Flutter/security cases executed here, no candidate proof or race result, and
no Android compilation/testing is claimed. The earlier Chrome/Dart test loading
stall remains an existing gap; do not call it passed or block Android work on it.

On Windows, inspect a clean working tree and update the existing branch by a
normal fast-forward (stop on divergence):

```powershell
git status --short
git fetch origin
git switch feature/stage-2a-03-vendor-menu
git pull --ff-only origin feature/stage-2a-03-vendor-menu
git rev-parse HEAD
flutter pub get --enforce-lockfile
flutter analyze
flutter test
Push-Location test/firebase
npm ci
npm run test:menu
Pop-Location
```

The combined security command includes original Stage 1, Vendor Operations and
the new menu tests. Stop previous emulator processes first. All Firebase runners
must use the demo project and local Auth/Firestore emulators. Do not deploy rules
or edit the gates merely to get a working button. Share the actual test output
for review before a separate enabling change.

For Pixel 6, start Firebase at repository root in one terminal, then Flutter in
another:

```powershell
.\test\firebase\node_modules\.bin\firebase.cmd emulators:start --project demo-smart-canteen --only auth,firestore --config firebase.json
flutter devices
flutter run --debug -d <pixel-6-emulator-id> -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2
```

Remaining acceptance: both Delete controls must visibly remain disabled with
explanations in this commit; rerun create/edit/availability/reassignment/persistence,
duplicate categories, error/cache/Retry, picture scrolling/Cancel/Confirm, four
Vendor and five Student tabs, Dashboard status, Profile/Stall Settings and Logout.
After a reviewed gate-enabling change, separately accept Delete Cancel/no writes,
one pending submission, offline failure retaining the item, acknowledged success,
unavailable-food deletion and stale-edit/reassignment conflicts on Pixel 6.
Category Delete must remain disabled until its own positive proof and existing-data
compatibility are resolved. Stage 2B is not started.
