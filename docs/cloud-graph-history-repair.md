# Cloud graph history discovery (local review candidate)

The released Home screen lists only this browser origin's IndexedDB graphs.
Historical shared packages still exist in OpsBrain, but this Home screen does
not discover them. This change adds an explicit Cloud graph history button;
it does not establish the cause of Cole's missing local-history report.

The history screen calls the existing authenticated GET
`/api/bugman-graphs/recent`, follows opaque cursors on explicit Load more,
continues through empty pages, deduplicates by storage key and displays
finalized status. It uses the existing shared Customer Files authorization,
not account-draft ownership. No API, permission, ownership or storage format
changes are required. The factory uses the existing trusted standalone hosts
and the current origin when mounted under `/bugman-graphs/`.

Opening a result calls the existing portal GET load method and renders the
existing complete-package presentation view with package-owned photo bytes.
Its repository rejects save and delete, and its portal service is disabled.
It never calls the `?graph=` app-entry
path, saves into IndexedDB, imports a graph, or publishes a package. A matching
document ID in local storage is therefore untouched. There is no edit/copy
action in this view; finalized source packages remain immutable.

Authentication errors clear displayed cloud metadata and offer separate-tab
OpsBrain sign-in. Authorization errors clear metadata and report denied
access. Other failures are visible and retryable; they are not represented as
an empty successful history. Pagination loops are rejected. The existing
local list and local error handling are unchanged.

## Confirmed deployed contract

Read-only Cloudflare API metadata identifies OpsBrain production deployment
`85f55910-8d3a-410c-854b-b8192d71737a`, source main commit
`87a9639eec5013fa15c55d061175df4588110fd7`, created November 3, 2026 at
13:04:35.376 UTC, deployment succeeded at 13:05:15.554 UTC. That source contains
the recent-history route, customer-specific `/list` route and package `/load`
route. `requireUser` runs before history dispatch; existing trusted-origin
credentialed CORS applies. No backend source is copied into this app.

## Validation status

Added Flutter fixtures cover GET-only pagination, opaque cursor encoding,
empty pages, malformed responses, 401/403 distinctions, duplicate results,
read-only preview, same-ID local preservation, old flat documents, geometry,
unknown fields and package photo-byte access. **These tests have not run.**
Flutter/Dart SDK is absent. Official Flutter SDK release-index and archive
requests returned HTTP 404 in this environment. No third-party SDK was used.

Separately, four Node synthetic checks passed against the exact deployed
OpsBrain history/load function source in a sandbox with mocked storage and
helper boundaries. They exercised 207 unique graphs across three pages,
ledger/receipt duplicates, excluded non-graph keys, invalid cursor rejection,
historic flat-package/photo preservation, disallowed package roots and no
storage writes. Authentication/CORS ordering was checked statically. These
checks do not execute Flutter, the frontend HTTP service, real authentication,
or a real R2 binding and must not be presented as full app validation.

`git diff --check` passed. Before approval for release, run:

```sh
flutter pub get
flutter analyze
flutter test
flutter build web --release
```

Manually verify desktop/mobile history navigation, empty paginated pages,
separate-tab sign-in recovery, finalized package preview, visible photo/marker
rendering, same-ID local history preservation and access failure behavior.
Do not test with production writes or clear browser storage.

The active expandable-action-card branch changes the editor and has no changed
files in common with this patch. This branch does not alter the canvas editor
or the separate file-manager work. No merge, push or deployment is authorized.
