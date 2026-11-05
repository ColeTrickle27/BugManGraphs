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

Eleven added Flutter unit/widget cases pass. They cover GET-only pagination,
opaque cursor encoding, empty pages, malformed responses, 401/403 distinctions,
mid-pagination access expiry clearing, duplicate results, repeated cursor
cycles, stale service responses, read-only preview, same-ID local preservation,
old flat documents, geometry/calibration, unknown fields, package photo bytes
and rejection of document/photo/delete/portal writes.

Flutter stable 3.47.9 / Dart 3.13.7 was downloaded from the official manifest
at `https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json`.
SDK archive SHA256 matched
`25ed8c3c29d51a7353f2a944310b478af8214920639524b19c50a19e6c044c5a`.
Earlier not-found responses were caused by an incorrect extra `/flutter/`
segment in the URL, not unavailable official downloads.
Tool configuration, pub cache and analyzer state use temporary directories.
The Dart hook compiler needed a narrowly approved writable local `.dart-tool`
cache. HOME and application configuration were not repurposed.

Analysis is clean; the full 374-test Flutter suite and release web build pass.
These checks are repeated after the final opt-in viewport correction below.
SDK-generated analysis options/lockfile changes are excluded from the patch.

Separately, four Node synthetic checks passed against the exact deployed
OpsBrain history/load function source in a sandbox with mocked storage and
helper boundaries. They exercised 207 unique graphs across three pages,
ledger/receipt duplicates, excluded non-graph keys, invalid cursor rejection,
historic flat-package/photo preservation, disallowed package roots and no
storage writes. Authentication/CORS ordering was checked statically. These
checks do not execute Flutter, the frontend HTTP service, real authentication,
or a real R2 binding and must not be presented as full app validation.

`git diff --check` passed. Validation commands:

```sh
flutter pub get
flutter analyze
flutter test
flutter build web --release
```

Local Chromium fixtures exercise desktop1440x1000 and mobile390x844 history,
empty first page, finalized status, exact source-key GET, preview, same-ID
IndexedDB preservation and mid-pagination401 clearing. Each uses three history
GETs and one package GET, with zero writes. Screenshots are synthetic only.
Manual source inspection and screenshot review found that the existing
presentation canvas centers the3600x2600 canvas rather than off-center graph
content. An opt-in `presentationFitToContent` flag now uses the existing
ExportBoundsCalculator and EditorViewport.fit; it changes screen magnification
only. The history preview enables it. A widget assertion verifies centered
geometry without changing wall coordinates. All other callers default false.

Real authenticated production browser behavior, actual historical package
photo/marker rendering and the user's affected local browser remain unverified.
Do not test with production writes or clear browser storage.

The active expandable-action-card branch also changes graph_canvas_screen.dart.
This patch adds only the opt-in constructor flag and initial viewport-fit block;
normal editor interactions are unchanged. A local merge-tree check assesses
integration without changing that branch. Separate file-manager work is untouched. No merge, push or deployment is authorized.
