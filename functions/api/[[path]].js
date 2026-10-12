import {createGraphRelay} from '../../relay/graph-relay.mjs';
const relay=createGraphRelay();
export function onRequest({request,env}) {
  if(env.GRAPH_DRAFTS_RELAY_ENABLED!=='true') return Response.json({error:'Account drafts are unavailable.'},{status:404,headers:{'Cache-Control':'private, no-store'}});
  return relay(request);
}
