# Smart Canteen — Stage 1

Android-first Flutter authentication for **A Real-Time Smart Queue and Order Notification System for University Canteens**. Uses Firebase Authentication and Cloud Firestore; there are no hard-coded accounts or simulated production sign-ins.

## Implemented

- Separate Login, Registration, Forgot Password, and Reset Email Sent screens based on the five supplied references. Orange `#FF7A00`, bundled Inter font, larger Login branding, safe areas, scrolling forms and password visibility toggles.
- Real email/password registration and login. Inline validation, friendly errors, loading states and disabled duplicate submissions.
- Profiles at `users/{Firebase UID}` with UID, full name, email, phone, role, creation timestamp, stall setup status and association.
- Authentication gate restores the Firebase session, verifies the profile from the server, and routes without temporarily showing the wrong home. Missing profiles require completion; invalid/inaccessible profiles offer Retry/Logout.
- Student: Home, Orders, Cart, Queue, Profile. Vendor: Dashboard, Orders, Menu, Profile. Non-Stage-1 tabs display **Coming soon**. Both profiles show account details and Logout. Logout removes the authenticated navigation tree.
- New vendors must finish Stall Setup before Dashboard. A Firestore transaction creates `stalls/{vendor UID}` and updates the profile together. One stable, unique stall per vendor; new stalls are `closed`. Setup failure leaves the vendor on setup.
- If Auth registration succeeds but profile saving fails, the service preserves the identity, signs out and explains recovery. The next login verifies whether the profile exists and offers completion when missing. It never overwrites an existing role or claims partial registration is complete.

## Firebase setup to complete manually

The existing `android/app/google-services.json` is preserved. It names project **fyp-app-9d78a** and package **com.example.my_fyp_app**, matching the Android application ID. No production API keys or Firebase options were invented.

1. In Firebase Console for that project, enable **Authentication → Sign-in method → Email/Password**. Enable email enumeration protection if it is not already enabled.
2. Create the default **Cloud Firestore** database if necessary. Use the supplied rules rather than open test-mode rules.
3. Review `firestore.rules`, then deploy them using an account authorized for your project:

   ```bash
   firebase login
   firebase deploy --only firestore:rules --project fyp-app-9d78a
   ```

   Alternatively paste the contents into Firestore's Rules editor and publish. Rules allow only each authenticated user to create/read their own profile, keep UID/email/role/creation time immutable, and enforce atomic vendor stall ownership and association. Profile deletion and other collections are denied in Stage 1.
4. Review the password-reset email template and sender settings in Authentication. Test receipt in an actual mailbox (including spam). The confirmation message intentionally does not reveal whether the email exists.

Native Android Firebase initialization uses the Google Services Gradle plugin. No `firebase_options.dart` is needed for this Android workflow. Live web/iOS support is not configured; use FlutterFire CLI with your actual project if you later target those platforms. The browser integration tests use **local demo emulators only**, not live web configuration.

## Run on Android

Use Flutter **3.44.4 / Dart 3.12.2**, Android SDK platform 36, and a compatible JDK (21 was used in cloud validation). Enable USB debugging on an Android phone or start an Android emulator in Android Studio.

```bash
cd FYP_Project
flutter pub get --enforce-lockfile
flutter devices
flutter run -d <android-device-id>
```

For an ARM64 debug APK:

```bash
flutter build apk --debug --target-platform android-arm64
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`. Use a normal Android device to verify actual Firebase connection, email delivery and native session restoration. The cloud has no connected Android device.

## Checks

```bash
flutter analyze
flutter test test/stage_one_test.dart
```

The Flutter UI/unit suite uses an explicit test repository. It exercises validation, password visibility, pending Login requests, Student and Vendor registration/routing, exact tab counts, tab switching, logout/back navigation, reset confirmation, restored sessions, profile recovery and small keyboard-open layouts. It is not evidence of live Firebase success.

Firebase rules and Auth integration tests run against local demo emulators (Node 24 and Java 21):

```bash
cd test/firebase
npm ci
npm test
```

The suite rejects unauthenticated access, role/UID/email changes, cross-user access, invalid stall writes and incomplete associations, and exercises real emulator registration/login/reset/logout and atomic vendor setup. It never deploys or writes to the production project.

To exercise the actual Dart Firebase repository with its web plugins:

```bash
cd test/firebase
npm run test:dart
```

This command starts local emulators, bundles the matching official Firebase JS SDK locally, serves it on loopback port 9190, and runs Flutter's Chrome test runner. This avoids a Firebase CDN dependency. Stop previously running emulators before running either npm script. Chrome must be installed; set `CHROME_EXECUTABLE` if it is not on the default path.

These tests cover Student/Vendor service operations, idempotent stall setup, restoration from an existing Auth session and recovery from a real rules-rejected profile write. They require Chrome; normal `flutter test` skips this browser-only file.

## Supervisor demonstration checklist (live Android)

Cloud validation on 11 October 2026: Flutter 3.44.4 and Dart 3.12.2 verified; `flutter analyze` passed; all 12 Flutter unit/widget tests, 11 Firebase rules/Auth emulator tests, and 3 tests of the actual Dart Firebase repository passed. Both documented npm scripts passed with fresh emulator startup/shutdown. The final ARM64 debug APK built successfully. The six rendered reference-based screens were visually checked. The existing Google Services configuration was unchanged.

Live Firebase Console settings, production rule deployment, actual email delivery, and force-close/relaunch persistence on an Android device have **not** been verified. The build emits existing Kotlin Gradle Plugin migration warnings, but completes with the pinned Flutter version.

- Register a Student, logout/login, switch all five tabs and logout again. Press Back; authenticated screens must stay inaccessible.
- Register a Vendor, complete Stall Setup, verify four tabs and no Cart/Queue. Logout/login; setup must not repeat. Check the new stall is Closed in Firestore.
- Try incorrect credentials, empty fields, invalid email/phone, weak/mismatched passwords and invalid preparation minutes.
- Send a reset request, confirm the separate email screen and verify mailbox receipt and actual password reset.
- Force-close/relaunch while signed in: check the correct role home returns. Do the same for an unconfigured vendor: Stall Setup must return.
- Disconnect network during setup or deny profile writes in a development project: no false-success dashboard; recover via login/profile completion.

Ordering, payment, real queues, menu editing and notifications are deliberately unfinished for Stage 1. A vendor's stall cannot be opened or edited yet. See the delivery report for the commands actually run and any build/environment blockers.
