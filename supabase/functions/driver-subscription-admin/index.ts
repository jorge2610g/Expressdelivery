import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-retry-count, traceparent, tracestate, baggage',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(body: unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...corsHeaders,'Content-Type':'application/json'}})}
function serviceKey(){const legacy=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');if(legacy)return legacy;const raw=Deno.env.get('SUPABASE_SECRET_KEYS');if(!raw)throw new Error('No hay clave de servicio');const parsed=JSON.parse(raw);if(!parsed.default)throw new Error('No hay secret key default');return parsed.default}
async function assertAdmin(req:Request){
  const authorization=req.headers.get('authorization')??'';
  if(!authorization.startsWith('Bearer '))throw new Error('Sesión administrativa requerida');
  const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data,error}=await client.rpc('is_admin');if(error||data!==true)throw new Error('No autorizado');
  const {data:u,error:ue}=await client.auth.getUser();if(ue||!u.user)throw new Error('Sesión inválida');return u.user;
}
Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:corsHeaders});
  if(req.method!=='POST')return json({error:'Método no permitido'},405);
  try{
    const caller=await assertAdmin(req);
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,serviceKey(),{auth:{persistSession:false,autoRefreshToken:false}});
    const body=await req.json().catch(()=>({}));const action=String(body.action||'get');
    if(action==='get'){
      const {data:cfg,error}=await admin.rpc('service_get_driver_subscription_provider_settings');if(error)throw error;
      return json({ok:true,configured:!!(cfg?.api_base_url&&cfg?.create_path&&cfg?.status_path&&cfg?.username&&cfg?.password),settings:{
        api_base_url:cfg?.api_base_url||'',create_path:cfg?.create_path||'',status_path:cfg?.status_path||'',username:cfg?.username||'',
        has_password:!!cfg?.password,has_secret_key:!!cfg?.secret_key,extra_config:cfg?.extra_config||{}
      }});
    }
    if(action==='save'){
      const {error}=await admin.rpc('service_set_driver_subscription_provider_settings',{
        p_api_base_url:String(body.api_base_url||''),p_create_path:String(body.create_path||''),p_status_path:String(body.status_path||''),
        p_username:String(body.username||''),p_password:String(body.password||''),p_secret_key:String(body.secret_key||''),
        p_extra_config:body.extra_config&&typeof body.extra_config==='object'?body.extra_config:{},p_updated_by:caller.id
      });if(error)throw error;
      return json({ok:true});
    }
    return json({error:'Acción no soportada'},400);
  }catch(error){console.error('driver-subscription-admin',error);return json({ok:false,error:error instanceof Error?error.message:String(error)},500)}
});
