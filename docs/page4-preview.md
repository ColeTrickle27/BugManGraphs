# Page 4 isolated review preview

Base `cee2aafef73616319f6bb127a1b550c06b1058f1`; branch `preview/digiboard-page4`.
Changes are preserved in a local commit on the isolated preview branch. No push, deployment, auth/gate changes,
customer writes or New Job form rewrite. Other worktrees remain untouched.

## Run and review

Build with:

```powershell
flutter pub get
flutter build web --release --no-wasm-dry-run --dart-define=PAGE4_REVIEW=20261021_final --target lib/page4_preview.dart
```

Run the task-folder `serve-preview.ps1` in a hidden/background PowerShell process.
Open `http://127.0.0.1:8794/` for a blank synthetic in-memory editor.
The normal preview uses an unavailable portal service. For the synthetic export
review fixture use `/?exportReview=1&fixture=standard` (or `wide`, `tall`), then
Fit drawing. This fixture alone substitutes a memory portal and sends exports
only to the loopback server, under `artifacts/page4/exports`. It never contacts
Ops Brain. The standard fixture has three synthetic logo-photo appendices.
The bundled PDF.js renderer also stays local. Cache identity is
`20261021-page4-review-final2`.

## Final behavior

- Primary Sketch / Area chooses Square, Polygon, Curved line or Straight line
  before classification. Polygon finishes at its starting point, double-click,
  Enter or Tab. Context-launched sketches begin at the menu's world coordinate.
- Classification shows six common/recent choices, More types with search and
  Building/Outdoors/Lines/Treatment groups, and Custom description. Apply is
  explicit. Classify later retains geometry; Undo shape discards it. Selected
  shapes expose Change shape type for correction. Every valid legacy category
  remains accessible; Patio/custom are added and existing Driveway is retained.
- Quick Measure and its dedicated transient interaction path are removed, per
  the later instruction. The serialized legacy measurement enum remains readable.
  Ordinary lengths/areas and existing saved geometry remain supported.
- Viewport zoom spans 1–3200%, with absolute presets both below/above 100%,
  consistent wheel/pinch limits, center-anchored buttons, Fit drawing and 100%
  reset. It never changes coordinates or physical calibration. Modifier wheel
  and Spacebar pan remain supported.
- Empty-canvas right-click has exactly Sketch structure, Add note, Callout box.
  Selected-object menus retain contextual actions. Escape dismisses menus;
  Select-mode touch long press provides the same menu without stealing pan.
  Draft right-click undo remains intact.
- Callouts use shared painted/hit/export bounds. Boxes are no longer clamped to
  the old finite page. Body dragging preserves grab offset and world leader tip;
  corner handles resize the box; the tip handle moves the leader separately.
  Text editing remains readable at negative coordinates/extreme zoom. Escape
  discards a new inline draft or cancels an existing edit. Delete/undo/redo and
  extra-property save/load are covered.
- Quadratic curves now measure actual arc length instead of chord length. Exact
  Green-integral area includes curved boundaries, including two-segment closed
  regions. Measurement labels anchor to the curve midpoint. Adaptive curve hit testing follows
  the bowed edge rather than its chord; selection/movement/undo are covered. Saved control points
  are unchanged. LF/sqft display whole numbers and acres two decimals; source
  values retain double precision.
- Curve joining on a single existing straight-edge structure offers Cancel,
  Keep line or Fill area; Fill copies the shorter boundary with snapshot undo.
- HVAC remains; Access retains `crawlspaceAccess` serialization and draws a
  doorway/exit arrow. Piers use outlined grid geometry. Both Steps variants remain.
  Gas is green dashed and water blue dashed. Canvas and exports share rendering.
- Rounded expandable Graphs toolbar keeps all original tool actions, 44px touch
  targets, reduced-motion support, outside-click label collapse and phone More
  actions. The supplied reference's unrelated Home/bell actions were not copied.
  Chrome/dialogs have layered white surfaces, subtle borders, #C20000 hover and
  selection accents, restrained header gradient and native selection motion.
  No animated textures were added behind the work canvas or to exports.

## Export verification

PNG now rasterizes the completed PDF at 144 dpi. Both formats use the same
headers, customer metadata, measurement summary, legend, colors, labels, page
framing and photo inclusion. Existing bundled Bitter fonts preserve Unicode
customer/header text. A multipage PDF becomes one PNG page strip with all pages
centered and a 24px gray gutter; no appendix is silently omitted. Safe strip
limits are 16,384px wide, 32,768px high and 64 million pixels, otherwise an explicit
error directs the user to PDF. Diagram scene bounds retain the existing explicit
8,192 world-unit-per-side export limit and pattern geometry budget.

`tool/page4_capture_exports.js` exercises the actual toolbar actions in an
isolated headless browser. `tool/page4_export_parity.js` independently rasterizes
all exported PDF pages using local PDF.js and compares RGBA pixels to each PNG.
Standard (3 pages, 1584x4440), wide and tall (1 page each, 1584x1224) matched with
zero differing pixels and zero maximum channel error after the final header-font
polish. Each paired artifact has its own independently rendered reference and JSON result.
Fixtures include negative coordinates, curved boundary, native hatch, labels,
callout leader, Access/Piers/Steps, gas/water lines, inspection legend and photos.
The comparison verifies raster visual parity, not physical print scale.

## Library assets and exact blocker

The first batch is used only as Graphs fills, never dashboard textures. Exact PAT
text, origins, offsets and signed dash data are retained in
`lib/services/graph_pat_catalog.dart`. Repeats are validated as blockwork 450x450,
brick 225x150 and checkerplate 1x1. Native geometry is stable in canvas and export.
Proposed preview mappings are green/lime blockwork for Main Structure, tan/brown
brick for Patio and gray checkerplate for Driveway; saved styles are not changed.

Supported Library materialization failed on the laptop while applying provenance
metadata: `AttributeError: module 'os' has no attribute 'setxattr'`. Raw original
PAT-file archival and herringbone JPEG (`libfile_77e504f91ad48191ad44700fefd7aecd`)
materialization remain blocked by that helper error, not a denied permission.
PAT definitions were independently obtained through authorized Library text reads.
No provenance controls were patched. EPS was never executed or downloaded.
The toolbar PNG was visually inspected by the parent through supported cloud
materialization; its React companion was read as plain text, never executed.

## Calibration decisions and limits

Sketch dimensions retain the legacy assumption of 24 canvas units/foot. A known
240-unit edge is numerically 10ft and a 240x240 square 100sqft under that convention.
This does not independently establish a real property's scale. Viewport percent,
Fit drawing and PDF page fitting are not physical calibration. Existing map/trace
calibration records remain intact. A future reviewed choice is how field-known
lengths calibrate legacy sketches without silently rescaling historical drawings.

Fill between different structures or along an already-curved existing boundary
remains unsupported because it needs a reviewed region/curve-splitting policy.
The original PAT sources are preserved as text, but the JPEG cannot be claimed
integrated until supported Library materialization succeeds.

## Evidence

Current browser captures are under `output/playwright/`: desktop/mobile final,
classification and context screenshots, plus callout selection and wide/tall views.
Actual paired PDF/PNG, independently rendered reference PNG and parity JSON files
are under `artifacts/page4/exports/`. Native PAT gallery and earlier test captures
remain under `artifacts/page4/` for provenance.

Final verification: 141 tests, clean static analysis and a release web build.
Verification logs are in the task folder: `page4-verified-test.log`,
`page4-verified-analyze.log`, `page4-verified-build.log`, `page4-browser-export.log`,
`page4-export-parity.log`, `page4-browser-workflows.log`. Browser QA uses an isolated
headless session; Cole's foreground browser was never taken over.

## Preservation and Library attachment follow-up

The completed batch is locally committed; use `git rev-parse HEAD` for the exact
review checkpoint. Unrelated formatter-only test changes, generated header line
endings and temporary browser records were deliberately left outside the commit.
The preview server remains running on loopback port 8794.

One supported prepared-upload batch attempted these synthetic deliverables:
`BugMan Graphs - Page4 Export.png`, `BugMan Graphs - Page4 Export.pdf`,
`BugMan Graphs - Desktop Preview.png`, `BugMan Graphs - Mobile Preview.png`.
The helper returned `library upload failed: prepare_uploads failed`, with no
Library file IDs. No transfer/finalization was confirmed. A read-only Library
search found no exact canonical matches for those filenames. The operation was
not retried and was not replaced with another upload route. Original paired
exports and screenshots remain intact at the evidence paths above.

Styling coverage: the Graphs editor chrome, rounded animated quick toolbar,
shared dialogs/menus, inputs, cards and selection/hover accents are updated.
This is a restrained adaptation of the modern-app direction; it is not a full
screen-by-screen visual audit of every legacy Graphs route or an exact clone of
the latest homepage composition. No other application/worktree was changed.
