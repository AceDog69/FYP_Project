# Smart Canteen development progress

Updated 21 October 2026 (Asia/Singapore). Supervisor meeting: 28 October 2026.

## Milestones and source

| Milestone | Commit / state |
| --- | --- |
| Approved Stage 1 baseline | `d7741277fe0918c1463449b0d0f5bb178ca01fef` |
| Stage 2A-01 Dashboard source | `fb9760731474fe80257c8d753b6e6f90d03330bb` |
| Latest Stage 2A-01 fixes, verified through GitHub before editing | `01b08d15ab2bc48d87caa497c0c54fbdc35b80d8` |
| Stage 2A-02 implementation | Source commit will be recorded after the implementation snapshot is committed. |

Stage 2A-01 was verified by the user on a Windows Pixel 6 Android emulator:
analysis passed, 23 combined Flutter tests passed, and Dashboard navigation,
real stall display, Profile and Logout were manually verified. Those are the
user's reported results for Stage 2A-01, not results for the new code below.

Stage 2A-02 branch: `feature/stage-2a-02-vendor-operations`. The exact latest
Stage 2A-01 commit and its tree were imported through the connected GitHub
integration because shell Git transport could not reach its proxy. The verified
Material widget and test-visibility fixes are retained. No missing old Stage 2A
commit was reconstructed and no development was based on Stage 1 alone.

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
