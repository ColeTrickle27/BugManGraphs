import {createGraphRelay} from '../../relay/graph-relay.mjs';
export function onRequest({request,env}) {
  if(new URL(request.url).origin!=='https://graphs.holloman-ext.com') return Response.json({error:'Host unavailable.'},{status:404,headers:{'Cache-Control':'private, no-store'}});
  if(env.GRAPH_DRAFTS_RELAY_ENABLED!=='true' || !env.GRAPH_OPS_ACCESS_CLIENT_ID || !env.GRAPH_OPS_ACCESS_CLIENT_SECRET) return Response.json({error:'Account drafts are unavailable.'},{status:503,headers:{'Cache-Control':'private, no-store'}});
  return createGraphRelay({accessClientId:env.GRAPH_OPS_ACCESS_CLIENT_ID,accessClientSecret:env.GRAPH_OPS_ACCESS_CLIENT_SECRET})(request);
}
