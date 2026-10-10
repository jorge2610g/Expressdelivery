// Retired callback: acknowledge without processing credentials or personal data.
Deno.serve((_req:Request)=>new Response(null,{status:204}));
