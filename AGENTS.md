# BugManGraphs — Agent Instructions

## Purpose

This repository is the source implementation for Holloman Exterminators' BugMan Graphs application.

BugManGraphs is an independent graphing, measurements, and site-plan application. Existing markers, photos, and findings remain supported graph data. A future general inspection app will be a separate product with a unique name; do not repurpose this application for it.

Treat this as a production business application.

Preserve:

* existing graph data
* drawing behavior
* measurements
* inspection markers
* customer identity
* saved-graph compatibility
* OpsBrain integration
* field usability

---

# Core Working Rules

## Prefer the smallest safe change

Modify only what is required for the current task.

Do not:

* rewrite working features unnecessarily
* refactor unrelated code
* change unrelated drawing behavior
* redesign unrelated UI
* change storage formats casually
* introduce new frameworks or platforms without approval

If a broader architectural improvement would be useful but is not necessary for the current task, report it separately.

---

## One task, one scope

Prefer:

`one task → one branch → one pull request`

Do not combine unrelated:

* features
* bug fixes
* refactors
* architecture changes
* dependency upgrades
* cleanup

If another issue is discovered, address it only if it directly blocks or safely completes the current task.

Otherwise report it separately.

---

# Technology Standard

BugMan Graphs is a Flutter application written in Dart.

Continue using:

* Flutter
* Dart
* existing Flutter packages and application patterns

Do not rewrite BugMan Graphs into:

* React
* TypeScript
* JavaScript
* another frontend framework
* another cross-platform framework

merely to make it match OpsBrain or SalesBrain.

BugMan Graphs has specialized canvas, geometry, gesture, image, PDF, mapping, and field-interaction requirements. Flutter remains an approved technology for this application.

Integration consistency should come from stable APIs and data contracts, not from forcing every Holloman application to use the same frontend framework.

---

# Repository Structure

Important areas currently include:

* `lib/main.dart` — Flutter application entry point
* `lib/editor/` — graph editor behavior
* `lib/models/` — graph and domain data models
* `lib/screens/` — application screens
* `lib/services/` — OpsBrain, export, mapping, storage, and supporting services
* `lib/theme/` — application styling/theme
* `lib/widgets/` — reusable Flutter widgets
* `pubspec.yaml` — Flutter dependencies and project configuration

Add new behavior to the appropriate existing area rather than accumulating unrelated logic in `main.dart`.

---

# GraphDocument Is Business-Critical

`GraphDocument` is the durable, serializable source of truth for a saved inspection graph.

Treat changes to its structure, serialization, schema version, migration logic, and object relationships as data-format changes.

Do not casually change or remove serialized fields.

Preserve compatibility with previously saved graphs whenever reasonably possible.

When changing persisted graph structure:

1. Determine whether existing saved graphs can still load.
2. Preserve unknown or forward-compatible properties where supported.
3. Add migration/backward-compatibility handling when required.
4. Test loading older graph data.
5. Test saving and reopening new graph data.

Never solve a UI problem by casually breaking the durable graph format.

---

# Drawing and Editor Behavior

The graph editor is the core product.

Changes to the editor must protect existing behavior for:

* walls
* property lines
* shapes
* markers
* freehand drawing
* text
* photos
* measurements
* selection
* movement
* resizing
* rotation
* zoom
* pan
* layers
* tracing

Do not change unrelated editor interactions while fixing one tool.

When modifying a drawing tool, verify other major tools still behave normally.

Avoid global gesture changes when a tool-specific correction can solve the problem.

---

# Geometry and Measurements

Treat graph coordinates, scale, calibration, dimensions, and measurement calculations as business-critical behavior.

Do not alter:

* coordinate systems
* scaling formulas
* measurement calibration
* distance calculations
* export scaling
* geometry serialization

without understanding how existing graphs and exports will be affected.

A visual change must not silently change the underlying measured geometry.

Where measurement behavior changes, test representative known dimensions.

---

# Inspection Markers

Inspection and treatment markers are structured operational information, not merely decorative icons.

Examples include findings such as:

* active termites
* moisture readings
* wood-decaying fungi
* old damage
* insulation issues
* pest access points
* standing water

and treatment information such as:

* drilling
* trenching
* treatment locations

Preserve structured marker identity separately from its visual presentation.

Changing an icon, color, label position, or appearance should not unnecessarily change the underlying marker type or saved data.

Marker data should remain usable by future OpsBrain, SalesBrain, inspection-report, and AI workflows.

---

# Findings Integration

BugMan Graphs is expected to supply structured inspection information to other Holloman tools.

Prefer machine-readable graph data over extracting meaning from screenshots or rendered graph images.

A downstream system should be able to determine structured facts such as:

* which inspection markers exist
* marker type
* marker notes
* moisture readings
* customer identity
* graph identity
* attached findings

without depending solely on image recognition.

Do not remove structured information merely because the visual graph still looks correct.

---

# Photos and Attachments

Photos and attachments may be operational evidence associated with an inspection.

Protect:

* attachment references
* photo association with graph objects
* saved-image compatibility
* photo numbering or identifiers
* export behavior

Do not silently discard attachments during duplication, editing, loading, or saving.

Be especially careful when changing:

* image compression
* blob handling
* attachment serialization
* upload behavior
* graph duplication behavior

---

# OpsBrain Relationship

OpsBrain is the operations hub. The shared integration layer is holloman-mcp and approved shared APIs. Existing OpsBrain-hosted APIs remain compatibility endpoints until individually migrated and verified.

BugMan Graphs should integrate with shared Holloman capabilities through OpsBrain APIs rather than creating competing systems.

The approved shared API layer provides capabilities such as:

* authentication
* permissions
* customer/location lookup
* file storage
* shared business records
* company-wide integrations

BugManGraphs remains specialized around graphing, measurements, and site plans. Keep its source, build, and feature work in this repository; never import sibling app source.

Do not turn this repository into a second general-purpose OpsBrain backend.

---

# OpsBrain API Integration

Web integrations should use approved OpsBrain API routes.

Current integration includes OpsBrain-backed graph save/load and Customer Files upload behavior.

Preserve authenticated request behavior and stable API contracts.

Do not make Flutter browser code directly responsible for privileged:

* D1 access
* R2 credentials
* Cloudflare secrets
* provider secrets
* PestPac credentials
* administrative tokens

Privileged operations belong behind the OpsBrain/server API boundary.

---

# Customer Identity

Preserve Holloman's Bill-To / Location customer identity model.

Graph data associated with a customer should preserve stable customer information including, where available:

* Bill-To number
* Location number
* customer name
* service address

Do not create a conflicting BugMan-only customer identity system.

Bill-To / Location compatibility is especially important for:

* Customer Files
* SalesBrain
* future inspection reporting
* future PestPac synchronization

---

# PestPac

PestPac remains Holloman Exterminators' operational system of record for customer, location, service, scheduling, billing, service-history, and related pest-control operational records unless explicitly changed by an approved architecture decision.

BugMan Graphs should not independently duplicate PestPac-owned workflows.

Do not add direct PestPac write behavior unless explicitly requested and approved.

Preserve Bill-To / Location compatibility so graph records can participate in future PestPac-integrated workflows.

---

# SalesBrain Integration

BugMan Graphs and SalesBrain should communicate through stable OpsBrain-supported contracts.

SalesBrain may consume:

* graph identity
* customer identity
* structured inspection findings
* markers
* notes
* graph exports
* other approved graph metadata

Do not couple SalesBrain to Flutter widget internals or editor implementation details.

Do not require SalesBrain to parse compiled Flutter code.

Do not require SalesBrain to infer structured findings from an image when structured graph data is available.

---

# Data and Storage Boundaries

Use OpsBrain-approved infrastructure for shared persistent business data.

General direction:

* R2 — files, images, PDFs, graph packages, and binary artifacts
* D1 — structured relational operational data where appropriate
* OpsBrain API — controlled access to shared business data

BugMan Graphs should not introduce another database or storage provider without explicit approval.

Do not migrate graph data from one source of truth to another as part of an unrelated feature.

---

# Graph Save Safety

Saving, overwriting, duplicating, and recovering graphs must protect existing work.

Do not casually change behavior around:

* Save
* Save As New
* duplicate structure
* overwrite
* concurrent edits
* graph deletion
* recovery

Never overwrite an existing graph when the requested behavior is to create an independent copy.

Preserve existing recovery mechanisms when changing save logic.

Any destructive change to persisted graph data requires an explicit recovery or rollback path.

---

# Exports

Graph image and PDF exports are customer/business artifacts.

Changes to exports must preserve:

* visible graph geometry
* marker placement
* measurements
* legends
* customer information
* readable scaling
* expected attachment behavior

A successful build does not prove an export still looks correct.

Visually inspect affected exports when export code changes.

---

# Mapping and Satellite Trace

Mapping and satellite imagery are tracing aids.

Do not make aerial imagery itself part of the durable graph unless explicitly required.

Preserve separation between:

* temporary/reference imagery
* saved trace geometry
* actual inspection graph objects

Do not introduce paid mapping services, API keys, or a new map provider unless explicitly approved.

---

# Dependencies

Before adding a Flutter/Dart dependency:

1. Confirm Flutter, Dart, or an existing package cannot reasonably solve the requirement.
2. Prefer maintained and focused packages.
3. Avoid duplicate packages for the same function.
4. Consider Flutter Web compatibility.
5. Explain why the dependency is required.

Do not introduce a large package to solve a small problem without justification.

---

# Security

Never commit or expose:

* API keys
* Cloudflare secrets
* authentication secrets
* PestPac credentials
* service tokens
* private provider credentials

Assume Flutter Web client code can be inspected by users.

Client-side UI restrictions are not a replacement for server authorization.

---

# Local Development

Install dependencies with:

```bash
flutter pub get
```

Typical browser development:

```bash
flutter run -d chrome
```

Or use a browser-hosted local server when appropriate:

```bash
flutter run -d web-server --web-port 8787 --web-hostname 127.0.0.1
```

Do not assume a local environment is production-equivalent.

---

# Required Validation

For normal feature work, run:

```bash
flutter analyze
flutter test
flutter build web --release
```

All applicable checks should pass before the change is declared ready.

If a check cannot be run, explain why.

For UI/editor changes, automated tests do not replace manual visual and interaction verification.

---

# UI Verification

For editor or workflow changes, manually verify the behavior affected by the task.

Where relevant, verify:

* creating/opening a graph
* selecting tools
* drawing
* selecting objects
* moving/resizing
* zooming/panning
* markers
* measurements
* saving/reopening
* exporting

Only verify unrelated areas when the change could reasonably affect them.

Do not perform a giant manual regression pass for every tiny change unless risk warrants it.

---

# Deployment

BugMan Graphs currently deploys through GitHub Actions to Cloudflare Pages.

The deployment project is:

`bugman-graphs`

The current workflow builds Flutter Web and publishes `build/web`.

Do not introduce another deployment platform without explicit approval.

## Main branch is production-sensitive

A push to `main` currently triggers the Cloudflare Pages deployment workflow.

Therefore:

* do not perform routine development directly on `main`
* do not merge to `main` without explicit authorization
* do not push directly to `main` as a testing method
* use a dedicated task branch
* validate before merge

Treat merging to `main` as a deployment-affecting action.

---

# Git and Pull Requests

Use a dedicated branch for each task.

Do not reuse old branches for unrelated work.

Before committing:

* inspect the diff
* confirm only intended files changed
* avoid unrelated generated files
* avoid dependency-lock changes unless required

Pull requests should explain:

## What changed

The implementation.

## Why

The field/business problem being solved.

## Validation

Exactly which analyze/test/build checks were run.

## Manual verification

Which editor or workflow behavior should be tested.

## Data compatibility

Whether saved graph format, markers, measurements, attachments, or APIs changed.

## OpsBrain impact

Any required API or integration changes.

## Deployment requirements

Any Cloudflare configuration, secrets, or other production requirements.

## Not in scope

Important related behavior intentionally left unchanged.

Do not merge without explicit authorization.

---

# Review Rules

Review changes for:

## Graph compatibility

Can existing saved graphs still open correctly?

## Data loss

Could graph objects, attachments, markers, or measurements disappear?

## Editor regressions

Did fixing one tool break another?

## Geometry regressions

Did appearance changes affect measurement or coordinates?

## Customer identity

Was Bill-To / Location compatibility preserved?

## Architecture drift

Did the change introduce an unnecessary framework, data store, or provider?

## OpsBrain coupling

Is Graphs using a stable API or depending on implementation details?

## SalesBrain compatibility

Can structured graph data still be consumed downstream?

## Security

Were secrets or privileged operations moved into client code?

## Deployment risk

Could the change deploy merely because it reaches `main`?

## Missing verification

Were appropriate Flutter checks and manual interaction tests performed?

---

# Decision Priority

When multiple solutions work, prefer:

1. Protect saved graph data.
2. Protect drawing and measurement correctness.
3. Protect field usability.
4. Preserve structured inspection information.
5. Preserve OpsBrain and SalesBrain integration.
6. Preserve Bill-To / Location and future PestPac compatibility.
7. Keep Flutter/Dart architecture simple.
8. Reuse existing APIs and patterns.
9. Minimize new dependencies and technology.
10. Reduce future maintenance burden.

If a requested change conflicts with these rules, explain the risk and recommend the safer approach rather than silently redesigning the application.
