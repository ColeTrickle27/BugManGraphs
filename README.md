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

The Trace workspace is limited to North Carolina locations. It uses the U.S.
Census Geocoding API for address lookup and NC OneMap's latest statewide
orthoimagery for the aerial tracing surface. No API key, cloud account,
billing, or build-time secret is required.

The imagery is an interactive tracing aid only. Graph exports retain the
scaled trace geometry and measurements without copying the aerial tiles.

Each new trace stores its selected address as optional trace metadata. **Add new trace** defaults to the most recent trace address, including after reopening the graph; older graphs without this field fall back to the job address. Editing an existing trace uses that trace's own saved address. This does not change customer identity or measured geometry.

## Validation

Before pushing feature work, run:

```sh
flutter analyze
flutter test
flutter build web --release
```
