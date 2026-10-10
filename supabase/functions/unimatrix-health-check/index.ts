Deno.serve(() => new Response(
  JSON.stringify({ok:false, disabled:true}),
  {status:410, headers:{"content-type":"application/json"}}
));