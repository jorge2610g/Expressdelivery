Deno.serve(() => new Response(JSON.stringify({
  ok:false,
  code:'disabled'
}), {
  status:410,
  headers:{'Content-Type':'application/json','Cache-Control':'no-store'}
}));