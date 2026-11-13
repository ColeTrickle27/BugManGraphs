"""Build a standalone, reproducible Pages preview; does not deploy production."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
from datetime import datetime, timezone

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--flutter', default='flutter')
parser.add_argument('--output', default='build/satellite-preview')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
output = Path(args.output).resolve()
subprocess.run([args.flutter, 'build', 'web', '--release', '--no-pub', '-t',
                'tool/satellite_preview.dart', '--output', str(output)], cwd=root, check=True)

release = datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')
index = output / 'index.html'
html = index.read_text().replace('<title>BugManGraphs</title>', '<title>Satellite acreage preview</title>')
html = html.replace('<body>', '''<body>
<section id="preview-startup" role="status" aria-live="polite" style="position:fixed;inset:0;z-index:99999;display:grid;place-content:center;padding:24px;text-align:center;background:#fff;color:#222;font:18px system-ui">
  <h1 style="font-size:24px">Satellite acreage preview</h1>
  <p id="preview-status">Loading the yard map…</p>
  <p style="font-size:14px">The first visit may take a few seconds.</p>
  <button id="preview-retry" hidden onclick="location.reload()" style="padding:12px;font:inherit">Try again</button>
</section>''')
failure = "document.getElementById('preview-status').textContent='The preview could not download. Check your connection and try again.';document.getElementById('preview-retry').hidden=false"
html = re.sub(r'src="flutter_bootstrap\.js(?:\?[^"]*)?" async',
              lambda match: f'src="flutter_bootstrap.js?preview={release}" async onerror="{failure}"', html)
index.write_text(html)
bootstrap = output / 'flutter_bootstrap.js'
js = bootstrap.read_text()
js = re.sub(r"const bugManRelease = '[^']+';", f'const bugManRelease = {json.dumps(release)};', js)
js = js.rsplit('_flutter.loader.load(', 1)[0] + '''
const startup = document.getElementById('preview-startup');
const status = document.getElementById('preview-status');
const retry = document.getElementById('preview-retry');
function previewFailed(error) {
  console.error('Satellite preview startup failed', error);
  status.textContent = 'The preview could not start. Try this link in Chrome, Edge, or Safari.';
  retry.hidden = false;
}
async function startPreview() {
  // This review app must not reuse an older preview service worker.
  if ('serviceWorker' in navigator) {
    try {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations.map(registration => registration.unregister()));
    } catch (error) { console.warn('Preview cache cleanup unavailable', error); }
  }
  await _flutter.loader.load({
    config: {canvasKitBaseUrl: 'canvaskit/'},
    onEntrypointLoaded: async engineInitializer => {
      try {
        status.textContent = 'Opening the yard map…';
        const runner = await engineInitializer.initializeEngine();
        await runner.runApp();
        startup.remove();
      } catch (error) { previewFailed(error); }
    }
  });
}
startPreview().catch(previewFailed);
'''
bootstrap.write_text(js)
shutil.copyfile(root / 'tool/satellite_preview/worker.mjs', output / '_worker.js')
(output / '_routes.json').write_text(json.dumps({'version': 1, 'include': ['/api/preview/*'], 'exclude': []}))
(output / '_headers').write_text('/*\n  Cache-Control: no-store\n')
print(f'Preview built at {output}; publish to a preview branch only.')
