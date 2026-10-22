# Smart Canteen development progress

Updated 22 October 2026 (Asia/Singapore). Supervisor meeting: 28 October 2026.

**Latest state:** the finalization section at the end supersedes the historical
checkpoint limitations/results below. Both destructive actions remain gated.

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
