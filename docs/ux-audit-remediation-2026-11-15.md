# November 15 UX audit remediation

Base: `41d1aaf03626086180a16620dc7d15f07c42f6b1` (released layer panel preserved).
This branch contains no unfinished station/imagery work.

| Audit item | Result | Verification |
|---|---|---|
| UX-001 mode-switch loss | Separate manual and linked-customer snapshots retain fields, contacts, visibility and stable identity without mixing them | New regression failed before; manual/linked round trips, canonical IDs, authentication/network failures and unassigned creation pass |
| UX-002 intake Back loss | Dirty intake asks Keep editing or Discard information; clean exit and successful creation remain direct; browser unload also warns | New regression failed before; app Back keep/discard and creation pass |
| UX-004 note clipping after Fit | Fit refines zoom-aware painted text bounds, retaining drawing scale/calibration and space for callouts | New desktop/phone regressions failed before; reopen/Fit bounds and unchanged document checks pass |
| UX-005 unavailable local Existing mode | Explains origin/context unavailability and offers Use New Customer, preserving the manual draft | New regression failed before; no invented offline access or customer identifiers; auth/network errors stay distinct |
| UX-003 offline font finding | Retained as historical, not reproduced on Flutter 3.47.9 | No font-source changes |
| UX-006 abrupt-loss recovery | Last explicit save remains the verified recovery boundary | No new autosave promise or cloud recovery change |

## Uploaded graph / startup investigation

A service-worker preparation timeout alone did not prevent Flutter boot in a synthetic check. A failed entrypoint did leave the old page blank; the startup screen now provides recovery after resource/engine failure, an unhandled startup dependency failure, or a long wait. Reload preserves the complete URL and graph key. The release cache marker is updated; service-worker handling and protected API authentication remain intact.

A separate synthetic valid graph package at offscreen coordinates (including a note-only package) reproduced an initially blank editor despite correct key/parse. Uploaded editable graphs now fit their visible content on entry. Two regressions failed before and pass after. Finalized packages still use the existing read-only path.

These reproduce bounded software defects; they do not establish the cause of the reported signed-in .bgraph session. The actual signed-in package/transport/cache state remains unverified. Blank rendering is not evidence of data loss.

## Validation and boundaries

Flutter 3.47.9 / Dart 3.13.7. Local validation includes analyze, the full Flutter suite, focused final-delta tests, the release build, startup JavaScript tests, and isolated desktop/phone browser checks. CI runs Flutter checks plus the Node startup regressions. Test artifacts are not application source and are excluded from the commit.

Browser checks cover local draft preservation, explicit discard, synthetic create/draw/save/reopen, full note visibility after Fit, the released layer panel, service-worker timeout continuation, entrypoint retry with key retention, and synthetic graph-link success/authentication/malformed-package results. No customer records or production graph files are changed by these checks.

No saved graph schema, geometry, calibration, attachment format, treatment rules, API contract, credentials or authorization policy changes. The local lookup explanation does not promise network/authenticated data availability. Physical-device keyboards and real authenticated customer flows are outside the synthetic evidence.

Rollback reference: pre-release main `41d1aaf03626086180a16620dc7d15f07c42f6b1`. If a production regression occurs, revert this PR merge through a reviewed commit and let the existing deployment workflow publish it; do not reset main or alter customer records.

## Review regressions

A far-away hidden trace was reproduced shrinking visible uploaded walls; fitting now uses the current layer visibility. Hidden content remains stored unchanged. The no-JavaScript explanation was covered by the startup overlay; the no-script path now hides that overlay. Owner-driven `Navigator.pop(Job)` already bypasses system-Back guarding in Flutter: the existing recovery tests and a new direct dirty-intake completion regression pass without changing the guard contract.
