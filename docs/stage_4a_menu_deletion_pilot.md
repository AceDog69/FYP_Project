# Stage 4A menu deletion pilot

Food deletion remains disabled in the default Rules and the existing ordering pilot. The separate `firebase.menu-deletion.pilot.json` selects a candidate differing from `pilot/firestore.ordering.rules` only by opening the paired food/membership deletion gate. Its tests verify that equivalence; it has not been deployed.

The app also defaults deletion off. Enable `REAL_MENU_DELETION_RULES_ACTIVE=true` only in a build that already passes the existing real-ordering project, Auth, Android, app-name, TLS and endpoint checks, and only after the matching candidate has been reviewed and deliberately deployed to `fyp-app-9d78a`. This build define is an operator attestation, not runtime proof of deployed Rules. If Rules are not active, Firestore rejects the operation and the UI reports the failure; no success is shown before server acknowledgement.

Category deletion remains disabled. Current Rules cannot prove absence of arbitrary `menuMemberships` documents. A future safe implementation needs a category membership count/revision maintained atomically and enforced for every food create, move and delete, followed by an emulator-tested migration or fail-closed handling for existing categories without that invariant. A client query alone is not sufficient.

Food deletion only deletes a verified food and its matching membership in one transaction. It does not touch order documents. Students' existing Cart and checkout validation already reject missing/unavailable foods.
