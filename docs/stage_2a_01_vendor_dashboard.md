# Stage 2A-01 — read-only Vendor Dashboard

Branch: `feature/stage-2a-01-vendor-dashboard`.
Baseline: `d7741277fe0918c1463449b0d0f5bb178ca01fef`, independently verified
against the connected GitHub `main` endpoint before creating this branch.
The missing previous Stage 2A commit was not used or reconstructed.

## Implementation

The Vendor Dashboard now listens to exactly `stalls/{authenticatedVendorUid}`.
It displays the existing `name`, `category`, `status` and `preparationMinutes`
fields. The decoder checks ownership and field types; legacy category strings
remain readable. It requires no new fields, image IDs or data migration.

The screen follows the supplied V2-01 orange `#FF7A00` header, rounded stall card
and quick-action layout. Both the V2-01 PNG and Full Design & Decision Handover
were accessible and inspected. Stall pictures are outside this increment.
Order information is labeled unavailable rather than populated with sample counts.

Loading, missing/malformed data, stream errors, Retry and cached-data labeling are
included. Errors hide previously retained stall data. Open Stall / Close Stall
have a null callback, disabled styling and an explicit Stage 2A-02 explanation.
There is no new Firestore write operation. Quick actions select the existing
Orders/Menu tabs; those screens retain their Stage 1 placeholders.

Vendor's four tabs, Student's five tabs, Profile/Logout, authentication and original
Vendor Stall Setup are preserved. Firestore rules, schema, dependencies, lockfiles,
Firebase configuration and normal app entry point are unchanged. No production
Firebase data or rules were modified. No menu, food CRUD, ordering, queue, ETA,
notification or profile-refresh implementation is included.

## Changed files

- `lib/models/vendor_stall.dart`: validated read-only model of existing fields.
- `lib/screens/vendor_dashboard.dart`: dashboard presentation and listener state.
- `lib/screens/home_screen.dart`: replace only Vendor's Dashboard placeholder.
- `lib/services/auth_repository.dart`: own-stall read-stream interface.
- `lib/services/firebase_auth_repository.dart`: authenticated UID document listener.
- `test/vendor_dashboard_test.dart`: model, loading/error/retry/cache/live updates,
  disabled status controls, navigation/logout and Student isolation tests.
- `test/stage_one_test.dart`: synthetic stall stream and updated dashboard title
  assertions; existing registration/setup/auth/navigation assertions retained.
- `test/stall_category_test.dart`: update destination title assertions only.
- `test/firebase_repository_browser_test.dart`: assert the real Dart listener
  reads the existing own-stall fields without changing the document.
- This handover.

## Actual checks

| Command | Result in this environment |
| --- | --- |
| `flutter analyze` | Not executed: missing Dart SDK; bootstrap cannot connect to proxy port 8080; exit 7 |
| `flutter test test/vendor_dashboard_test.dart test/stage_one_test.dart test/stall_category_test.dart` | Not executed: same bootstrap/proxy failure; exit 7 |
| `npm test` in `test/firebase` | Tests did not start: `firebase: not found`; exit 127 |
| `npm run test:dart` in `test/firebase` | Tests did not start: `firebase: not found`; exit 127 |
| `git diff --check` | Passed |
| `node --check test/firebase/stage_one.test.mjs` | Passed syntax only |
| Diff of rules/config/dependencies/Stall Setup/main entry | No changes |

The source was **not compiled, Android-tested or visually rendered** here. The
new tests have not passed yet. Historical Stage 1 test results do not validate
this increment. Shell Git access also encounters the unreachable proxy; the final
chat report records the push attempt and connected-GitHub backup result.

## Windows / Android Studio

Fetch the backed-up feature branch and open this Flutter project in Android Studio:

```powershell
git fetch origin
git switch --track origin/feature/stage-2a-01-vendor-dashboard
flutter pub get --enforce-lockfile
flutter analyze
flutter test test/vendor_dashboard_test.dart test/stage_one_test.dart test/stall_category_test.dart
```

If the local branch already exists, switch to it without `--track` and inspect
its commit before running. Use the existing Flutter 3.44.4 / Dart 3.12.2 setup,
Android SDK 36 and compatible JDK from the Stage 1 README. Start an Android
emulator in Android Studio, then:

```powershell
flutter devices
flutter run --debug -d <android-emulator-id>
```

Use the unchanged Stage 1 Firebase configuration and sign in as an **existing
configured Vendor**. Check actual stall name/category, Open/Closed status and
initial preparation time. Open/Close must remain disabled. Check all four tabs
and Profile logout. The app's normal entry point connects to the existing Firebase
project; signing in to view this dashboard requires no stall writes or rule deploy.
Registration or Stall Setup retains its existing Stage 1 write behavior.

For local synthetic Firebase regression/integration testing, install Node 24,
Java 21 and Chrome, then run sequentially:

```powershell
Push-Location test/firebase
npm ci
npm test
npm run test:dart
Pop-Location
```

These scripts start demo emulators and do not deploy rules. Check loading/failure
and reconnect behavior on Android as well; a cached snapshot is explicitly labeled.
No Android acceptance or live Firebase validation is claimed by this handover.

Review this single increment before Stage 2A-02. Do not merge, deploy or start
another feature as part of this task.
