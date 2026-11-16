{{flutter_js}}
{{flutter_build_config}}

// Keep the production editor from reusing a prior release's stable
// main.dart.js URL. Flutter's generated service worker and the browser cache
// can otherwise keep an older Graphs build alive for hours after deployment.
const bugManRelease = '20261116-imagery-acreage';
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath = `${build.mainJsPath}?release=${bugManRelease}`;
  }
}

const config = { canvasKitBaseUrl: 'canvaskit/' };

_flutter.loader.load({
  config,
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
    serviceWorkerUrl: `flutter_service_worker.js?release=${bugManRelease}`,
  },
  onEntrypointLoaded: async (engineInitializer) => {
    try {
      const runner = await engineInitializer.initializeEngine(config);
      await runner.runApp();
      window.bugManStartup?.complete();
    } catch (error) {
      console.error('BugMan Graphs startup failed', error);
      window.bugManStartup?.fail();
    }
  },
}).catch((error) => {
  console.error('BugMan Graphs loader failed', error);
  window.bugManStartup?.fail();
});
