# Disabled account graph drafts frontend

This branch adds a fixture-testable client, account-scoped recovery journal, debounced sync controller, account gallery, active-creator picker and canvas status panel. It is stacked on PR17. PR17/18 are not changed by this branch. No production migration, authentication, credentials, API proxy, CORS, activation or deployment change is supplied.

## Activation remains off

`accountGraphDraftsActivated` is a literal false. `createProductionGraphDraftWorkspace()` returns null while off and refuses activation without a verified host binding. The app's normal HomeScreen has no workspace, creates no account database and makes no draft API requests. An explicitly injected fixture workspace can exercise the new UI. Do not add a URL/query toggle or infer ownership from username, employee author ID, graph metadata or a selected creator.

Contract baseline: OpsBrain PR100, head `1b8bff38b9a487b9b79e8fd6dc5e361e19a0d994`, `docs/graph-drafts-api.md`. Backend deployment and account migration remain independently blocked pending approval.

Before live activation, require a verified immutable credential accountId projection and a same-origin session/login/logout flow. Standalone Graphs does not inherit an OpsBrain-host cookie. Review host-cookie/signing/CSRF behavior and account-switch handling. The disabled bootstrap reads `GET /api/graph-drafts/context` and pins its server-derived `accountId` before creating a workspace. Every authors/list/load/save request sends `X-Graph-Expected-Account-Id`; the backend compares it against authenticated ownership before draft storage. A409 triggers a context check: a different account invalidates this client and asks for the original account instead of rebinding queued recovery. Existing recovery can require its original UUID during bootstrap. This precondition is not client authorization. The backend reports missing428 and malformed400; the client always supplies the validated pinned UUID. No live production service is created here.

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

Tests use MockClient/fixture services and synthetic account UUIDs/customer data. The production activation gate is asserted. Real-device native sharing, live host identity/cookie routing, production backend account-binding enforcement and behavior are not asserted by these fixtures. Local fixture browser QA must never use customer production accounts or objects.

## Review corrections

Clean sessions revalidate on reopen; pending local edits win even if created during a remote fetch. Each pushed copied-structure editor has its own repository/session. The route close guard waits for repository transitions and flushes/checks the active fork, including failed acknowledgment metadata persistence. A successful upload cannot be called locally durable until its revision/author metadata is stored; retry can persist it without uploading twice.

Closing before debounce flushes recovery and starts sync. Home drains the queue on refresh, app resume and a30second reconnect retry while displayed. Failed attempts retain recovery. Original409 conflicts survive unchanged canvas captures. Optional explicitly empty thumbnail references remain empty, while absent legacy references retain the migration fallback. Serializers retain nested customer, attachment and graphObjects fields; deleted objects stay deleted. Manual Customer Files publication is explicit and independent of cloud acknowledgment or the loaded document's clean flag. The read-only conflict preview includes annotations, treatment, freehand and full photo bytes with a Close action.

IndexedDB summaries are decoded during each cursor event rather than retaining live cursor objects until iteration ends. The injectable IndexedDB implementation is tested against the memory database client; browser QA additionally verifies actual IndexedDB navigation and refresh.

## Account access and complete recovery

Confirmed server-context mismatch invalidates and locks the gallery, active editor, sync sheet and remote preview. Cached rows disappear; workspace local listing/opening is denied until a fresh bootstrap verifies the original account. Stored recovery is retained under its original UUID. Ordinary offline/expired-auth errors do not invalidate that context and still permit local recovery. No production sign-in flow is added.

Layer, trace and calibration extensions survive serialization along with customer, attachment and geometry fields. Undo/Redo snapshots include serialization state so deleted id-less objects regain their own future fields when restored. Keep Both and Save As New preserve package extensions. The reserved draft identities include both authors and context.

A missing Customer Files graph triggers a new identity and awaits that identity's local session creation/durability before the replacement publication. Returned portal keys bind to the awaited new session, never the preceding session. The regression holds new local writes while the remote service is fast and verifies both keys independently.

Account draft cloud previews require an account parameter; the sync-panel route passes its owning session's account. Account-bound trace routes also lock on invalidation, cancel pending address lookups and reject stale trace results. Open-preview and open-trace regressions invalidate the account while each route is displayed.

Publication is serialized per editor. A second save or active-session switch is refused while a request is in flight. Each publication holds an immutable document snapshot and its exact editor session; responses update only that captured session. Edits made during the request remain dirty and keep their pending photo buffers. A held-response test attempts the second save, edits the graph, then verifies the returned key stays with the original identity and newer edits stay unsaved.
