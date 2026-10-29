# Smart Canteen development progress

Updated 29 October 2026 (Asia/Singapore). Supervisor meeting: 28 October 2026.

**Latest state:** the Stage 4B public queue count section at the end supersedes historical checkpoint
limitations/results below. Production checkout and both Vendor destructive actions remain gated.

## Milestones and source

| Milestone | Commit / state |
| --- | --- |
| Approved Stage 1 baseline | `d7741277fe0918c1463449b0d0f5bb178ca01fef` |
| Stage 2A-01 Dashboard source | `fb9760731474fe80257c8d753b6e6f90d03330bb` |
| Latest Stage 2A-01 fixes, verified through GitHub before editing | `01b08d15ab2bc48d87caa497c0c54fbdc35b80d8` |
| Stage 2A-02 implementation; runtime/security acceptance pending | `d76c2c95f7142e87191e8ed6cbf516b839d4b1b4` |
| Stage 2A-02 Windows emulator/launcher fixes, accepted by user | `eff8c6e5235314a5e6c74af06cbbc17e07873ddf` |

Stage 2A-01 was verified by the user on a Windows Pixel 6 Android emulator:
analysis passed, 23 combined Flutter tests passed, and Dashboard navigation,
real stall display, Profile and Logout were manually verified. Those are the
user's reported results for Stage 2A-01, not results for the new code below.

Stage 2A-02 branch: `feature/stage-2a-02-vendor-operations`. The exact latest
Stage 2A-01 commit and its tree were imported through the connected GitHub
integration because shell Git transport could not reach its proxy. The verified
Material widget and test-visibility fixes are retained. No missing old Stage 2A
commit was reconstructed and no development was based on Stage 1 alone.

GitHub backup of the implementation snapshot was confirmed at
`d76c2c95f7142e87191e8ed6cbf516b839d4b1b4`. All 23 uploaded PNG Git object hashes
match the local original assets, and the remote source tree matches the complete
local tree. Normal Git push failed with `Failed to connect to proxy port 8080`;
the connected GitHub integration created the commit and feature branch instead.
A subsequent documentation commit records this verification; the final chat
report gives the final remote branch-head hash. No force-push, merge or Firebase
deployment was performed.

## Approved decisions and implementation

- Firebase Authentication and Firestore remain on the existing project; no paid
  services, billing changes, Storage uploads or production migrations.
- Vendor navigation remains Dashboard, Orders, Menu, Profile. Student's five tabs
  and Student Profile presentation remain unchanged.
- Stall Setup remains unchanged, including no picture selection during setup.
- Stall categories remain exactly Malay, Western, Chinese, Japanese, Korean,
  Beverage, Dessert. Preparation time remains an integer from 1 to 180 minutes.
- Open/Close Stall uses a server Firestore transaction. A repository guard rejects
  concurrent stall writes, UI disables repeated submission, and failures preserve
  the previous confirmed state. Cached data remains labeled; cached Dashboard
  status actions and entering the editor are disabled. Local pending snapshots
  are not presented as confirmed values.
- V2-05A Vendor Profile displays full name, email, phone and role as read-only,
  plus existing stall information and Edit. Logout remains available even if stall
  loading fails. Account-owner full name/phone permissions are unchanged in rules.
- V2-05B editor saves stall name, category, initial preparation time and picture
  together. Cancel discards the draft; save errors retain it for retry.
- All 23 original supplied PNGs are bundled with stable IDs; filenames are
  unchanged, including `Japanese 1.png`. The reusable scrolling Choose Picture
  dialog shows selection, Cancel and Confirm. Confirm changes only the form;
  persistence requires successful form Save.
- Stalls without `pictureId` use a category default. Defaults are Nasi Lemak,
  Western Food, Chinese Food 1, Bento, Bibimbap, Drink and Dessert respectively.
  Saved valid IDs override these defaults; unknown IDs fall back for display.
- Supplied V2-01, V2-05A/B and actual picture ZIP are accessible and inspected.
  Orange `#FF7A00`, rounded cards and existing navigation are retained.

## Firestore changes requiring later review/deployment

`stalls/{vendorUid}` keeps its stable ID and existing fields. Settings saves add
the optional string `pictureId` from the exact 23-ID allowlist. Every update adds
or refreshes `updatedAt` using a server timestamp equal to `request.time`.

Rules permit only an authenticated owning Vendor with completed setup and a
matching profile `stallId` to update name, category, preparation time, status,
picture ID and update timestamp. Types, nonblank/maximum name length, category
values, prep bounds, Open/Closed status and permitted picture IDs are enforced.
`ownerUid`, `createdAt` and all other existing fields cannot change or be removed.
Unknown new fields and stall deletion remain denied. Existing protected extra
fields can remain unchanged. Missing optional picture IDs remain valid.

Registration, profile/stall association, original Stall Setup and read restrictions
are unchanged. Students do not gain stall catalog reads or stall writes in this
milestone. No checkout/order/queue/FCFS/notification rules are added.

**Rules were not deployed.** New operations against the unchanged live Stage 1
rules will be denied. First prove these changes in local emulators; production
deployment needs separate review and authorization.

Legacy category text remains readable, but edits require one of the seven valid
categories. An invalid legacy category or picture ID must be corrected through a
valid settings save before status updates satisfy the new rules. Valid Stage 1
records lacking only a picture ID require no migration.

Future checkout must validate authoritative stall status inside its confirmed
checkout transaction so a Closed stall rejects new checkout. Existing confirmed
orders must remain processable. This batch never writes orders and initializes no
queue runtime. If the approved future checkout design needs separate runtime data,
its initialization must be implemented and tested in that milestone; do not change
Stage 1 Stall Setup or invent runtime fields as part of this batch.

## Changed source and test files

- `lib/constants/predefined_pictures.dart`, 23 PNGs under
  `assets/predefined_pictures/`, and the asset declaration in `pubspec.yaml`.
- `lib/models/vendor_stall.dart`: optional picture ID and validated settings model.
- `lib/services/auth_repository.dart`, `lib/services/firebase_auth_repository.dart`:
  server transactions, Vendor validation and concurrent-write guard.
- `lib/screens/vendor_dashboard.dart`: real status action, failure/pending behavior
  and stall picture; existing Material wrappers are preserved.
- `lib/screens/home_screen.dart`, `lib/screens/vendor_profile.dart`,
  `lib/screens/vendor_stall_editor.dart`: Vendor-only presentation/editor routing.
- `lib/widgets/stall_picture_picker.dart`, `lib/widgets/vendor_profile_widgets.dart`:
  reusable picture dialog, thumbnails and profile layout.
- `lib/main_emulator.dart`: optional synthetic-data debug entry; normal `main.dart`
  and Firebase configuration remain unchanged.
- `firestore.rules`: conservative owner-only stall updates.
- `test/vendor_operations_test.dart`, `test/vendor_dashboard_test.dart`,
  `test/stage_one_test.dart`: new behavior and updated shared synthetic fixture.
- `test/firebase/vendor_operations.test.mjs`, `test/firebase/package.json`,
  `test/firebase/stage_one.test.mjs`, `test/firebase_repository_browser_test.dart`:
  rules and actual Dart service checks. Existing security assertions are retained;
  the old test title about all edits being denied now describes immutable fields.
- This progress handover. No dependency versions or lockfiles were changed.

## Actual verification in this session

| Command / check | Result |
| --- | --- |
| `flutter analyze` | Analysis did not start: missing Dart SDK; proxy port 8080 unreachable; exit 7 |
| `flutter test test/stage_one_test.dart test/stall_category_test.dart test/vendor_dashboard_test.dart test/vendor_operations_test.dart` | Tests did not start: same SDK/proxy failure; exit 7 |
| `npm test` in `test/firebase` | Tests did not start: `firebase: not found`; exit 127 |
| `npm run test:vendor` | Tests did not start: `firebase: not found`; exit 127 |
| `npm run test:dart` | Tests did not start: `firebase: not found`; exit 127 |
| Node syntax checks of existing/new rules test modules | Passed syntax only |
| Asset names and bytes versus original ZIP | Passed, all 23 PNGs |
| Dart picture map versus rule allowlist | Passed, exact 23-ID match |
| `git diff --check` | Passed |
| Original Stall Setup, normal entry, Firebase config and lockfile comparison | Unchanged |

New code and rules have **not been compiled, emulator-validated or Android-tested**
here. No new functional/security test pass is claimed. Widget tests include a
412x915 logical layout check, but it was not executed and is not Pixel 6 acceptance.

Added tests cover Open/Close acknowledgement, repeated submission, failure state,
cached data, account read-only presentation, settings validation, seven categories,
picture defaults/library scrolling/Cancel/Confirm/Save, image persistence, logout,
immutable ownership and timestamps, cross-Vendor/Student rejection, original
profile permissions and preserved protected legacy fields. Browser tests exercise
the real Dart transaction service and fresh-session/listener persistence using demo data.

## Windows / Android emulator acceptance

Fetch the feature branch, use the existing Flutter 3.44.4 / Dart 3.12.2 toolchain,
Android SDK 36, Node 24, Java 21 and Chrome. Run sequentially from repo root:

```powershell
git fetch origin
git switch --track origin/feature/stage-2a-02-vendor-operations
flutter pub get --enforce-lockfile
flutter analyze
flutter test
Push-Location test/firebase
npm ci
npm test
npm run test:vendor
npm run test:dart
Pop-Location
```

If a local branch already exists, inspect/switch to it without creating another.
Stop any previous emulator processes before each npm runner. Set
`CHROME_EXECUTABLE` if Chrome is not found.

For manual Pixel 6 testing without production writes, start local Firebase
emulators in one terminal at repository root:

```powershell
.\test\firebase\node_modules\.bin\firebase.cmd emulators:start --project demo-smart-canteen --only auth,firestore --config firebase.json
```

Start the Android Studio Pixel 6 emulator; in another terminal run:

```powershell
flutter devices
flutter run --debug -d <android-emulator-id> -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2
```

This named demo Firebase app uses only local Auth/Firestore emulator services,
rejects release mode/nonlocal hosts and does not use the production default app's
services. The debug entry itself is unrun here. Register synthetic accounts and
complete the unchanged Stall Setup. No live-rule deployment is needed.

Acceptance checklist:

1. New stall starts Closed and shows its category default picture. Open/Close
   updates only after acknowledgement. Rapid taps produce one pending operation.
2. Stop/disconnect the local server: no success or new confirmed status is shown;
   error/cache labeling remains meaningful. Retry after reconnection.
3. Account name/email/phone/role remain read-only; Logout and four Vendor tabs work.
4. Edit name, each fixed category, prep-time boundaries and picture. Reject empty
   name, invalid prep times and unapproved categories. Cancel discards all changes.
5. Scroll to the final picture, select it, test Cancel and Confirm, then Save.
   Reopen the editor and restart/sign in: the saved picture and settings persist.
6. Inspect demo documents: owner UID/creation time/association stay unchanged.
   Run emulator rules tests for Student/cross-Vendor/timestamp/extra-field attacks.
7. Rerun original registration, reset, setup, Student navigation/Profile and Logout
   checks; confirm no picture control was added to Stage 1 Stall Setup.

## Remaining work and next milestone

Blockers: unavailable SDK/CLI tooling and failed proxy connection prevent runtime
and security validation here. Resolve these or execute the above checks locally.
Review this source and all rule results before a separate deployment decision.

After Stage 2A-02 review/acceptance, the next proposed milestone is Stage 2A-03
Vendor Menu Management with a reproduced protected category-reference design and
emulator security proof. Student browsing, food/cart/checkout, tickets/FCFS, queue,
ETA and notifications remain later work. No next milestone, merge or deployment
is authorized by completion of this batch.

## Stage 2A-03 — core checkpoint, 22 October 2026

Required base verified through connected GitHub and imported exactly:
`eff8c6e5235314a5e6c74af06cbbc17e07873ddf`. User-confirmed Stage 2A-02:
31 Flutter tests, 14 Stage 1 + 20 Vendor Operations rules tests, and Pixel 6
Android acceptance passed. Chrome/Dart loading stalled and remains incomplete.
The debug HTTP manifest and Windows launcher fixes are preserved.

Core source implemented: Vendor Menu tab; own-stall context; category creation
and stable-ID renaming with case-insensitive duplicate protection; Add/Edit Food,
integer-sen RM prices, existing picture picker, availability and atomic category
reassignment; cached/loading/error/empty states and optimistic revision checks.
No sample order or production Firebase data is written. E-D01/E-D02/E-S03 PNGs
are unavailable; written behavior is used without claiming missing visual approval.
V2-02, V2-03A/B and category-management screenshots were inspected.

Schema under `stalls/{vendorUid}`: `menuCategories/{categoryId}` stores name,
canonical lowercase `nameKey`, owner, revision and server timestamps;
`menuCategoryNames/{nameKey}` reserves the name for one stable category ID;
`menuFoods/{foodId}` stores owner, category, name, description, integer `priceSen`,
picture ID, availability, revision and server timestamps;
`menuMemberships/{foodId}` is the unique canonical active category reference.
Rules require food and membership after-states to agree. Reassignment replaces
the one active category reference in the same transaction. Unavailable food retains
its membership. Categories cannot be deleted by any client in this checkpoint.

Limits: category names 1–50 characters, trimmed/collapsed whitespace, no slash or
reserved Firestore document names; food names 1–100; description required 1–500;
price RM 0.01–1000.00 (1–100000 sen), at most two input decimal places.
Category names are unique per Vendor ignoring case/extra whitespace. Existing
23 PNGs/IDs are reused without duplication. No Student catalog access is added.

**Not complete:** P0-C has not been reproduced. Food deletion is implemented as
an atomic service operation but visibly disabled in production and denied by the
`menuDeletesEnabled()` rules gate; category deletion is unconditionally denied.
No unprotected empty-category check or counter is substituted. Empty-category
DELETE and deletion races need a reviewed, emulator-proven design before enabling.
Food Delete confirmation exists but cannot execute against the default safety gate.
Do not claim the full requested deletion workflow is ready.

At this core checkpoint: additional tests and analyzer review remain pending.
Flutter SDK is absent and its download uses an unreachable proxy; Firebase CLI
was absent in this environment. No new code is compiled or Android-tested yet.
No rules are deployed; local demo emulators must be used for validation. Existing
order snapshots are protected conceptually by never touching any order path.
This checkpoint is to be committed and remotely verified before further tests.

### Stage 2A-03 closeout and remaining work

Intermediate core backup verified on GitHub **before** adding tests:
`ee929c81533aad48e0950217688ebea25246eee1` on
`feature/stage-2a-03-vendor-menu`. Final branch-head verification is reported in
chat. Continue from that latest verified remote HEAD, never recreate from Stage 1.

Added runnable Flutter tests cover precise RM parsing/bounds, category normalization,
empty Menu, category creation/duplicate rejection, food field validation, failed
Save retaining draft, scrolling the existing picker, edit/reassignment/availability,
disabled deletes, confirmation Cancel, loading/error/cache/Retry, four tabs and
Logout. Existing Vendor navigation regression expectations now assert the real
empty Menu, and shared fixtures provide a synthetic menu repository. Existing
Stall Settings picker/operations tests are retained. No additional images,
dependencies, Android configuration or debug launcher changes were introduced.

New `test/firebase/vendor_menu.test.mjs` exercises normal creation/edit/reassignment,
unavailable-food references, atomic category rename and name uniqueness races,
malicious/ghost/duplicate references, invalid fields/prices/ownership/timestamps,
revision checks, cross-Vendor/Student attacks, blocked destructive writes and
creation/reassignment races against the **always-denied category delete**.
These last race tests prove the intended gate behavior only when executed; they
are not a positive proof of safe empty-category deletion. No new order documents
are created in tests. Menu writes only touch menu paths; future checkout still
needs immutable item snapshots (name, price and quantity) in confirmed orders.

Actual execution on 22 October:

| Check | Observed result |
| --- | --- |
| `flutter analyze` | Did not start: Dart SDK bootstrap cannot connect to proxy port 8080; exit 7 |
| `flutter test` | Did not start: same missing SDK / proxy failure; exit 7 |
| `npm run test:menu` | Did not start: Firebase CLI not found; exit 127 |
| `npm test`, `npm run test:vendor` | Did not start: Firebase CLI not found; exit 127 |
| `npm run test:dart` | Did not start here; existing user-reported Chrome loading stall remains unresolved |
| Node syntax checks: Stage 1, operations, menu modules | Passed syntax only |
| Git whitespace and protected-file comparisons | Passed |

Flutter/security test counts for this batch: **0 executed, 0 passed, 0 test-case
failures observed**. Bootstrap/launcher failures above are not passing tests.
P0-C: **not reproduced**. No new code or rules were compiled in this environment.
Manual Pixel 6 acceptance remains pending. The two historical informational lint
messages cannot be confirmed/resolved without working analysis or their output;
do not claim that informational analysis is clean.

Static rules budget review (not emulator measurements): a food+membership batch
has at most eight written get/getAfter calls before caching, each write path at
most four; category create/name-reservation at most four total, rename at most
seven across three writes. These estimates are below Firestore's 10-per-write and
20-per-atomic-operation access limits. Actual evaluation/expression counts and the
1000-expression limit have **not** been measured. Re-evaluate if rules/schema are
changed. The canonical membership design intentionally has no category scan,
unbounded membership arrays or client-maintained unprotected counters. A reviewed
empty-category deletion proof/design is still required; do not simply remove
`allow delete: if false` or flip the food-delete gate to obtain a passing UI.

Remaining implementation/acceptance gaps: positive Food Delete through the default
safety gate, positive empty Category Delete, deletion proof/races and measured rules
budgets; full executed Flutter/security regression; Pixel 6 UI and new-food happy
path acceptance; review of missing E-D01/E-D02/E-S03 visuals. The food deletion
transaction/confirmation is present but blocked; category deletion is not enabled.
This is a preserved partial Stage 2A-03 delivery, not a declaration of completeness.

Windows commands (use local demo emulators, never production testing):

```powershell
git fetch origin
git switch --track origin/feature/stage-2a-03-vendor-menu
flutter pub get --enforce-lockfile
flutter analyze
flutter test
Push-Location test/firebase
npm ci
npm test
npm run test:vendor
npm run test:menu
# Optional existing Chrome runner; do not wait indefinitely if loading stalls:
npm run test:dart
Pop-Location
```

Run npm suites sequentially. Start Firebase in another terminal from repo root:

```powershell
.\test\firebase\node_modules\.bin\firebase.cmd emulators:start --project demo-smart-canteen --only auth,firestore --config firebase.json
flutter run --debug -d <pixel-6-emulator-id> -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2
```

Register synthetic Vendors/Student, complete unchanged Stall Setup, create Rice and
Drinks categories, reject a duplicate ` rice `, Add Food with RM 8.50 and a picture
beyond the initial choices, Edit and reassign it, toggle Unavailable and confirm it
remains in the menu. Cancel drafts/dialogs and retry failed Saves; provoke a stale
revision from a second client and ensure it is not silently overwritten. Test
cached/read-error states, Orders placeholder, Profile/Logout and previous Stall
Settings picker. Both Delete actions must remain blocked with an explanation.
Prove rules locally and review before enabling any destructive operation. The
updated menu rules have not been deployed; normal live rules will not provide
these new menu permissions until a separate authorized deployment.

Recommendation: **hold approval for Stage 2B** until the core menu has compiled,
passed security/Flutter tests and Android acceptance, and deletion proof/gates are
resolved or explicitly scoped by review. Stage 2B browsing/read rules, Stage 2C
Cart/checkout/immutable order snapshots, and Stage 3 queue/FCFS/ETA/in-app Ready
notifications remain unimplemented. No merge, deployment, billing change or
production migration is part of this work.

## Stage 2A-03 finalization — deletion preparation, still gated

Exact existing branch HEAD verified through the connected GitHub integration
before edits: `14a9ff6f0885de8cb47b26f18efbd9a8580b920d`. Imported that exact
commit, including the user's non-null fake repository fix; no rebuild or rebase.

User-reported Windows acceptance at that base: **37/37 Flutter tests**, **28/28
`npm run test:menu` tests**, core Vendor Menu Pixel 6 acceptance, and analysis with
zero errors/warnings plus four informational lints. These are user results for
the base, not fresh results for the finalization. Earlier Stage 2A-02 acceptance
and the incomplete Chrome/Dart browser test remain recorded above.

Prepared stronger Food Delete authorization: before-state owner/category/canonical
membership checks plus atomic absence of both documents after deletion. The real
transaction verifies the displayed revision, reads membership/category before any
write, and deletes only the selected food/membership. UI preparation handles
Cancel, repeated taps, pending server confirmation, errors retaining data and
success feedback. **Food Delete stays disabled in both the real repository and
checked-in rules**, pending actual passing security tests and review.

The security suite opens only the food gate in an in-memory emulator rules copy
to test the candidate; a separate test uses the unchanged checked-in closed gate.
There are now 18 menu security cases, including authorized/unavailable deletion,
single/orphan/wrong/foreign pair denial, stale/repeated attempts, edit/delete and
reassignment/delete races, forged counters/revisions/names/timestamps, role attacks,
category-delete races and order namespace isolation. No order document fixture or
workflow is created. One additional Flutter widget test covers Delete Cancel,
pending/failure/retry/success through a test-only fake. These cases are unexecuted.

**Category Delete stays disabled unconditionally**, including empty categories.
The current canonical reference cannot prove zero category references. No count,
witness schema, migration or reservation cleanup permission is introduced.
[Deletion review](stage_2a_03_deletion_review.md) records the invariant, operation
read/write sets, counter/witness requirements, serialization, unavailable foods,
existing-data compatibility, static budget review and exact Windows commands.
P0-C positive Category Delete proof remains **not reproduced**. Closed-gate races
are not positive emptiness proof. Write-authorization estimate: six access calls
per deletion, twelve for the pair before caching; runtime accesses and expression
counts remain unmeasured.

Applied precisely the four supplied informational-lint fixes in Dashboard, Menu
(two sites) and profile widgets. Analysis has not rerun successfully here, so a
clean analyzer result is pending. Dashboard/Profile behavior is unchanged by those
syntax-only edits. Authentication, Stall Setup, Stage 2A-02 operations, Student
screens, all 23 PNGs, dependencies, Firebase configuration, debug HTTP/emulator
entry and Windows launcher are preserved.

Actual finalization commands: `flutter analyze` and `flutter test` each stop before
analysis/testing with Dart SDK bootstrap `Failed to connect to proxy port 8080`,
exit 7. `npm run test:menu` stops with `firebase: not found`, exit 127. Node syntax
checks of all three security modules and `git diff --check` pass. **Zero functional
or security tests executed here; no security/race proof claimed.** No Android
build/acceptance here. No production rules deployment or data/billing change.

Run the Windows commands and gated-control Pixel 6 checklist in the linked review.
Successful candidate tests require review before enabling Food Delete; category
deletion needs its own proven design. Preserve the verified remote backup and
resume from its exact SHA (reported in final chat / branch history). Do not
restart from Stage 1. Stage 2B browsing, Stage 2C Cart/checkout/immutable order
snapshots and Stage 3 queue/FCFS/ETA/notifications remain pending; none are started.

## Stage 2B — Student browsing and unpaid Cart

Required base verified through connected GitHub before edits:
`ba7edcf7661c62f7771ecae37b3cf57a17355bd0` on the existing Stage 2A-03 branch.
New branch: `feature/stage-2b-student-browsing-cart`, created from that exact commit.
User reports acceptance at that base: analyzer no issues, 38/38 Flutter tests,
38/38 combined menu security tests, previous core Vendor Menu Pixel 6 acceptance
and clean Windows working tree. These are user-reported results, not Codex reruns.

Intermediate checkpoint: Student Home real-time listings, stall-name-only search,
fixed category chips, loading/error/Retry/cache/empty states; minimal owner-published
`publicStalls/{vendorUid}`; existing raw stall/profile/membership/name privacy;
Student categories and `available == true` food queries against the original menu
schema. Owner status/settings transactions publish matching public fields atomically;
once published, rules reject stale standalone source changes. Existing stalls are
published idempotently when the owning Vendor views a server-confirmed Dashboard,
or saves status/settings. No bulk migration or Student backfill rights. Vendors who
have not returned to the app do not automatically appear. Publication failures
preserve Dashboard reads and retry on a subsequent server snapshot/visit.

Only public name/category/status/preparation/picture/vendor ID/update timestamp are
copied, never arbitrary legacy fields or user contact details. Student reads of
raw `stalls` remain denied. No new Student writes or menu duplication. Both delete
gates remain false. Eight new runnable catalog security scenarios are added;
`npm run test:student` includes all earlier rule suites. SDK remains absent and
proxy port 8080 is unreachable; Firebase CLI is absent. No runtime pass is claimed.

Student S2-01/02/03 PNGs are not in supplied ZIPs; the approved written handover was
inspected and is used. Missing visual references are not claimed reviewed.

That intermediate checkpoint was verified on GitHub at
`6bc6af9331c678f3c79d184b2deb17ea092b0f56` **before** continuing Stall Menu/Cart.

### Stage 2B final implementation and acceptance pending

Implemented Stall Menu: live stall/category/available-food data, category filters,
description/picture/integer RM price, quantity selection, server-only selection
refresh, cache/Closed/unavailable gating and error/Retry. No duplicate menu database.

Implemented a local session-owned unpaid Cart: one Vendor; four distinct foods;
1–20 units per item; integer-sen item and total arithmetic; add/increase/decrease;
confirmed Remove/Clear; switching-stall confirmation that preserves the old Cart
on Cancel or failed verification; empty state/browse navigation; visibly disabled
Stage 2C Checkout. Cart survives tabs/details, clears on logout/account change or
process exit, and never writes Firestore. UID-scoped authenticated routes dispose
Student menus/dialogs with the Cart when the account changes. Profile UI is unchanged.

Live menu listeners flag stale prices/names/category assignments, unavailable food,
Closed stalls and unverified cached/error states. Old snapshots/totals persist until
confirmed Review Changes with another server read. Future Stage 2C must securely
revalidate canonical status/food/membership/price/quantity/limits and immutable order
snapshots atomically; these unpaid display checks are not checkout guarantees.

New tests: 5 Cart controller + 6 browsing/Cart widget cases; 8 Student catalog rules
cases. Updated combined command `npm run test:student` includes all four rules
modules (46 registered top-level cases, **not observed passes**). Existing auth test
Cart expectation now checks the real empty Cart. All prior Vendor source/delete
gates, 23 PNGs, dependencies, production config and debug/Windows setup are preserved.

Actual execution: all four `node --check` security module checks and Git whitespace
checks passed. The combined Firebase command stops with `firebase: not found`,
exit 127. Dart SDK/executable are absent and the network proxy remains unreachable;
`flutter analyze` / `flutter test` were **not run**, avoiding repeated failed SDK
downloads as requested. **Zero new functional/security tests executed; no compile,
Android acceptance, rule proof or runtime budget measurements claimed.** Historical
Chrome/Dart loading remains incomplete and does not block ordinary Android testing.

[Stage 2B implementation/security/Windows acceptance guide](stage_2b_student_browsing_cart.md)
records the exact schema, permissions, existing-Vendor publication requirement,
rules compatibility, limits, all test commands and Pixel 6 checklist. Existing Vendors
must revisit the new app or save settings/status to publish; no automatic production
backfill is done. Missing Student PNGs remain a visual-reference gap. The final
verified branch SHA is reported in final chat and GitHub history. Resume from that
verified commit. Stage 2C Checkout/Orders and Stage 3 queue/FCFS/ETA/notifications
remain unimplemented and require later review; no merge, deployment or paid service.

## Stage 2C — core checkpoint

Verified latest GitHub Stage 2B verification-fix HEAD and imported its exact tree:
`7ba35a219b5f3267d1b95941265a7166cc70b024`. Created the new
`feature/stage-2c-checkout-orders` branch from that exact commit, retaining all
user test fixes. User reports Stage 2B Flutter/analyzer, 46/46 rules and core Pixel 6
acceptance; simultaneous-account manual Cart acceptance remains deferred. These
are user-reported base results, not Codex reruns.

Core proposed implementation: durable owner-scoped checkout requests; immutable
Pending orders with first item inline and up to three bounded child snapshots;
atomic per-stall monotonic ticket counters; same-ID retry/recovery; safe terminal
discard of unconfirmed requests. Rules validate canonical food/category/membership,
Open source stall, snapshots, quantities, distinct IDs and integer totals. Private
raw stall/membership reads are not opened to Students. No Stage 3 transitions.

**Checkout confirmation and all new write rules remain gated false pending
executed proof and review.** At the intermediate checkpoint UI/tests are pending.
[Stage 2C handover](stage_2c_checkout_orders.md) records schema, invariants, recovery
and the unmeasured 10-per-header / 20-distinct-state worst-case access estimate.
The expression budget is unmeasured. SDK/CLI remain unavailable, proxy port 8080
unreachable; no download retry or runtime pass is claimed. Both Vendor Delete
gates remain closed. Back up and verify this checkpoint before UI/tests continue.

### Stage 2C final source / proof and enabling still pending

Intermediate core backup verified on GitHub before UI/tests:
`dc40fe4bb42c570caa42e291ae3ebfeddea39e48`. Continued on the same Stage 2C branch.

Implemented eligible Cart → Checkout Review, simulated methods/no-money message,
same-ID pending/retry/discard controller, Cart locking and receipt-only clearing,
success/ticket view, Student Orders/details/persisted-request recovery and read-only
Vendor inbox with live immutable snapshots/ticket ordering. Added targeted item
Retry, cached labels, stable order-card identities and account/session isolation.
Student Queue remains a placeholder. No Stage 3 status actions or queue/ETA work.

**Confirm Order and all request/order/counter writes remain disabled in the real
client and checked-in rules.** Safe client-only checkout has not been demonstrated
here. The candidate proof opens only an in-memory emulator gate. Static budget
estimate is at 10 header / 20 distinct write-authorization states for four distinct
categories, depending on cache reuse; transaction read authorization and expression
quotas are also unmeasured. This is a precise blocker, not successful Rules proof.
Both old Vendor delete gates remain closed.

New runnable coverage: 8 controller/model + 6 UI tests; 19 new checkout security
cases, including direct malicious writes, canonical membership/category checks,
same-ID retries, parallel per-stall ticket assignment, immutable order history,
safe request discard races and offline behavior. `npm run test:checkout` includes
all prior suites (65 registered cases, not observed passes). Raw Rules coverage is
saved to an ignored artifact when available, without claiming per-request counts.

Actual checks: all Firebase `.mjs` syntax checks, Git whitespace checks and 42
protected-file byte comparisons passed, including 23 PNGs and user Stage 2B fixes.
The Firebase runner stops with `firebase: not found`, exit 127. Flutter/Dart SDK is
absent; analyze/test were not run and no repeat download was attempted. **Zero new
functional/security cases executed; Dart/Rules uncompiled; Android, race proof,
ticket proof and runtime expression/access evidence pending.** Base acceptance
and deferred simultaneous-account manual Cart scenario remain as recorded above.

The [Stage 2C handover](stage_2c_checkout_orders.md) contains schema, invariants,
two-phase recovery/tombstone lifecycle, exact commands, gated versus later-enabled
Pixel 6 checks, unmeasured limitations and the Stage 3 integration contract. Missing
Student order/checkout PNGs are recorded; written approved behavior was used.
Final verified GitHub SHA is reported in final chat/history. Resume there, never
rebuild. No main merge, production rules/data change, migration or paid service.
Stage 3 requires successful proof, review, a separate gate-enabling change and
complete checkout/Student/Vendor Android acceptance first.

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

### Stage 2C focused security repair — final source, proof pending

Core backup verified on GitHub before test work:
`87b8d45fbc8561cee0ea2597cdae6d8a87d4cad2`. Continue on the same
`feature/stage-2c-checkout-orders` branch. Final verified SHA is in the final
report/GitHub history; resume from it rather than rebuilding. Main is unchanged.

Rules now validate each canonical snapshot once at its creating document, require
all bounded child slots, and bind the header total to the immutable, sum-validated
draft. Exact canonical map equality/diffs preserve all field/ownership/price/
availability/category/membership checks. Four products and the existing schema
remain supported by the source. No production migration is needed. The inductive
child/total invariant, unchanged static access estimate at the limit and remaining
unmeasured runtime budget are documented in the Stage 2C handover. This is a
candidate repair; fitting the 1,000-expression ceiling has NOT been proven here.

Client/helper contention recovery is bounded and requires server-observed changed
state/counter before retrying permission errors. Stable-input permission failures
still fail; same identity and server receipt requirements remain. Fresh demo
databases isolate each test; all parallel operations settle before reporting
failures and both race outcomes are checked. No checkout `clearFirestore()` race
remains. Actual RPC disconnection replaces the invalid read-only offline assertion.
Connectivity failure is required and independent server checks prove no order or
ticket. Android offline behavior remains untested.

The combined runner retains the earlier 46 cases unchanged and contains **23
checkout cases: 69 total expected, not executed here**. Added maximum-size direct
attacks at every slot, canonical category/membership corruption, detached/extra
child protection and stable-permission-error checks. Parallel same-ID/Students
and discard races now exercise four products. The wrapper fails on emulator/client
expression/access exhaustion even when a negative assertion gets permission-denied;
missing/empty debug-log evidence also fails. Raw coverage and diagnostic artifacts
are ignored, not pushed or represented as measured expression counts.

Actual Codex checks: diagnostic unit test **1/1 passed** (six assertions), all 11
Firebase `.mjs` syntax checks passed, Git whitespace checks passed. Four earlier
security modules and protected app/config/assets outside the checkout repository
are unchanged from the starting HEAD. Flutter/Dart SDK, Firebase CLI and Node
dependencies are unavailable; no runtime Rules/Flutter suite, compilation or
Android acceptance was run and no download was retried. Historical Windows
results remain analyzer clean / Flutter **63/63** / old security **58/65**, with
the seven failures recorded above. They are not passes for this revision.

[Updated Stage 2C Windows/Pixel 6 instructions](stage_2c_checkout_orders.md)
include `npm ci`, `node checkout_budget.test.mjs`, `npm run test:checkout`, log/
coverage evidence, Flutter checks and gated-build acceptance. All **69 security
cases plus the budget guard must pass locally** before security proof can be
reviewed. Both checkout gates and both Vendor deletion gates remain disabled.
No Firebase deployment/data change, merge, SDK/dependency version change or new
feature is included. Stop for review; Stage 3 queue/FCFS/ETA/notifications remain
pending separately, and the historical Chrome/Dart loading gap remains open.

## Stage 2C — approved two-food scope, 22 October 2026

This entry supersedes earlier four-food limits and test counts above. The user
approved a maximum of **two distinct foods per Cart/order**, retaining twenty
units per food, one stall, integer-sen totals, simulated payment and all canonical
ownership/integrity, ticket, idempotency and concurrency protections.

Verified and imported latest GitHub base
`341e7c2d051a15a2f19fe47e26862cac0e048df0` before editing, preserving the user's
compile, mounted-context, nullability and broadcast-stream/widget fixes. Earlier
repair backups `87b8d45` and `260f176` remain in history. Resume from the new exact
verified final SHA in the delivery report/GitHub branch, not an older checkpoint.

User's local evidence before this change: analyzer passed, Flutter **63/63**;
positive one/two-food checkout passed without Rules exhaustion; three/four foods
failed the 1,000-expression ceiling; preceding full suite had **53 budget
diagnostics**. Working tree was clean. This is historical Windows evidence, not
verification of the new two-food commit or a complete successful security proof.

Implemented shared two-product/twenty-unit constants across Cart/eligibility,
models, controller, repository and UI labels. A third distinct ID is rejected
without discarding selections; additional units of existing foods remain allowed.
Model construction/decoding and receipt integrity enforce the limit. Rules allow
one inline snapshot and optional child `items/1` only, reject oversized preparation
and confirmation, and remove unused third/fourth slot checks. Canonical source
food/category/membership, availability/price/revision, stall and owner checks are
preserved. Transactions still atomically confirm immutable snapshots, consume one
sequential stall ticket and retain the same ID for retry/discard/recovery.

Adapted maximum-size malicious snapshot/missing-document/canonical/ownership/race
cases to two foods. Explicit separate three/four/five-food rejection cases also
test seeded legacy oversized drafts and verify no order/ticket is created.
Duplicate IDs, invalid quantities at either slot, forged totals, unique sequential
tickets across four Students, same-ID replay and discard assertions remain.
The four earlier security suites/46 cases are unchanged. Combined runner now has
**70 expected security cases (24 checkout + 46 earlier)**; zero budget diagnostics
and all assertions passing are mandatory. A failing negative test cannot be
rescued by expression/access exhaustion. None of these security cases ran here.

Offline investigation retains strict connectivity-only expected errors. The test
now proves the online RPC traversed its forwarding socket before disconnection,
then attempts real two-food checkout with all old/new RPC sockets blocked and
checks pending/no-order/no-ticket through another client. Arbitrary permission
or other exceptions do not qualify. Added an executable standalone transport test;
its success proves the transport, not Firestore/Android offline behavior.

Actual Codex results for this revision:

- Diagnostic unit test **1/1 passed**; offline transport unit test **1/1 passed**.
  The first restricted transport run failed with localhost `listen EPERM`; the
  approved rerun allowing temporary localhost sockets passed.
- All **12** Firebase `.mjs` syntax checks and Git whitespace checks passed.
  Protected source/config/assets and earlier security modules were byte-checked.
- Four new Flutter cases cover two-food eligibility/third rejection, twenty units
  each, exact controller totals, oversized model records and Pixel 6 Cart labels;
  existing Cart-limit and Checkout Review assertions were updated.
- Flutter analyze/tests, Rules compilation, the 70-case emulator suite, budget
  counts, actual Firebase concurrency/offline proof and Android remain **unrun**.
  Flutter/Dart, Firebase CLI and Node dependencies are unavailable; no SDK or
  dependency bootstrap/download was retried. No runtime pass is inferred.

The [current Stage 2C handover](stage_2c_checkout_orders.md) documents the reduced
schema, unchanged invariants, static/unmeasured budget, exact Windows/Pixel 6
commands, all evidence and blockers. Historical Chrome/Dart loading remains open.
Checkout Rules and the real client stay false; both Vendor deletion gates remain
closed. No main merge, rules deployment, production data/migration, billing change,
paid service or Stage 3 work is included. Stop after implementation for exact-commit
local verification; enabling checkout and Stage 3 require successful proof/review.

## Stage 2C — final offline assertion correction, 22 October 2026

Verified base: `1ace379bc02c8bb0d33b3aa131fc99e36d81d9cf` on the existing feature
branch. User Windows evidence: analyzer PASS; Flutter **67/67**; security **69/70**;
**zero Rules-budget diagnostics**. One/two-food checkout, over-limit three/four/
five rejection, same-ID recovery, concurrent sequential tickets and the standalone
transport test passed. Only the offline integration assertion failed, receiving
`FirebaseError: 1 CANCELLED: Call cancelled` after the deliberate RPC cut.

Source investigation confirmed locked grpc-js 1.9.16 maps HTTP/2 `NGHTTP2_CANCEL`
to CANCELLED / `Call cancelled`; Firebase maps the status while preserving the
message. Current gRPC source also documents Node generating cancellation resets
on connection drops. The exact observed cancellation is legitimate in this
controlled test. This finding is not a newly reproduced Cloud Firebase result.

Focused test-only correction accepts code `cancelled` and **exact** message
`1 CANCELLED: Call cancelled` only after the verified online path and deliberate
cut, alongside `unavailable`. Generic cancellation, permissions, unknown/arbitrary
errors, success and deadlines/timeouts are not accepted. All other security cases
are unchanged. Explicit independent server-only assertions now run before cleanup:
no successful confirmation, no order, absent/unchanged counter and unchanged
pending request. Listener close and SDK termination have separate five-second
bounds; cleanup deadlines fail rather than becoming offline proof. Transport
never reconnects. Added pure matcher and cleanup unit assertions beside the
existing real loopback transport test; no application/Rules changes were needed.

Actually executed in Cloud: transport/helper **3/3 passed**, budget diagnostic
**1/1 passed**, all twelve Firebase `.mjs` syntax checks and Git scope/whitespace
checks passed. The other 69 security cases and all production source/Rules/config/
dependency files are byte-preserved. Flutter, Rules compilation, actual Firebase
offline execution, the full 70-case suite and Android were **not rerun**: SDK,
Firebase CLI and Node dependencies remain unavailable. No SDK/download retry.

The [handover](stage_2c_checkout_orders.md) records source evidence, exact matcher,
server assertions, bounds and Windows commands. The final verified GitHub SHA is
in the delivery report/history; resume there. Local success still requires **70/70
and zero budget diagnostics** on that exact commit. Both checkout gates and both
Vendor deletion gates remain closed. No production deployment/data change, main
merge, scope expansion, paid service or Stage 3 work is included. Stop for review.

## Stage 2C — emulator-only Android checkout activation, 22 October 2026

Verified latest remote starting HEAD:
`7c9ee91618a73b77a858900e84919b250ef7d030`. The user reports **70/70** security
cases passed, **zero** budget diagnostics, budget unit PASS, transport units
**3/3 PASS**, and previously clean Flutter analysis / **67/67** Flutter tests.
These are Windows acceptance of that starting commit, not Cloud reruns. Actual
Pixel 6 checkout and a simultaneous Vendor live inbox are the remaining acceptance
step; Stage 3 has not begun.

Authorized only a local demo activation. Added `scripts/start_checkout_demo.cmd`
and its Node launcher/generator. It permits only `demo-smart-canteen`, invokes
only local Auth/Firestore emulators using the project's pinned CLI, refuses
arbitrary Firebase arguments and changes only the single checkout gate in a
temporary copy of checked-in Rules. Both Vendor deletion gates must remain false.
Rules/config/logs are outside the repository in an owned OS temporary directory;
default temporary project is demo-only, config is explicitly selected and no
default deploy config is generated. Normal shutdown removes the files; ignore
patterns add protection against accidentally copied artifacts. Production
`firestore.rules`, `firebase.json` and existing configuration are unchanged.

The production `main.dart`, Auth/Order repositories and checkout transactions
remain byte-identical and disabled. Private subclasses in `main_emulator.dart`
enable only the demo repository after emulator setup and only with all runtime
conditions: debug, emulator entry point/setup, exact named synthetic Firebase app,
`demo-smart-canteen`, explicit `EMULATOR_CHECKOUT=true`, synthetic options and a
local port-8080 non-TLS endpoint. Normal main, profile/release, default/foreign/
production apps, wrong endpoints and runs without the flag fail closed. Existing
two-food/twenty-unit bounds, snapshots/tickets, Cart recovery and simulated payment
are unchanged. No other security gate is opened.

Cloud execution: launcher/generator tests **7/7 passed** after fixing an optional
absent `.firebaserc` test fixture and allowing the sandboxed negative-launch
subprocess. The subprocess rejected a real project before Firebase startup.
Node syntax, temporary-file cleanup, Git scope/whitespace and protected-source
checks passed. No Firebase emulator or production service was started.

Written but unexecuted: **3 Flutter gate tests**, including 48 combinations of
debug/entry/flag/app/project and additional synthetic/setup/endpoint checks plus
the normal repository's closed gate. Flutter/Dart, Firebase CLI/dependencies and
Windows shells are unavailable here; actual Windows CLI startup/Ctrl+C cleanup,
Rules compilation, Flutter full regressions, the 70-case security rerun and Pixel
6/two-device live receipt remain local acceptance. No bootstrap/download retry.

[Beginner Windows/Pixel 6 demo guide](stage_2c_emulator_checkout_demo.md) contains
exact preparation/start/run commands, synthetic Vendor/Student workflow, two-device
live-inbox demonstration and safe stopping. Stop the manual demo before security
tests reuse its ports. Latest verified final SHA is in the delivery report/history;
resume from that branch commit. Production checkout and both deletion gates remain
closed. No merge, deploy, paid service, Windows permission/policy change,
production data access or Stage 3 implementation is included. Stop for review.

## Stage 3A — Vendor FCFS candidate checkpoint (22 October 2026)

Supersedes the earlier “Stage 3 not started” status. Verified base:
`9da8298418eaeedbae002903504a6f5a84f59407`; new branch
`feature/stage-3a-vendor-fcfs`. User-reported Windows acceptance of that BASE:
Flutter analyze clean, Flutter 70/70, Firebase 70/70, zero Rules-budget diagnostics,
and Pixel 6 Student Ticket #1/#2 confirmed and received by Vendor. Those results
are not candidate validation.

Candidate adds a protected per-stall next-ticket/single-preparation-slot cursor,
paired Rules enforcement, immutable transition timestamps/revisions, Vendor
status actions and readable status badges, real-time Student status decoding and
live details. Checkout transaction, two-food/quantity bounds, existing demo
launcher and all production/deletion gates are preserved. Processing is enabled
only by the isolated flagged debug emulator repository.

See [Stage 3A architecture and verification](stage_3a_vendor_fcfs.md) for the FCFS
inductive invariant, schema, limitations and test status. New adversarial/race
Rules tests are written but not emulator-executed. Flutter/Dart and Firebase CLI
are unavailable in Cloud. Focused Flutter tests and final checks/documentation
are pending at this intermediate checkpoint. Stage 3B Student Queue/ETA and 3C
notifications remain unstarted; no Firebase rules have been deployed.


## Stage 3A — final candidate handover (22 October 2026)

Intermediate GitHub backup verified on `feature/stage-3a-vendor-fcfs`:
`e6ec9c18a9c1ce16a14f48f8acf8d02f6ae8f499`. The final delivery commit adds focused
Flutter coverage, tighter retry/refresh gating and this verification handover.
The exact final branch SHA is supplied in the delivery report; use `git rev-parse
HEAD` after fetching/switching to verify that candidate locally.

Implemented Vendor Pending → Preparing → Ready → Completed with owner-only,
reciprocal order/cursor Rules checks. At most one Preparing; only the exact next
per-stall ticket may start. Ready releases the slot; completion follows collection
and does not occupy it. New protected `vendorQueues/{vendorUid}` stores the next
never-started ticket, active preparation ID and revision. Orders gain immutable
transition timestamps and monotonic status revisions; all accepted checkout
identity/snapshot/payment/total/ticket fields and child items stay immutable.
Legacy Pending records need no migration. Details now listen to current order
status for both roles. Vendor cards retain the approved orange/white style, show
readable badges, ticket/time/items/quantities/total, actions and status filters.

The existing checkout transaction body and retry/recovery protocol are unchanged.
Processing is enabled only inside the existing isolated flagged debug/demo entry;
normal/release/production client processing remains disabled. The checked-in
checkout gate, Food Delete and Category Delete remain closed. No deployment,
production data write, billing change, Function, ETA, Student Queue or notification
work was performed.

Cloud actual results: **11/11 Node regression tests passed**, covering the unchanged
emulator launcher (7), Rules-budget detector (1) and transport/cleanup helpers (3).
JavaScript syntax checks for the three new/extended FCFS-related modules and
`git diff --check` passed. **Flutter analysis/tests, Rules compilation, all emulator
security cases and Android acceptance were NOT executed in Cloud.** Usable
Flutter/Dart SDK binaries, Firebase CLI and Firebase npm dependencies are absent;
no SDK downloads were retried. Base acceptance remains the user's 70 Flutter /
70 security / zero-budget Windows report, not proof of this candidate.

Added **13 Flutter tests** and **19 Rules tests**; `npm run test:fcfs` runs all earlier
70 security cases plus these 19, preserving strict intended-denial checks and
whole-run budget log inspection. Cases include stale/direct/immutable attacks,
FCFS races, wrong owners/roles/stalls, real-time delivery and verified offline
transport loss with independent server assertions before bounded cleanup.
The written FCFS induction and static document-access review support the design;
actual expression/access budgets and race outcomes remain unverified until the
Windows suite passes with zero diagnostics. Do not represent this as executed
server proof or production-ready deployment.

[Stage 3A architecture, exact commands and Pixel 6 checklist](stage_3a_vendor_fcfs.md)
contains beginner steps for `flutter analyze`, `flutter test`, `npm run test:fcfs`,
the preserved safe demo launcher, flagged Android debug run and safe shutdown.
Next step is local review/acceptance of this exact candidate; resolve any new
analyzer/test/Rules failures first. The old Chrome integration loader stall remains
an unpassed historical gap. Stage 3B Student Queue/ETA and Stage 3C notifications
remain unstarted and require separate authorization.

## Stage 3B candidate checkpoint — 23 October 2026

Verified Stage 3A base `2f950fa600d72ac3b01486aaea0e07571f053feb`; new branch
`feature/stage-3b-student-queue-eta`. The user confirmed base Windows acceptance:
analyze clean, Flutter 83/83, Firebase FCFS 89/89, zero budget diagnostics, Pixel 6
checkout, FCFS, progression and Student history/details passed.

Candidate implements own-Student real-time Queue/History, per-stall numeric
progress, deterministic orders-ahead and approximate time until Ready, cached /
missing / syncing / overdue / error handling. New owner-validated queueProgress
projection has no preparingOrderId or Student details, and is required atomically
on cursor transitions. Existing private cursor/FCFS and immutable receipts remain
protected. Vendor bootstrap of missing legacy progress is exact and non-advancing.
Cart and Checkout use the actually visible original inline reference images,
adapted to TWO foods, existing assets, simulated payment and accepted safeguards.

Cloud: 11 Node regression tests passed; new/updated JS syntax and Git whitespace
checks passed. New 15-case queue security suite is unexecuted; the combined runner
retains the previous 89 cases. Flutter SDK, Firebase CLI and Android unavailable;
Flutter tests and final verification/documentation are pending at this checkpoint.
No SDK downloads retried. No deployment or Stage 3C work. See
[Stage 3B architecture and acceptance handover](stage_3b_student_queue_eta.md).

## Stage 3B final candidate handover — 23 October 2026

Intermediate backup confirmed through GitHub on feature/stage-3b-student-queue-eta:
`fa451b9bd45dfaaa71056570561f55846bd4b185`. The delivery report gives the exact final
commit SHA (the commit containing this handover); verify with git rev-parse HEAD
on Windows. No main/Stage 3A ref update, force-push, merge or deployment.

Implemented candidate: own-Student real-time Queue with Active/History, statuses,
stall-isolated ticket progress, deterministic orders ahead, approximate time until
Ready, last-updated labels, missing/syncing/elapsed/cached/error states and Retry.
Ready/Completed are no longer waiting. Per-order configured preparationMinutes
snapshots remain the baseline; no invented averages, statistics or countdown.

The public six-field queueProgress projection contains only stall ID, schema,
next-ticket/revision numbers, preparation flag and authoritative timestamp. Every
Start/Ready transaction atomically updates order/cursor/projection. Rules require
exact matching after-state, actual cursor advancement for updates, monotonic
projection revisions and strict shape/ownership. Students gain only per-stall
GET permission to aggregates for published stalls. Private preparingOrderId,
other Students' orders and source stalls remain protected. Existing checkout is
the sole unchanged Student ticket-allocation protocol; Queue has no write action.
Vendor Orders can publish a missing initial/legacy projection exactly without
advancing/resetting the queue; missing data otherwise stays unavailable.

Both inline original references were actually visible: My Cart and Checkout &
Payment. Those screens now follow their orange rounded headers, stall context,
white bordered cards, large local food pictures, quantity controls, summaries,
orange totals and full-width payment selection/actions. Three-product sample
content yields to the two-food business limit. Checkout navigation has real
callbacks; pending submissions lock it. Receipt styling is consistent. No
unrelated Vendor/Auth/Student Profile redesign or new image library.

Cloud results: original 11 Node safety/budget/transport cases passed, with the 7
launcher cases rerun successfully after final Rules changes; JS syntax checks of
four queue/FCFS/runner modules and Git whitespace checks passed. A supplemental
Dart lexical delimiter audit passed; NOT compilation/analysis. Source comparisons
confirmed checkout transaction/retries, controller, Cart model, limits, launcher,
dependencies and prior 70 security source files unchanged. All 83 earlier Flutter
case declarations and 19 FCFS case names remain; only necessary UI finders and
atomic-projection test fixtures were adapted without removing assertions/cases.

Added 19 Flutter cases and 15 projection security cases. Expected full suites:
Flutter 102 (83+19), Firebase 104 (89+15). **Neither full suite, Flutter analyze,
Rules compilation/budget execution nor Android acceptance ran in Cloud.** Flutter /
Dart binaries, Firebase CLI and npm dependencies are unavailable. No repeated SDK
downloads attempted. Base Windows acceptance 83/89/zero diagnostics remains a base
result only. The historical Chrome loader integration gap remains unpassed.

[Stage 3B handover and exact Windows/Pixel 6 instructions](stage_3b_student_queue_eta.md)
records formulas, privacy/atomic proof, conservative access-call review, test
commands, visual adaptations, bootstrap behavior and known ETA limitations. Require
all local checks passing and zero budget diagnostics before accepting the candidate.
Checkout and both deletion gates stay closed in checked-in Rules; existing safe
emulator-only launcher is preserved. No production Firebase writes, billing,
Functions or real payments. STOP: Stage 3C Ready notifications remain unstarted.

## Focused Vendor UI polish — 24 October 2026

Base independently verified on GitHub:
`3be2117e7d868110be9ea678c8ce97beef4f8596`
(`fix: stabilize Stage 3B cart and checkout UI`). Its five changed blobs and full
Git tree were imported exactly because shell Git could not reach proxy port 8080.
New branch: feature/final-ui-vendor-polish. The final delivery SHA identifies the
candidate containing this handover; use git rev-parse HEAD after fetching it.

Vendor Menu, Vendor Orders and shared Student/Vendor Order Details now use the
accepted Dashboard/Profile orange rounded header, white bordered cards, spacing
and type hierarchy. Menu has clearer pictures/prices/availability and responsive
actions. Orders has readable tickets/status/items/totals and horizontal filters.
Details groups the live immutable receipt into overview, information, items and
simulated payment sections, with real dates/statuses and cached/error feedback.
Details remains read-only; Vendor transitions stay in Orders. Existing disabled
Food/Category Delete and all checkout/FCFS business rules are preserved.

All eight supplied screenshots were actually opened: two accepted Dashboard /
Profile, three current Details/Orders/Menu, and V2-02 / V2-04 / V3-02 references.
No personal account data or images from those screenshots were committed.
[UI polish handover](final_ui_vendor_polish.md) records exact filenames, visual
adaptations, changed files and beginner Windows/Pixel 6 acceptance instructions.

Cloud actual results: 11/11 existing Node launcher/budget/transport checks passed;
Git whitespace, protected-source comparisons and a supplemental Dart lexical
delimiter audit passed. Flutter analysis/compilation/tests, Firebase emulator tests
and Android/visual acceptance were NOT executed: required SDK/CLI/dependencies are
unavailable. Added 12 focused widget cases; all previous Flutter test files and
Firebase security coverage remain unchanged. No assumed new Flutter/Firebase
pass counts or repeated SDK downloads.

A 76-file source audit preserves Rules, services/models, assets, dependencies,
launcher, accepted Dashboard/Profile, Student Queue and latest Cart/Checkout fixes.
Menu/category callbacks and order/FCFS eligibility are unchanged. Home has only
the Vendor Orders AppBar adjustment. No gates, transactions, cursor/projection,
queue calculations, security tests, production data/rules, billing or paid services
were changed. No merge, rebase, force-push or deployment. Stop for local review:
Student Queue readability and Stage 3C notifications remain unstarted.

## Focused Student main-screen UI polish — 24 October 2026

Source: GitHub-confirmed `feature/final-ui-vendor-polish` at
`92710b06ffdddc6be837d906074b244c63bafdc1`, including its local scrolling/Material/layout fixes.
New branch: `feature/final-ui-student-polish`. The delivery report supplies the final verified GitHub SHA.
The user reports 114 passing Flutter tests for the base; those are not Cloud results for this candidate.

Home, Stall Menu, Student Orders, Profile and Queue now follow the accepted orange rounded headers,
20px spacing and white bordered cards. Home/Menu pictures are compact, stall status and prices readable,
and food selection still uses the original dialog/validation. My Orders keeps real immutable snapshots,
actual status, totals and unconfirmed recovery. Profile shows only existing read-only fields and safe Logout.
Queue prioritizes stall/ticket/status, large orders-ahead and approximate until-Ready values;
long explanations/timestamps move into How this estimate works. Essential stale, unavailable,
synchronizing and elapsed-estimate warnings remain visible. Refresh and shared Details are preserved.

Inspected all five images in `To_Improve_Student_Screen.zip`, all three in `Approved_Screen.zip`
(Vendor Menu, Vendor Orders, shared Details), and reopened the earlier accessible Dashboard/Profile
screenshots from `Improved_Current_Screen.zip`. No reference gap. No personal screenshot data committed.

Rules, Firebase services/transactions, FCFS cursor/projection, queue/ETA formulas, security tests,
checkout limits, dependencies, assets and local emulator launcher are unchanged. Accepted Vendor
rendering and shared Details are preserved; Cart/Checkout source and navigation callbacks are unchanged.
All existing Flutter tests remain byte-for-byte intact. Production checkout and Food/Category Delete
remain gated. No production connection/deploy, merge, migration, paid service or Stage 3C implementation.

Cloud checks actually executed: existing Node launcher/budget-detector/offline-transport checks **11/11 passed**
after granting their required local process/socket execution; the first sandbox attempt could not execute two
files. `git diff --check`, a protected-source audit (239 unchanged tracked files) and a Dart lexical delimiter
check passed. The lexical check is not compilation. **Flutter analyze/tests, Firebase emulator suites and
Android/manual visual acceptance were not run** because their tooling is unavailable. The new
`test/student_ui_polish_test.dart` contains 20 unexecuted widget cases covering the five screens, Pixel 6,
320×640/1.6× text, real queue values/statuses, warnings/refresh, selection guards, recovery and session/Logout.
No new emulator Rules-budget result is claimed. The historical stalled Chrome/Dart test remains unverified.

See [Student UI verification and Pixel 6 guide](final_ui_student_polish.md) for exact Windows commands,
inspected filenames, changed-file list, expected behaviors and safe demo shutdown.
Run `flutter analyze`, the focused widget file and full `flutter test`, then optionally the unchanged
`npm run test:queue` suite (zero budget diagnostics required). Manually review the five screens and
accepted-screen regressions on the Pixel 6 using the existing demo-only launcher and debug entrypoint.
Candidate is ready for local review, not accepted on Android yet. Stop here; Stage 3C Ready notifications
remain the next separate task after review. No notification, payment, billing or production work is authorized by this batch.

## Stage 3C Ready notifications and Stall Menu header — 24 October 2026

Verified remote base: latest `feature/final-ui-student-polish` at
`a5847df924b0a22a86d1135f40bbd5c4884c8ed5` (`fix: stabilize student UI quantity and cached request tests`).
Both locally repaired source/test files were imported exactly before editing.
Candidate branch: `feature/stage-3c-ready-notifications`; delivery report gives the verified GitHub SHA.
User-reported prior Windows acceptance: **134/134 Flutter tests**, **104/104 Firebase security cases**,
zero Rules-budget diagnostics, accepted Android checkout/FCFS/queue/UI. These are base results, not
Cloud executions of the new candidate.

Implemented the isolated Stall Menu Back/title/live Cart row with measured-width and enlarged-text
fallback, preserving 48px controls and existing menu/Cart behavior. Other headers are unchanged.

Implemented a session-scoped read-only Student Ready controller using existing authenticated order streams.
Canonical Ready/Completed status, revision and Ready timestamp supply records; no notification documents,
client notification writes, queue/cursor reads or new permissions. Existing Firebase stream metadata filtering
rejects pending writes; cached snapshots cannot create events. Deterministic UID/order/Ready-timestamp event
identities suppress repeats. First confirmed snapshots and first-seen Ready orders populate the center without
inventing a new transition. Observed foreground Pending/Preparing → Ready changes show actual stall/ticket
alerts. Background/resume rebaselines without replay. Student Profile has an unread indicator and Notifications
entry; the center has Ready/History, actual current status, timestamps, Viewed state, retry and shared Details.
Ready → Completed preserves event/read state. Existing five-tab navigation remains intact. UID-scoped transient
message state, controller disposal and generation/session guards prevent previous-account alerts/routes leaking.

Viewed/announced flags are **in-memory session state**, not durable or cross-device receipts. Existing Ready
orders can be unread again after restart/logout, without a popup. Fresh offline sessions await server confirmation;
only already confirmed records in a running session remain as clearly stale information. Alerts are best-effort
in-app events, not OS push or guaranteed background delivery. No FCM, notification permissions, Cloud Functions,
paid services, new dependencies, real payments or production deployment.

Rules, existing Firebase services/transactions, Vendor FCFS, queue/ETA formulas, limits, security gates, assets,
launcher and accepted layouts are unchanged. All previously passing Flutter/security test source files are
preserved byte-for-byte. Production checkout and both Vendor deletion gates remain disabled.

Cloud actually executed: existing launcher/budget-detector/offline-transport Node checks **11/11 passed** with
approved local process/socket permissions; `git diff --check`; protected-source audit (244 unchanged tracked
files); lexical Dart delimiter check. The lexical check is not analysis/compilation. New tests: **20 controller +
15 widget cases**, written but **unexecuted**. Flutter/Dart, Firebase CLI/dependencies and Android are unavailable;
no `flutter analyze`, Flutter tests, Firebase suite, Android acceptance or rendered screenshot comparison was run.
No new Rules-budget result or historical Chrome/Dart integration pass is claimed. SDK/dependencies were not upgraded.

See [Stage 3C Windows and two-client Pixel 6 guide](stage_3c_ready_notifications.md) for the exact changed files,
Windows Flutter/security commands, duplicate/read-state design and limitations. The foreground notification
scenario requires Pixel 6 Student plus another simultaneously signed-in Vendor client on the same local demo.
Do not log Student out to process the order and expect a foreground transition popup on reopening. Verify
Vendor Open Stall → two Student tickets → earliest Preparing → Ready alert/Details → Completed/History,
then account isolation, initial snapshots, offline/cache, duplicates and enlarged text.

Candidate awaits local Windows/Android review. Stop after Stage 3C; no unrelated feature, production activation,
deployment or additional service work is part of this authorization.

## Real Firebase ordering pilot preparation — 26 October 2026

Verified GitHub base `017fd9fe78a0e6116544c4246cf52eb959280218` on Stage 3C, including all four
locally repaired files. New branch `feature/real-firebase-apk-pilot`; final delivery identifies remote SHA.
Prior user Windows evidence: 169 Flutter and 104 security cases passed, zero budget diagnostics.
Real Auth/menu/browsing and deployed closed checkout Rules are user-reported current state.

Prepared an explicit Android-only normal-entrypoint pilot wrapper requiring BOTH build defines and actual
Auth/Firestore default-app project fyp-app-9d78a with canonical TLS endpoint. Normal builds stay disabled;
existing Firebase transaction classes and all emulator entry/configuration remain unchanged. Added a
separate reviewable Rules candidate and only-rules config; automated comparison proves the ONLY Rules
change is checkout false→true, retaining menu deletion false and all ownership/snapshot/counter/FCFS guards.
Generator accepts only the exact project and never deploys. App flags are not server authorization:
opening the candidate authorizes secure checkout for all otherwise eligible project users, not an allowlist.

Cloud executed 16/16 Node checks, whitespace and protected-source/lexical checks. Four Flutter policy/controller
integration tests are written but unexecuted. Flutter analyze/tests, Firebase emulator evaluation/budget suite,
Android/release APK/sign/install and live pilot acceptance were not run: tooling unavailable. No new 169/104
candidate pass or zero-budget claim. Existing test sources, default Rules, limits, queue/ETA/Ready logic,
package/config/assets/signing, deletion gates and local demo launcher preserved. No live Firebase access,
deployment, data changes, APK build/publication, paid service, credentials or signing keys added.

See [real Firebase pilot + Windows CMD APK guide](real_firebase_apk_pilot.md) for source boundaries,
activation, full local security verification, actual deployed-Rules backup, explicit-project manual Rules
deploy/Console verification and rollback, two-client Pixel 6 acceptance and private debug-signed release APK
build/install/hash checks. Local Rules and Flutter tests plus manual review are required before any deployment.
Stop at preparation; live activation and APK acceptance remain manual and unverified.

## Stage 4B public queue count — 29 October 2026

Verified base: `68d15b6d3d366ad102e8dc274f639cc97019d5f9`, latest pilot branch including Stage 4A Food Delete
preparation and Student Orders fixes. Candidate: `feature/stage-4b-public-queue-count`; delivery gives exact
verified GitHub SHA. All previously existing Flutter/security test files remain unchanged.

Implemented only Student Home Orders in queue. Sanitized `stallQueueCounts/{vendorUid}` stores exactly
schemaVersion, vendorUid, lastTicket, nextTicket, preparing, count and updatedAt. Count is L−N+1+(preparing?1:0):
checkout +1, Start unchanged, Ready −1 once, Completed unchanged. No identities/order IDs/snapshots in public
projection and no Home ETA. Missing/cached/malformed/denied/pending/unverified data shows Queue unavailable.

Stage 4B opt-in clients read that public allocation source instead of private checkoutCounters, then atomically
write the original private counter/order/request plus count. Vendor FCFS writes cursor/progress/order/count
atomically. Separate candidate Rules require both reciprocal links and independently verify the complete mirror
against canonical post-transaction sources. Student gets also check current source agreement to reject stale
mirrors; private counter get is owner-Vendor only and listing denied. Existing queue/ETA calculations unchanged.
Guarded same-ID and contention recovery retain original transaction semantics; no blind authorization retries.

Owning Vendor Orders initialization/repair verifies counter, cursor, last-order and Preparing-order boundaries
inside a server transaction. Missing summary never means zero. Both authoritative sources absent under accepted
no-delete invariants can prove the initial zero; malformed authority fails closed. No order scan, source reset,
ID migration or live backfill. This is not recovery from arbitrary privileged Admin corruption.

Existing conservative/default/ordering/Stage 4A deletion Rules/configs/launchers and deletion-disabled defaults
are unchanged. New Stage 4B closed and ordering candidates/configs are review artifacts, generated reproducibly.
Explicit STAGE4B_QUEUE_COUNTS build flag defaults false and requires existing ordering eligibility. Old live pilot
behavior remains as-is; its counter-read concern is not fixed until later approved Stage 4B activation. New and
old client/Rules modes must not be mixed. Food/Category Delete remains closed in both Stage 4B candidates.

Cloud final emulator suite: **149/149 passed (105 existing registered emulator cases + 44 new Stage 4B), zero
Rules-budget diagnostics**, child exit zero and log evidence. Prior user report was 111 security tests; actual
runner counts are recorded separately from Node unit checks rather than assuming that number was executed.
All old security sources are preserved, including Stage 4A. Additional Node unit/generator/launcher/transport
checks: **21/21 passed**. Initial fixture API failures were corrected; no validation was removed. Integer/double
Rules equality has explicit type guards and an adversarial emulator fixture. Exact per-request expression/access
counts are not inferred from coverage; budget guard scans every negative/positive run and debug logs.

Flutter/Dart and Android are unavailable: analyze, Flutter tests, compilation and manual Android acceptance
were **not run**. Ten new model/default-gate/widget tests are written but unexecuted; existing 176 Flutter sources
preserved. Source scope, lexical delimiters and whitespace checked. Existing locked Node dependencies and local
Firestore emulator installed for tests; no new project dependency, live Firebase access, migration, deployment,
billing change, merge or APK build/publication.

See [Stage 4B schema, security proof, bootstrap plan and Windows CMD guide](stage_4b_public_queue_count.md).
Run the complete new demo-only runner and Windows Flutter/Pixel 6 checks before considering any later activation.
Stop after this feature. Home ETA, Category Delete, four-food checkout, parallel preparation and background
notifications remain outside scope.
