# Disabled Graphs session relay and activation adapter

PR19 is rebased onto released main 5af35b975bdae490203d8bb4c20e1468a10cde12, preserving the approved PR20 export cleanup. The production frontend flag remains literal false; Pages forwarding requires GRAPH_DRAFTS_RELAY_ENABLED exactly true, which is absent from the current project. No migration, credentials, Access grant, service token, signing secret, cookie domain or live configuration was changed.

The exact allowlist is POST /api/login and /api/logout, GET /api/me, GET /api/graph-drafts/context and /authors, paginated GET /api/graph-drafts, and GET/POST /api/graph-drafts/:id. The authority is fixed https://ops.holloman-ext.com. No caller-selected proxy path/host, unsupported methods, redirects or CORS are allowed. Before origin adaptation, incoming Origin and Sec-Fetch-Site/Mode/Dest must prove a same-origin API fetch. GET may omit Origin; POST must supply the exact Graphs origin. The browser's actual destination value is empty (the literal string), not a blank header. Account operations preserve the pinned expected-account header. Only the opaque hob_session cookie is forwarded; only a host-only HttpOnly/Secure/SameSite=Strict cookie is returned. JSON bodies are size-limited while streaming; responses are private/no-store and compressed JSON remains streamed without recompression. No signing is performed on Graphs.

The adapter uses existing username/password only for the same-origin login request. Password UI is cleared after submission; no session token is read by Dart or persisted in application storage. me supplies display information, context supplies immutable ownership. Successful sign-in builds a new scoped workspace; logout first flushes durable recovery. Explicit import retains the original legacy document. Existing customer-folder APIs remain unchanged pending the separate route-scope decision.

## Read-only live configuration and Access obstacle

Pages project bugman-graphs has domains graphs.holloman-ext.com and bugman-graphs.pages.dev, production branch main, compatibility date2026-08-05, no service bindings, no relay enablement variable and no session signing secret. Existing address-provider variables were not read/copied or changed.

Access app c0b5dbbd-fbe8-4233-aba8-44a58ddd14c2 covers ops.holloman-ext.com. Policies include non_identity d0172127-07a6-4377-88fa-4718e0fbaa8c and identity allow292a632e-bc68-48f6-94a6-3ebb461a3c6e. An unauthenticated normal browser GET /api/me redirects to Cloudflare Access login HTML rather than returning backend JSON. The relay has neither an authorized service identity nor that host's Access cookie; it rejects such redirects. No challenge was solved, policy changed, token created, credential copied or internal path used to route around Access. Parent must coordinate any separately approved minimal security change.

## Activation prerequisites and limits

Backend owner must confirm migration protection, backup and successful migration; historical backend deployments binding production storage remain an owner-reported blocker. Independent security review is required before live deployment. Joint tests with the actual isolated backend must pass, and the Access path must be explicitly authorized. Existing Customer Files saves currently use an OpsBrain-host cookie, which a Graphs-host login cannot supply; they need either separately reviewed exact relay routes or a clearly supported separate OpsBrain sign-in. This choice has been raised and is not silently implemented.

Node relay tests, Flutter tests and Wrangler Functions compilation exercise this code. The two-browser fixture uses an in-process protocol backend with synthetic users/session tokens/data, not production credentials or real backend/migration. It verifies independent sessions, shared graph/full-photo bytes, stale revision rejection, local scoped recovery, an already-open offline canvas, and account switching. It does not prove live Access, migration, offline edits/reload, real backend end-to-end, manual customer-folder auth or physical iPhone behavior. Keep both gates off until those prerequisites are resolved.

References: Cloudflare Pages Functions routing, Workers best practices and Response encodeBody documentation were retrieved before implementation. No new provider or production dependency was introduced.

## Prepared Access handoff and entry guards

The relay now accepts only server bindings GRAPH_OPS_ACCESS_CLIENT_ID and GRAPH_OPS_ACCESS_CLIENT_SECRET and refuses noncanonical Graphs hosts. Incoming credential headers are discarded; upstream CF_Authorization cookies never reach the browser. The user must create and enter the actual encrypted values in Cloudflare; no credential values were created or read here. The separately protected /access-ready page opens in a new tab without replacing the editor and does not claim successful upstream authentication.

Authentication precedes bill-to/location lookup and shared-graph loading. Verified customer mapping remains intact. Shared Customer Files graphs require an explicit Copy to My Graphs action to become independent account drafts; opening the source preserves its existing repository. Manual Customer Files publication retains separate OpsBrain sign-in, with no relay scope expansion or cookie-domain change.

Parent reports the guard-only backend release and 363 historical-host denies complete; account migration remains off. This code still requires independent review, secure user credential entry, migration confirmation and actual joint backend acceptance before activation.

## Review follow-up: forms and entry lifecycle

Ordinary gallery creation and verified customer entry now share the same guarded creation route. The original form controllers stay mounted but hidden after account invalidation. A fresh verified original-account session may resume them; a different account is rejected without rebinding or submission. Explicit discard explains the unfinished-form loss. Recovered workspaces retain the original storage scope and own their authentication client lifecycle.

Shared copy and structure-derived creation refresh the minimal active author directory before creating a draft. Account editors initiate queued upload on opening and retry every 30 seconds or app resume, independently of gallery visibility. Existing session serialization prevents parallel writes. No activation gate or live configuration changed.

## Owning-route recovery and current-fork retry

The session wrapper retains its authenticated entry subtree through invalidation. Pushed forms capture an owning-session resume delegate before navigation; verified original-account sign-in updates that owner without disposing the retained form. Locked forms unfocus and exclude keyboard focus, hide their input, and refresh active creator options on recovery while retaining the same controllers. A deactivated selection receives an explicit correction; submission uses a current active creator or no guessed identity.

Entry author refresh retains verified cached choices through connection failure; without a cache the form remains usable with an explicit unavailable-choices message. Confirmed ownership/permission failures are propagated. Editor retry waits for repository transitions and retries the current session, including Keep Both forks, rather than the original constructor session.

## Explicit recovery ownership and sign-in reachability

Inactive authenticated entry subtrees remain mounted offstage while the root exposes its normal sign-in screen. Closing a locked shared editor or discarding an interrupted form therefore retains a usable sign-in route. Root-owned recovered workspaces are installed by the session owner and are never disposed by a form; only locally owned fallback recovery workspaces are released by that form. Entry state follows explicit root workspace updates after sign-in. Regressions cover closing/discarding, successful sign-in, returning to My Graphs after recovery and starting another graph with the same active root-owned scope.

The dedicated relay identity duration is approved for one year; the backend owner verifies metadata only. Actual credential creation and encrypted binding entry remain user-only. This duration update does not change relay/session code, activation or migration.

## Prepared machine-only upstream path (2026-10-15)

The Graphs server adapter now maps its existing allowlisted browser routes to a fixed machine-only namespace on the same Ops authority:

| Graphs browser route | Fixed Ops upstream route |
| --- | --- |
| POST `/api/login`, `/api/logout` | POST `/api/graph-relay/login`, `/api/graph-relay/logout` |
| GET `/api/me` | GET `/api/graph-relay/me` |
| GET `/api/graph-drafts/context`, `/authors` | GET `/api/graph-relay/graph-drafts/context`, `/authors` |
| GET `/api/graph-drafts` with validated pagination | GET `/api/graph-relay/graph-drafts` with identical query |
| GET/POST `/api/graph-drafts/:id` | GET/POST `/api/graph-relay/graph-drafts/:id` |

Only an already validated route is mapped. Browser access to `/api/graph-relay/*` remains rejected. No fallback to human-facing Ops routes is permitted; redirects/HTML remain rejected. The upstream host, Origin, server credential bindings, signed session cookie rules, expected-account header, revision payload, streaming limits and feature gates are unchanged. Manual Customer Files publication remains separate Ops sign-in.

Parent coordinates the approved machine-only Access path and shared Ops deployment with the backend and Quotes owners. Backend must confirm these exact aliases dispatch to the existing handlers, preserving host-only `hob_session` cookies with Path=/ and JSON/status/precondition semantics. No new backend machine-path implementation was available on the published backend branch during initial preparation. This is a compatibility candidate, not live acceptance. Backend verification and a backed-up successful migration are required before autosave activation. No credential values are read or stored in source.
