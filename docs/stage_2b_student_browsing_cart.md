# Stage 2B — Student browsing and unpaid Cart

Required base: `ba7edcf7661c62f7771ecae37b3cf57a17355bd0`, verified on GitHub
before editing. Branch: `feature/stage-2b-student-browsing-cart`. The Student Home
and catalog-security intermediate backup was verified at
`6bc6af9331c678f3c79d184b2deb17ea092b0f56` before Stall Menu/Cart work continued.

The user reported no analyzer issues, 38/38 Flutter tests, 38/38 combined security
tests and earlier Vendor Menu Pixel 6 acceptance at the base. These historical
results do not validate the new implementation. No rules have been deployed.

## Implemented behavior

Student Home watches real public listings, searches **stall names only** without
case sensitivity, clears search, filters by All/seven fixed stall categories and
shows picture/name/category/Open/Closed/preparation time. Loading, no listings,
no matches, cached data, errors and Retry are distinct states. Closed stalls
remain browsable. Stall Menu watches the selected stall, its Vendor-created menu
categories and available foods; it filters by category and shows descriptions,
existing pictures and exact RM prices. Cached and Closed menus cannot add new
selections. Availability changes remove food from the selectable query results.

Food selection has bounded quantity controls and integer-sen subtotals. Add to
Cart performs server-only reads of listing, food and category, checks the displayed
food revision, and refuses an outdated or unavailable selection. Switching stalls
requires confirmation before any old selections are discarded. Cancel and failed
server checks preserve the existing cart. The controller independently enforces
one stall and validates limits before replacement. Repeated submissions are blocked.

The Cart displays name/picture/unit price/quantity/item subtotal/total, supports
increase/decrease, confirmed removal, confirmed Clear, empty state and return to
browsing. Checkout is a **disabled** button labeled available in Stage 2C. Quantities
range from **1 to 20 per item**, with **at most four distinct food IDs** from one
stall. Additional quantity does not count as a new product; at one unit, use Remove
instead of decrementing to zero. All money arithmetic uses integer sen and the
existing `rm()` formatter, never floating-point prices.

The Cart is local memory, owned by the authenticated Home/session tree, and
survives tab/detail navigation. It intentionally does not survive process restart
or logout. A UID-scoped authenticated Navigator disposes detail routes and Student
dialogs on logout/account switch as well as the Cart. No Firestore Cart, order,
checkout or ticket writes are introduced. Vendor four-tab and Student five-tab
navigation remain exact; Orders/Queue are placeholders and Student Profile's
layout/fields are unchanged.

Cart listeners follow listing, categories and available foods. Cached/error/missing
data warns that selections are unverified; increases are blocked until current.
Unavailable food is flagged for removal. Closed stalls are flagged. Changed food
revision (including price/name/category) keeps the old display snapshot and total
until the Student confirms Review Changes; applying it performs another server
check and rejects another revision change. Decrease, removal and Clear remain safe
local actions. Refresh restarts the listeners. Category renames retain their stable
IDs; food reassignment changes the food revision and requires review.

These checks concern an **unpaid display cart**. Server reads are not an atomic
checkout and can become stale immediately afterward. They never guarantee a valid
future order. Stage 2C must atomically re-read canonical stall status and authoritative
food/category/membership, validate availability, owning stall, quantities, four
distinct products, integer prices/totals and immutable order snapshots. Checkout,
payments, order creation and queue/tickets are not implemented here.

## Public listing and security design

Raw `stalls/{uid}` can contain protected legacy fields, so Student reads of those
documents and all other users' profiles remain denied. A new minimal projection
`publicStalls/{vendorUid}` contains only:

| Field | Meaning |
| --- | --- |
| `vendorUid` | Stable stall/owner ID, equal to document ID |
| `name`, `category` | Canonical stall name and one of the existing seven categories |
| `status` | Canonical `open` / `closed` |
| `preparationMinutes` | Canonical integer, 1–180 |
| `pictureId` | Optional canonical ID from the existing 23-picture allowlist |
| `updatedAt` | Server timestamp equal to the publishing request time |

Only the configured owning Vendor may create/update a listing. Exact-key validation
rejects contacts, arbitrary legacy fields, owner substitution and extra metadata.
All display fields must match the **after-state of the canonical stall**. A client
cannot invent another Vendor's listing or publish false data independently of its
stall. Listing deletion is denied. No anonymous read access is added; registered
Students can list/read listings, and Vendors can read their own listing.

Once a listing exists, stall updates must include a matching listing update in
the same atomic request. The normal status/settings transaction now writes both.
Old standalone writes after publication fail rather than leave misleading public
status. Source ownership, creation timestamps and protected fields retain their
existing restrictions. This compatibility change matters for old app builds:
use this branch's client with these proposed rules in local tests.

Existing configured Vendors publish idempotently when they visit a server-confirmed
Dashboard, or change status/settings using this client. Publication selects an
explicit field allowlist from a fresh owner transaction; no bulk migration or
Student backfill privileges. **A Vendor who has not revisited the app does not yet
appear in Student search.** Bootstrap publication failure does not break existing
Dashboard reads; publication retries at a subsequent server snapshot/visit or a
status/settings save. Invalid legacy categories/picture IDs may need a valid owner
settings save before publication; no destructive repair is attempted.

Students read the original `menuCategories` and `menuFoods` under a listed stall;
there is no separate Student menu database. Those menu documents have the existing
strict field schemas. Memberships and category-name reservations stay Vendor-only.
Students may read **only foods with `available == true`**. Food collection queries
must include `.where('available', isEqualTo: true)`; unrestricted/unavailable queries
and direct reads of unavailable items are denied by rules, independent of UI filters.
No Student writes to stalls, listings or any menu collection are allowed.

No new collection-group query, composite index, dependency, Storage service,
Function or paid service is needed. Existing pictures, production Firebase config,
normal/debug entry points, Android debug HTTP permission and Windows launcher are
unchanged. The Vendor Food Delete and Category Delete gates remain closed in
both app and checked-in rules.

## Tests and actual execution

New Flutter coverage: 5 controller tests and 6 widget tests covering money/limits,
single-stall replacement, price/name/category review, unavailable/Closed/cache/error
states, session disposal, Home/search/categories/pictures, selection/quantity,
tab persistence, switch Cancel/Confirm, Remove/Clear Cancel/Confirm, live updates,
retry, account changes with an open dialog and Logout. Existing authentication
tests retain their assertions except Cart now expects the real empty Cart.
Vendor tests and delete gates are preserved.

Eight new emulator security tests cover allowed listing/category/available-food
reads, query constraints, private profile/source/internal denial, role/cross-Vendor
attacks, forged/leaking listings, atomic source/listing synchronization, owner-only
publication of existing stalls, availability revocation and both closed delete gates.
`npm run test:student` sequentially includes Stage 1, Vendor Operations, Vendor Menu
and Student Catalog modules (46 registered top-level cases, not observed passes).
The existing menu suite still tests a candidate Food Delete gate only in emulator
memory and separately proves the checked-in gate is closed; no gate is enabled.

Actual checks in this Codex session:

| Command/check | Result |
| --- | --- |
| Flutter toolchain inspection | Dart SDK absent; no working `dart` executable |
| Network probe | `Failed to connect to proxy port 8080`, exit 7 |
| `flutter analyze`, `flutter test` | Not run; missing SDK. No repeated SDK download attempted |
| `npm run test:student` | Runner stops: `firebase: not found`, exit 127 |
| `node --check` for all four security modules | Passed syntax only |
| `git diff --check` | Passed |
| Protected source/config/launcher/dependency/23 PNG comparisons versus base | Unchanged |

**Zero Flutter/security cases executed here.** New Dart code was not compiled or
Android-tested, and new rules were not emulator-compiled. No new functional/security
pass count, race proof or clean analyzer result is claimed. Static access review:
public writes need configured profile and canonical stall lookups; synchronized
stall/listing writes add listing-before/after checks. Student menu reads add profile
and listing-existence lookups. These are bounded, but document-access and expression
budgets remain unmeasured until emulator execution. Do not treat source inspection
or Node syntax validation as Security Rules proof.

Student S2-01/02/03 PNG references were absent in the provided ZIPs. The accessible
approved full written handover specifies the orange/white design, text-only fixed
stall/menu category chips, vertical stall cards, single-stall Cart and item totals;
that behavior was followed. No missing visual approval is invented. The existing
Chrome/Dart loading stall remains a gap, not a prerequisite for Android testing.

## Windows and Pixel 6 acceptance

Use the existing Flutter 3.44.4/Dart 3.12.2, Node/npm and Java from Android Studio.
From a clean working tree, fetch the branch. If it already exists locally, switch
to it and use `git pull --ff-only`; stop on divergence.

```powershell
git fetch origin
git switch --track origin/feature/stage-2b-student-browsing-cart
git rev-parse HEAD
flutter pub get --enforce-lockfile
flutter analyze
flutter test
Push-Location test/firebase
npm ci
npm run test:student
Pop-Location
```

Stop previous emulator processes before the security runner. It uses only the
local `demo-smart-canteen` project. Start local Firebase for manual testing in a
separate terminal at repository root:

```powershell
.\test\firebase\node_modules\.bin\firebase.cmd emulators:start --project demo-smart-canteen --only auth,firestore --config firebase.json
```

In another terminal, launch the Pixel 6 Android emulator and run:

```powershell
flutter devices
flutter run --debug -d <pixel-6-emulator-id> -t lib/main_emulator.dart --dart-define=EMULATOR_HOST=10.0.2.2
```

1. Create synthetic Vendors, complete unchanged Stall Setup, open Dashboard to
   publish each listing, create menu categories and at least five available foods
   plus an unavailable food. Open stalls; choose existing predefined pictures.
2. Sign in as a synthetic Student. Test stall-name search case sensitivity/clear,
   category chips, no matches, pictures, preparation time, menu category filters,
   empty menus and Closed browsing. Never list/select unavailable food.
3. Select quantity 2 at RM 8.50: subtotal RM 17.00. Add, open Cart, navigate all
   five tabs and return. Test quantities 1 and 20, reject 21, four distinct foods
   allowed and fifth rejected; more quantity of an existing food remains allowed
   within its limit. Check exact integer-sen totals with RM 9.05 / RM 0.01.
4. Select another Vendor: Cancel preserves the original Cart; Confirm replaces it
   only after successful server verification. Test server failure after confirmation
   and verify the original Cart survives. Test Remove and Clear Cancel/Confirm.
5. With Cart selections, change food price/name/category on Vendor. Old Cart totals
   remain, a review warning appears, Cancel keeps them and Apply Latest adopts the
   confirmed snapshot. Change again during review; it must ask to retry. Mark food
   unavailable or close the stall; increases must be blocked and warnings visible.
6. Disconnect local Firebase: confirm cache/error labeling, blocked selection and
   quantity increases, safe local removal, and Retry/Refresh after reconnection.
   Checkout must always remain disabled and create no Firestore Cart/order/ticket.
7. Logout with a populated Cart and sign in as another Student: empty Cart. Also
   simulate an account change while a menu/dialog is open; old routes must disappear.
   Regress registration/reset/setup, Vendor Dashboard/Open-Close/Profile/Settings,
   Vendor Menu/pictures/availability and both disabled deletes. Student Profile is
   unchanged; Orders/Queue remain placeholders.
8. Review the actual rules test results, including forged catalogs and raw-stall
   privacy. No production deployment or data migration is authorized by this batch.

Stage 2B is ready for local compile/security/Android acceptance, not declared
validated. Stage 2C should wait for those results and review of the catalog rules,
publication compatibility and Cart revalidation contract. No Stage 2C work is started.
