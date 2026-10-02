import { createClient } from 'npm:@supabase/supabase-js@2';

const VERIPAGOS_BASE_URL = 'https://veripagos.com';
const VERIPAGOS_CREATE_PATH = '/api/bcp/generar-qr';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-retry-count, traceparent, tracestate, baggage',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown,status=200){
  return new Response(JSON.stringify(body),{
    status,
    headers:{...corsHeaders,'Content-Type':'application/json'},
  });
}

function serviceKey(){
  const legacy=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(legacy)return legacy;
  const raw=Deno.env.get('SUPABASE_SECRET_KEYS');
  if(!raw)throw new Error('No hay clave de servicio');
  const parsed=JSON.parse(raw);
  if(!parsed.default)throw new Error('No hay secret key default');
  return parsed.default;
}

async function assertAdmin(req:Request){
  const authorization=req.headers.get('authorization')??'';
  if(!authorization.startsWith('Bearer ')){
    throw new Error('Sesión administrativa requerida');
  }
  const client=createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    {
      global:{headers:{Authorization:authorization}},
      auth:{persistSession:false,autoRefreshToken:false},
    },
  );
  const {data,error}=await client.rpc('is_admin');
  if(error||data!==true)throw new Error('No autorizado');
  const {data:u,error:ue}=await client.auth.getUser();
  if(ue||!u.user)throw new Error('Sesión inválida');
  return u.user;
}

async function verifyVeriPagosCredentials(
  username:string,
  password:string,
  secretKey:string,
){
  if(!username||!password||!secretKey){
    throw new Error('Completa usuario, contraseña y Secret Key');
  }

  const response=await fetch(
    VERIPAGOS_BASE_URL+VERIPAGOS_CREATE_PATH,
    {
      method:'POST',
      headers:{
        'Authorization':'Basic '+btoa(username+':'+password),
        'Content-Type':'application/json',
        'Accept':'application/json',
      },
      body:JSON.stringify({
        secret_key:secretKey,
        monto:0,
        data:[],
        vigencia:'0/00:01',
        uso_unico:true,
        detalle:'Express - prueba de conexión',
      }),
    },
  );

  const raw=await response.text();
  let data:any={};
  try{data=raw?JSON.parse(raw):{};}catch{data={raw};}

  if(!response.ok){
    throw new Error(
      data?.Mensaje ||
      data?.message ||
      ('VeriPagos respondió HTTP '+response.status)
    );
  }

  if(Number(data?.Codigo)!==0){
    throw new Error(data?.Mensaje || 'VeriPagos rechazó las credenciales');
  }

  if(!data?.Data?.movimiento_id || !data?.Data?.qr){
    throw new Error('VeriPagos respondió sin movimiento_id o QR');
  }

  return {
    movimiento_id:String(data.Data.movimiento_id),
    mensaje:String(data?.Mensaje || 'Conexión verificada'),
  };
}

Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS'){
    return new Response('ok',{headers:corsHeaders});
  }
  if(req.method!=='POST'){
    return json({error:'Método no permitido'},405);
  }

  try{
    const caller=await assertAdmin(req);
    const admin=createClient(
      Deno.env.get('SUPABASE_URL')!,
      serviceKey(),
      {auth:{persistSession:false,autoRefreshToken:false}},
    );

    const body=await req.json().catch(()=>({}));
    const action=String(body.action||'get');

    if(action==='get'){
      const {data:cfg,error}=await admin.rpc(
        'service_get_driver_subscription_provider_settings'
      );
      if(error)throw error;

      const credentialsConfigured=!!(
        cfg?.username &&
        cfg?.password &&
        cfg?.secret_key
      );
      const verified=credentialsConfigured && !!cfg?.extra_config?.verified_at;

      return json({
        ok:true,
        configured:verified,
        credentials_configured:credentialsConfigured,
        verified,
        verification_ready:credentialsConfigured,
        status_endpoint_ready:!!cfg?.status_path,
        settings:{
          username:cfg?.username||'',
          has_password:!!cfg?.password,
          has_secret_key:!!cfg?.secret_key,
        },
      });
    }

    if(action==='save_and_verify'){
      const currentRes=await admin.rpc(
        'service_get_driver_subscription_provider_settings'
      );
      if(currentRes.error)throw currentRes.error;
      const current=currentRes.data||{};

      const username=String(body.username||current.username||'').trim();
      const password=String(body.password||current.password||'');
      const secretKey=String(body.secret_key||current.secret_key||'');

      const verification=await verifyVeriPagosCredentials(
        username,
        password,
        secretKey,
      );

      const {error}=await admin.rpc(
        'service_set_driver_subscription_provider_settings',
        {
          p_api_base_url:VERIPAGOS_BASE_URL,
          p_create_path:VERIPAGOS_CREATE_PATH,
          p_status_path:String(current.status_path||''),
          p_username:username,
          p_password:password,
          p_secret_key:secretKey,
          p_extra_config:{
            amount_key:'monto',
            description_key:'detalle',
            validity_key:'vigencia',
            data_key:'data',
            unique_use_key:'uso_unico',
            secret_body_key:'secret_key',
            qr_keys:['qr'],
            movement_keys:['movimiento_id'],
            create_method:'POST',
            provider_response_code_key:'Codigo',
            provider_response_message_key:'Mensaje',
            verified_at:new Date().toISOString(),
            test_movement_id:verification.movimiento_id,
          },
          p_updated_by:caller.id,
        },
      );
      if(error)throw error;

      return json({
        ok:true,
        connected:true,
        message:verification.mensaje,
        test_movement_id:verification.movimiento_id,
      });
    }

    if(action==='verify'){
      const {data:cfg,error}=await admin.rpc(
        'service_get_driver_subscription_provider_settings'
      );
      if(error)throw error;

      const verification=await verifyVeriPagosCredentials(
        String(cfg?.username||''),
        String(cfg?.password||''),
        String(cfg?.secret_key||''),
      );

      const extra={
        ...(cfg?.extra_config||{}),
        verified_at:new Date().toISOString(),
        test_movement_id:verification.movimiento_id,
      };

      const {error:saveError}=await admin.rpc(
        'service_set_driver_subscription_provider_settings',
        {
          p_api_base_url:VERIPAGOS_BASE_URL,
          p_create_path:VERIPAGOS_CREATE_PATH,
          p_status_path:String(cfg?.status_path||''),
          p_username:String(cfg?.username||''),
          p_password:String(cfg?.password||''),
          p_secret_key:String(cfg?.secret_key||''),
          p_extra_config:extra,
          p_updated_by:caller.id,
        },
      );
      if(saveError)throw saveError;

      return json({
        ok:true,
        connected:true,
        message:verification.mensaje,
        test_movement_id:verification.movimiento_id,
      });
    }

    return json({error:'Acción no soportada'},400);
  }catch(error){
    console.error('driver-subscription-admin',error);
    return json({
      ok:false,
      connected:false,
      error:error instanceof Error?error.message:String(error),
    },500);
  }
});
