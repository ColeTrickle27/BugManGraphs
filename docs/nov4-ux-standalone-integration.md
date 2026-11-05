# November 4 UX batch on released standalone Graphs

## Delivery and source boundary

This local candidate is based on standalone BugManGraphs `9c64de9a91b45a0654fc59d30ce2735462444e8d` (merged PR24). Ops production `c080aa564027c2c79606cd9893358bbd37dbffb4` uses `npm run build:hub`: it omits mounted Graphs, emits the `https://graphs.holloman-ext.com/` launcher, and redirects old `/bugman-graphs` paths there. The dedicated archived audit preview at `8d123c9…` is a different delivery. No routing, build configuration, activation gate, credential or authorization change is part of this candidate.

The reviewed archived-preview patch `3ca25da…` was adapted manually to current source, not merged wholesale. Both complete source histories are preserved separately in the private review artifact. There were no merge conflicts to resolve and no sibling/private application implementation was imported.

## Scope mapped to current production

| Approved item | Current production behavior | Local adaptation |
|---|---|---|
| Blank structure copy | Local/account-draft copy exists; local copy centers the large canvas and is initially clean, so first Save can be skipped | Explicit transient fitting for local copy and saved-local entry. New copies are dirty until their first save; no serialized field changed. Current account-draft callbacks and initial-fit logic remain intact. |
| Phone viewing/full title | Cloud preview already opts into content fit; no Fit action and title can truncate | Preserve content bounds/geometry padding, reduce screen padding, add read-only Fit action, preserve manual zoom/world center on resize, and expose full titles by touch/keyboard/semantics |
| Phone editor crowding | Collapsible tools/action pickers exist; categories clip; notices cover controls | Compact entry starts collapsed, wider readable tools, retained section/selection state, hidden-focus exclusion, and reserved dismissible notices including the original Open folder action |
| History dates | Cloud list sorts DateTime instants but displays `toLocal().toString()` | Readable local date/time plus UTC offset; retain exact source timestamp for tooltip/semantics; strict invalid/missing fallback; existing instant sorting/pagination remain intact |

**Cloud structure-copy is not added.** PR24 cloud history deliberately opens an isolated read-only complete-package preview with write-rejecting repository and disabled portal service. It has no Copy action. This batch adapts the existing local/account-draft copy route only. Restoring the archived locked-cloud Copy workflow or its separate finalization/download UI is a different scope decision; this candidate does not claim that feature parity.

The existing copy contract remains: new identity, wall/shape/customer reuse, no annotations/attachments/traces, and default legacy calibration rather than visit calibration. Only transient dirty state changed. Current unknown-field, photo, identity, account-session, finalization/receipt and watermark boundaries were preserved. A clean non-copy graph still performs no save; only a newly created structure copy now allows its first save without another edit.

## Verification

Toolchain: Flutter 3.47.9 / Dart 3.13.7. Unchanged production baseline: clean analysis, **407 tests passed**, release web build passed. Combined candidate: clean analysis, **420 tests passed, zero failures**, release production-entrypoint build passed. America/New_York date tests cover repeated/fall and skipped/spring DST hours. SDK-generated analysis-options/lockfile edits are excluded; no application dependency change is committed.

Thirteen new tests cover viewport/state/title behavior, actual Copy/Cancel/Save/reopen in all three sizes, preserved Open folder action, timestamp parsing/display/sorting and exact offset retention. Four existing expectations were updated only where this batch changes behavior: copied drafts now require their first save; notices now contain a real TextButton instead of SnackBarAction (the tests click it and retain URL assertions); a phone screenshot test explicitly opens collapsed tools. No unrelated legacy behavior was changed to make tests green.

Actual local production builds were exercised at 1440x1100, 390x844 and 844x390. Checks include three repeated Copy/Cancel cycles, visible copied structure/name/dimensions, saved local identity/customer/calibration, Chromium persistent-profile restart, app reopen, title touch/keyboard activation, toolbar section retention, orientation resize, notices above main and Undo/Redo controls, current save/share dialogs and source immutability.

The browser's real IndexedDB `bugman-graphs/documents` survives a full browser-context restart. Canonical graph publication is additionally exercised through the existing loopback compatibility-origin branch: exactly one intended new-copy save request per size is captured to a local disk mock, with a distinct ID and no locked-source target. Cloud preview loads the same document ID as a different local original and leaves the full local cache unchanged. Its repository/service remain read-only, the mocked locked envelope/receipt identity remains unchanged, and a simulated 401 clears cloud metadata. No unintended API writes occur.

Root-local tests cannot establish trusted standalone-host authentication. Compatibility-origin tests exercise the production HTTP service code with synthetic local responses, not a real authenticated OpsBrain service. Server receipt cryptography is not tested by matching mock claims. Production 403 routes were not retried or bypassed; signed-in hosted acceptance remains separate.

The isolated harness initially blocked Flutter public fallback fonts. Final visual/export runs instead fulfill the two exact public font resources from local byte fixtures; no production CSP/font/configuration change was made. PNG exports are byte-identical baseline/candidate at all three sizes (1584x1224). PDF page count, page size (792x612), extracted text and rendered pixels match. Visible labels, watermark, graph geometry and package photo marker were inspected. The build emits the baseline Cupertino-font warning.

## Sixteen archived failures classified against current source

These are **not current production failures**. Twelve exact names pass on both `9c64de9…` and the combined candidate. Two obsolete expectations have explicit updated equivalents; two absent old names have the geometry/undo coverage and limits below. No archived failure was hidden or waived as a current failure.

| Archived stable test name | Current production / combined evidence | Classification |
|---|---|---|
| `test/editor_interaction_test.dart: toolbar cleanup preserves legacy enums but hides removed entries` | Exact name passes / passes | Current covered behavior; no inherited failure |
| `test/graph_annotations_painter_scale_test.dart: moisture-reading marker: icon and label scale together and stay tight` | Exact name passes / passes | Current covered behavior; no inherited failure |
| `test/widget_test.dart: Callout Box places an editable inspection note on the graph` | Exact name passes / passes | Current covered behavior; no inherited failure |
| `test/widget_test.dart: Export PDF/PNG save the graph and rendered exports to Ops Brain` | test/widget_test.dart: retained legacy PDF/PNG callbacks preserve OpsBrain export support — success | Superseded expectation: current explicit device handoff is separate from graph publication; retained legacy callbacks remain tested |
| `test/widget_test.dart: Export stops before upload when its automatic graph save fails` | Exact name passes / passes | Current covered behavior; no inherited failure |
| `test/widget_test.dart: Exporting PDF/PNG to Ops Brain is unavailable outside Holloman Ops Brain, and never calls uploadGraphExport (item 8)` | Exact name passes / passes | Current covered behavior; no inherited failure |
| `test/widget_test.dart: Treatment Area plots points and double-click closes the area` | Exact name passes / passes | Current covered behavior; no inherited failure |
| `test/widget_test.dart: deleting a finished shape removes its backing lines` | Exact name passes / passes | Current covered behavior; no inherited failure |
| `test/widget_test.dart: dragging a rectangle vertex moves only its connected corners` | test/widget_test.dart: dragging a basic rectangle corner keeps it rectangular — success | Old name absent; current primitive-aware corner movement has explicit coverage |
| `test/widget_test.dart: drawing tools can overlap shapes and place markers inside them` | Exact name passes / passes | Current covered behavior; no inherited failure |
| `test/widget_test.dart: generic shapes require drag and double-click opens properties` | test/widget_test.dart: generic shapes insert on tap and double-click edits inline text — success | Superseded gesture expectation: current basic shapes insert on tap and edit text inline |
| `test/widget_test.dart: iPad-sized touch drag moves an object without drawing a structure` | Exact name passes / passes | Current covered behavior; no inherited failure |
| `test/widget_test.dart: keyboard deletion and undo redo preserve serialized graph geometry` | test/canvas_deletion_test.dart: $kind delete/repeat/undo/redo/reopen ($keepOther unrelated, $size) — 24 success | Old monolithic name absent; dedicated deletion/keyboard undo-redo/serialization tests cover six object kinds and two sizes. Deletion is activated through the UI button in those cases, so they do not establish a direct Delete-key equivalence. |
| `test/widget_test.dart: main toolbar tools can be dragged into quick tools` | Exact name passes / passes | Current covered behavior; no inherited failure |
| `test/widget_test.dart: selected shape rotation handle rotates the finished shape` | Exact name passes / passes | Current covered behavior; no inherited failure |
| `test/widget_test.dart: top toolbar keeps file and canvas options collapsed` | Exact name passes / passes | Current covered behavior; no inherited failure |

The dedicated deletion suite uses the Delete selection UI control, then keyboard Ctrl+Z/Ctrl+Y, and asserts serialized geometry/traces across reopen for six object kinds, two sizes and retained/unrelated data (24 passing cases). Those cases do not directly assert a Delete/Backspace key trigger; the absence of the old test name is not evidence of a product defect. Rectangle-corner coverage explicitly preserves the rectangular primitive.

## Release status

Local/private review candidate only. No push, PR mutation, merge, deployment, hosted workflow, production/preview configuration change, real customer write or denied-route retry was performed. Before release, finish separate authenticated standalone acceptance for the exact candidate, verify account/session and photo/receipt behavior in that permitted environment, review the exact commit and obtain separate release authorization. Keep complete recovered source histories private.
