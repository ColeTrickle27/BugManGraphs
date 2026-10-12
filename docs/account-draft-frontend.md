# Disabled account graph drafts frontend

This branch adds a fixture-testable client, account-scoped recovery journal, debounced sync controller, account gallery, active-creator picker and canvas status panel. It is stacked on PR17. PR17/18 are not changed by this branch. No production migration, authentication, credentials, API proxy, CORS, activation or deployment change is supplied.

## Activation remains off

`accountGraphDraftsActivated` is a literal false. `createProductionGraphDraftWorkspace()` returns null while off and refuses activation without a verified host binding. The app's normal HomeScreen has no workspace, creates no account database and makes no draft API requests. An explicitly injected fixture workspace can exercise the new UI. Do not add a URL/query toggle or infer ownership from username, employee author ID, graph metadata or a selected creator.

Contract baseline: OpsBrain PR100, head `fdf142cb9447ae926f266c57abcd944d134dd399`, `docs/graph-drafts-api.md`. Backend deployment and account migration remain independently blocked pending approval.

Before live activation, require a verified immutable credential accountId projection and a same-origin session/login/logout flow. Standalone Graphs does not inherit an OpsBrain-host cookie. Review host-cookie/signing/CSRF behavior and account-switch handling. A further binding question is pending: new-draft requests with expectedRevision null need an authenticated account-scope precondition (or an equivalent verified mechanism) so a changed cookie cannot associate an old account's queued package with a new account. A client-side UUID alone is not authentication. No live production service is created here.

## Data and state

- Complete version1 `.bgraph` packages retain document/unknown fields, full photo bytes and thumbnails. Missing data blocks upload; partial local recovery retains the drawing and available bytes and reports the problem. Explicit recovery download includes available data and never claims missing photos are complete.
- Request size includes UTF8 JSON and leaves64KiB below the25MiB backend limit for envelope overhead.413 preserves the complete local package; no data is trimmed.
- The new IndexedDB database `bugman-account-graph-drafts` has recovery and small summary stores. Keys are immutable accountId/graphId. A full recovery and its summary commit together. Legacy `bugman-graphs` documents/photo-blobs are never automatically read or adopted. Import requires an explicit copy action and keeps the original unchanged.
- Local persistence, pending cloud changes and manual Customer Files publication are separate. Portal keys remain local recovery metadata. `GraphDocument.markClean()` does not acknowledge cloud sync.
- Pending edits are snapshotted before async work. Large immutable photo buffers are copied when their reference changes, not on every drag notification. Journal writes and acknowledgment metadata updates serialize; old acknowledgments cannot clear newer edits or a newer creator choice. Updated server revisions feed the next queued write.
- Offline/auth/validation/size/conflict failures retain recovery. Conflict retains both complete local and remote copies; Keep both creates a new draft identity and never overwrites the existing cloud object. No delete API/action is invented.
- Gallery follows every opaque cursor, deduplicates IDs and sorts by timestamp after traversal; R2 key order is not presented as recency. Cached recoveries stay scoped when accounts switch or usernames are recreated.
- Creator choices use only the minimal active ID/name directory. Default is the signed-in employee from the API. Historical inactive snapshots stay visible and disabled; unchanged attribution is omitted on ordinary updates. Creator changes never change local owner scope or assign server ownership.

## Verification and remaining limits

Tests use MockClient/fixture services and synthetic account UUIDs/customer data. The production activation gate is asserted. Real-device native sharing, live host identity/cookie routing, atomic account-scope binding and production backend behavior are not asserted by these fixtures. Local fixture browser QA must never use customer production accounts or objects.
