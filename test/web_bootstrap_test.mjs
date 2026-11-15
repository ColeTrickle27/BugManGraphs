import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const html=readFileSync(new URL('../web/index.html',import.meta.url),'utf8');
const bootstrap=readFileSync(new URL('../web/flutter_bootstrap.js',import.meta.url),'utf8')
 .replace('{{flutter_js}}','').replace('{{flutter_build_config}}','').replace('{{flutter_service_worker_version}}',"'synthetic'");
function fixture(load){
 const elements=new Map(['bugman-startup','bugman-startup-title','bugman-startup-message','bugman-startup-reload'].map(id=>[id,{textContent:'',hidden:true,remove(){elements.delete(id);}}]));
 const listeners={};let timeout;let reloads=0;
 const window={location:{href:'https://graphs.example/?graph=SYNTHETIC-KEY',reload(){reloads++;}},addEventListener:(name,fn)=>listeners[name]=fn};
 const context={window,document:{getElementById:id=>elements.get(id)},setTimeout:fn=>{timeout=fn;return 1;},clearTimeout:()=>{},console:{error:()=>{}},_flutter:{buildConfig:{builds:[{mainJsPath:'main.dart.js'}]},loader:{load}}};
 vm.runInNewContext(html.match(/<script>\s*(\(\(\) => \{\s*let complete[\s\S]*?)<\/script>/)[1],context);
 return{context,elements,listeners,slow:()=>timeout(),reloads:()=>reloads};
}
test('slow startup and script failure expose reload without changing graph key',()=>{
 const f=fixture(()=>Promise.resolve());f.slow();assert.match(f.elements.get('bugman-startup-title').textContent,/Still opening/);assert.equal(f.elements.get('bugman-startup-reload').hidden,false);
 f.listeners.error({target:{tagName:'SCRIPT'}});assert.match(f.elements.get('bugman-startup-title').textContent,/could not open/);f.context.window.location.reload();assert.equal(f.reloads(),1);assert.match(f.context.window.location.href,/graph=SYNTHETIC-KEY$/);
});
test('engine initialization failure shows recovery; successful run removes loading UI',async()=>{
 for(const fails of [true,false]){
  const f=fixture(async options=>{assert.equal(options.config.canvasKitBaseUrl,'canvaskit/');await options.onEntrypointLoaded({initializeEngine:async()=>{if(fails)throw Error('synthetic failure');return{runApp:async()=>{}};}});});
  vm.runInNewContext(bootstrap,f.context);await new Promise(resolve=>setImmediate(resolve));
  if(fails)assert.match(f.elements.get('bugman-startup-title').textContent,/could not open/);else{assert.equal(f.elements.has('bugman-startup'),false);f.listeners.error({target:{tagName:'SCRIPT'}});f.listeners.unhandledrejection();assert.equal(f.elements.has('bugman-startup'),false);}
 }
});
test('entrypoint loader rejection shows recovery',async()=>{
 const f=fixture(()=>Promise.reject(Error('synthetic entrypoint failure')));vm.runInNewContext(bootstrap,f.context);await new Promise(resolve=>setImmediate(resolve));assert.match(f.elements.get('bugman-startup-title').textContent,/could not open/);
});

test('unhandled startup dependency rejection offers recovery before engine callback',()=>{
 const f=fixture(()=>Promise.resolve());f.listeners.unhandledrejection();assert.match(f.elements.get('bugman-startup-title').textContent,/could not open/);assert.equal(f.elements.get('bugman-startup-reload').hidden,false);
});
