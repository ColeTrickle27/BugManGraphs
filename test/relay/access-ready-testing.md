# Access-ready diagnostic proposal validation

This unpublished proposal changes only `functions/access-ready.js` in application code. The other changed files are synthetic tests and this validation note. No activation settings, Flutter source/assets, workflows, or authentication policies change.

From the repository root, with Node 24 and installed Playwright/Chromium:

```bash
node --check functions/access-ready.js
node --check test/relay/access-ready.browser.cjs
node --test test/relay/*.test.mjs
node test/relay/access-ready.browser.cjs
git diff --check
```

The browser harness uses `/usr/bin/chromium` by default; `CHROMIUM_EXECUTABLE` may select an installed Chromium. `ACCESS_READY_TEST_OUTPUT` may select an artifact directory; otherwise output goes to a newly created temporary directory. It imports the actual route, invokes it with a synthetic canonical Request and synthetic binding-presence arguments, and serves its response on loopback. Browser requests to other origins are aborted. No user browser profile or real credentials are loaded.

Observed: 57 Node handler/relay tests passed, including browser-script syntax compilation. These are separate from 15 actual Chromium 155 browser scenarios: user-shaped success; five fixed 401 errors; unknown error; malformed JSON; HTML; array/null user; manual redirect; socket failure; actual 10-second timeout; missing bindings. Browser checks cover zero requests on load, one application fetch despite repeated clicks, exact GET/path/options with no query/body, actual same-origin fetch metadata, nonce/CSP execution, no CSP violation or page errors, no sentinel rendered, and zero redirect-target requests.

A socket closed before response headers caused Chromium to retry the read-only GET: two wire requests from one JavaScript fetch. The proposal has no application retries and does not guarantee exactly one wire request. `session_available` means only HTTP 200 with an object-shaped user, not cryptographic identity validation. `Sign in required.` maps to `application_signin_required`, distinct from employee Access.

Cloudflare Pages Functions compile/bundle remains unverified: `wrangler pages functions build --help` failed with exit 127 (`wrangler: command not found`). No cached installed Wrangler was found; no package installation, authentication, or remote bindings were attempted. JavaScript syntax checks and real module execution passed; these do not replace a Cloudflare bundle check.

Flutter analyze/test/release build were not run for this isolated Functions-only proposal. The existing deployment workflow rebuilds Flutter and deploys the full Pages artifact; this task does not establish a Functions-only deployment mechanism or byte-identical deployed assets. Before release, an authorized workflow must compile the Functions and verify reuse or equivalence of baseline static assets, with account/draft UI still compiled OFF. No workflow or asset changes are included here. Production Access, cookie delivery, and relay authorization still require separately authorized end-to-end validation.
