// Retired endpoint: Express now uses manual, administrator-reviewed identity.
// No external API calls, secret reads, session creation or billable operations.
Deno.serve((req:Request) => {
  const cors = {
    'access-control-allow-origin':'*',
    'access-control-allow-headers':'authorization,apikey,content-type,x-client-info',
    'access-control-allow-methods':'POST,GET,OPTIONS',
    'content-type':'application/json',
  };
  if(req.method==='OPTIONS') return new Response(null,{status:204,headers:cors});
  return new Response(JSON.stringify({
    ok:false,code:'manual_identity_required',
    message:'Usa la verificación manual de Express en la versión actualizada.'
  }),{status:410,headers:cors});
});
