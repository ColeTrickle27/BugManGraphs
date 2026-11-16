# BugManGraphs

Independent Flutter graphing, measurements, and site-plan app for Holloman Exterminators.

Canonical repository: https://github.com/ColeTrickle27/BugManGraphs. A future inspection app will have its own name and repository. Existing graph markers, photos, and saved-file formats remain supported.

OpsBrain is the operations hub; SalesBrain owns sales workflows; Inventory owns inventory; holloman-mcp and shared APIs provide integrations. Existing authenticated OpsBrain API endpoints remain in use during the staged separation. Do not copy another app's source into this repository.

The app currently focuses on the graph editor workflow:

- Home / Job List
- New Job
- Graph Canvas
- Drawing/editing tools for walls, property lines, shapes, markers, photos, and text

## Production site

BugMan Graphs is served through Cloudflare Pages.

Live URL:

```text
https://graphs.holloman-ext.com/
```

The GitHub Actions workflow in `.github/workflows/deploy-cloudflare.yml`
builds and publishes `build/web` when `main` changes. An approved direct
release uses the same Cloudflare Pages project:

```sh
npx --yes wrangler pages deploy build/web --project-name=bugman-graphs --branch=main
```

## OpsBrain sign-in and saving

Open Graphs through OpsBrain's `/bugman-graphs/` link to use the same signed-in environment. The standalone Graphs site connects to `https://ops.holloman-ext.com`; a Preview sign-in does not authenticate that Production host.

When an online save requires sign-in, Graphs keeps the local saved copy and offers **Sign in in new tab**. Keep the graph tab open, sign in separately, then return and Save again. The open drawing, unfinished line, and photos remain in place. Satellite address search uses the same separate-tab recovery without clearing its address or trace points. **OpsBrain Home** in the job list and New Job headers also opens separately.

New Job and Edit Job use the SalesBrain customer-field order. **Existing Customer** requires a permanent selection from `/api/customer-identity/search`; **New Customer** permits an unnamed, unassigned graph draft. Contact/address details are stored as an optional `customer.intakeDetails` snapshot, with existing name/address fields retained for older graphs. Graphs does not create or update the canonical customer record. The standalone host requires OpsBrain's trusted-origin CORS support for the identity-search route before deploying this client.

## Local setup

Use Flutter **3.47.9**, the version pinned in both checking and deployment workflows. Confirm it with `flutter --version` before validation. Upgrade the SDK deliberately with affected checks rather than following a floating stable release.

Run the app locally with Flutter:

```sh
flutter pub get
flutter run -d chrome
```

For a browser URL without opening Chrome automatically:

```sh
flutter run -d web-server --web-port 8787 --web-hostname 127.0.0.1
```

Then open:

```text
http://localhost:8787
```

## Satellite trace setup

The Trace workspace is limited to North Carolina locations. NC OneMap's latest
statewide orthoimagery supplies the aerial tracing surface. The web app sends
authenticated address searches to OpsBrain's
`/api/bugman-graphs/address-suggestions` endpoint and validates the selected
address through `/api/bugman-graphs/address-selection`.

OpsBrain calls Google Places API (New) and Address Validation on the server.
Administrators must configure those APIs in a billed Google Cloud project and
store `GOOGLE_ADDRESS_API_KEY` as an encrypted OpsBrain secret, restricted to
those APIs. No provider key belongs in Flutter, browser assets or build-time
client configuration. See the [OpsBrain address setup](https://github.com/ColeTrickle27/holloman-ops-brain#bugman-graphs-address-suggestions).

Choose a suggestion to use its standardized address. The service reports whether
the coordinate is property-level or approximate and whether the result needs
review; it rejects addresses outside North Carolina. These results are tracing
aids, not verified field measurements. Address search requires an authorized
OpsBrain session; the standalone host uses `https://ops.holloman-ext.com`, while
the `/bugman-graphs/` mount uses its current origin.

Trace a yard boundary, then use **Exclude area** to draw and label homes,
buildings, driveways, or other areas to deduct. Choose a boundary or exclusion
chip to edit its corners; the chip's delete button removes an exclusion.
The workspace shows total, excluded, and net yard acreage. On phones, the
**Trace options** sliders button contains the imagery toggle, and **?** opens
tracing help. Boundary and exclusion chips scroll horizontally to keep the map
visible. Exclusions must be
fully inside the boundary and cannot overlap or touch each other. Crossing
edges and incomplete polygons must be corrected before saving.

Select **Include satellite imagery in graph and exports** to transfer a bounded
NC OneMap snapshot along with the scaled outlines. The snapshot keeps provider
attribution, survives saving/reopening offline, and moves/rotates with the trace.
PNG/PDF exports include the photo, exclusions, and acreage summary. Traces with
imagery or exclusions use the rendered diagram in the PDF to preserve alignment;
other graphs retain vector diagrams. No new provider, API key, or backend route
is required. Transfer failures preserve the open trace for retry or outline-only
save. Acreage is a map-derived estimate, not a survey or treatment recommendation.

Optional `exclusions` and `imagery` trace fields extend the saved graph without
changing existing fields or customer identity; older graphs load with neither.

Each new trace stores its selected address as optional trace metadata. **Add new trace** defaults to the most recent trace address, including after reopening the graph; older graphs without this field fall back to the job address. Editing an existing trace uses that trace's own saved address. This does not change customer identity or measured geometry.

## Validation

Before pushing feature work, run:

```sh
flutter analyze
flutter test
flutter build web --release
```

## Standalone satellite preview

Build the review app with `python3 tool/build_satellite_preview.py` (Flutter must
be on PATH). This opens the sample tracer directly and offers **Start a new
property** after returning to the preview menu. Graphs stay in memory and the
preview cannot write customer records.

Publish the output only to a Pages preview branch, including its `_worker.js`,
`_routes.json`, and `_headers` files. The worker supplies a same-origin,
North-Carolina-only public Census address lookup for this preview; it does not
call protected OpsBrain APIs. Census locations are approximate and require
review. Production continues to use the authenticated address service.

The preview shows startup/download errors, uses versioned JavaScript, and
unregisters old preview service workers rather than silently loading an older
review build.
