import {createClient} from 'npm:@supabase/supabase-js@2';

// Wallet top-ups are NEVER finalized by the client. A service-role-only SQL
// function credits an idempotent transaction after independent provider status.
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, apikey, x-client-info, content-type',
  'Access-Control-Allow-Methods': 'POST,OPTIONS',
};
const reply = (value: unknown, code=200) =>
  new Response(JSON.stringify(value),{
    status:code,headers:{...cors,'content-type':'application/json'}
  });
const url = () => Deno.env.get('SUPABASE_URL')!;
function serviceKey() {
  const legacy=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(legacy)return legacy;
  const obj=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}');
  if(!obj.default)throw Error('Servicio de pagos sin credenciales');
  return obj.default;
}
function admin() {
  return createClient(url(),serviceKey(),{
    auth:{persistSession:false,autoRefreshToken:false},
  });
}
function userClient(token:string) {
  return createClient(url(),Deno.env.get('SUPABASE_ANON_KEY')!,{
    global:{headers:{Authorization:'Bearer '+token}},
    auth:{persistSession:false,autoRefreshToken:false},
  });
}
function assertNoError<T>(x:{data:T,error:any}, fallback:string):T {
  if(x.error)throw Error(fallback);
  return x.data;
}
function amountNumber(v:unknown){return Math.round(Number(v)*100)/100;}
function safeCheckout(row:any) {
  return {
    checkout_id:row.id,
    purpose:row.purpose||'wallet_topup',
    amount:row.amount,currency_code:row.currency_code,
    country_code:row.country_code,provider:row.provider,
    status:row.status,checkout_url:row.checkout_url,
    qr_payload:row.qr_payload,
    expires_at:row.expires_at,
  };
}
function providerSettings(row:any,provider:string) {
  if(provider==='mercado_pago') {
    if(row?.provider!=='mercado_pago' || !row.access_token ||
       row.extra_config?.site_id!=='MLC') {
      throw Error('Mercado Pago no está configurado para esta zona');
    }
  } else if (provider==='veripagos') {
    if(!row?.api_base_url || !row.create_path || !row.status_path ||
       !row.username || !row.password || !row.secret_key) {
      throw Error('VeriPagos no tiene credenciales completas');
    }
  } else throw Error('Proveedor no admitido');
  return row;
}
async function getProvider(adminSb:any,row:any) {
  const {data,error}=await adminSb.rpc(
    row.provider==='mercado_pago'
      ? 'service_get_zone_payment_provider_settings'
      : 'service_get_driver_subscription_provider_settings',
    row.provider==='mercado_pago'?{p_zone_id:row.zone_id}:{},
  );
  return providerSettings(assertNoError({data,error},'Pasarela no disponible'),row.provider);
}
const providerUrl=(base:string,path:string)=>
  base.replace(/\/$/,'')+'/'+path.replace(/^\//,'');
const qrHeaders=(cfg:any)=>({
  'content-type':'application/json',
  'accept':'application/json',
  'authorization':'Basic '+btoa(String(cfg.username)+':'+String(cfg.password)),
});
async function makeCheckout(row:any,cfg:any,user:any) {
  if(row.provider==='veripagos'){
    const res=await fetch(providerUrl(cfg.api_base_url,cfg.create_path),{
      method:'POST',headers:qrHeaders(cfg),
      body:JSON.stringify({
        secret_key:cfg.secret_key,
        monto:Number(row.amount),
        data:[{
          source:'express',type:row.purpose==='cancellation_debt'?'cancellation_fee_debt':'driver_wallet_topup',
          checkout_id:row.id,user_id:row.user_id,
        }],
        vigencia:'0/00:15',uso_unico:true,
        detalle:row.purpose==='cancellation_debt'
          ?'Express · Pago deuda de cancelación'
          :'Express · Recarga de billetera',
      }),
    });
    const data=await res.json().catch(()=>({}));
    if(!res.ok || Number(data?.Codigo)!==0 ||
       !data?.Data?.qr || !data?.Data?.movimiento_id){
      throw Error(data?.Mensaje || 'VeriPagos no pudo generar el QR');
    }
    return {provider_order_id:String(data.Data.movimiento_id),
      qr_payload:String(data.Data.qr)};
  }
  const ref='express_wallet:'+row.id;
  const res=await fetch('https://api.mercadopago.com/checkout/preferences',{
    method:'POST',
    headers:{
      Authorization:'Bearer '+String(cfg.access_token),
      'Content-Type':'application/json',
      Accept:'application/json',
    },
    body:JSON.stringify({
      items:[{
        id:row.id,title:row.purpose==='cancellation_debt'
          ?'Pago deuda de cancelación Express'
          :'Recarga Billetera Express',
        quantity:1,currency_id:'CLP',
        unit_price:Number(row.amount),
      }],
      external_reference:ref,
      metadata:{
        source:'express',type:row.purpose==='cancellation_debt'
          ?'cancellation_fee_debt':'wallet_topup',
        checkout_id:row.id,user_id:row.user_id,
      },
      ...(user.email?{payer:{email:user.email}}:{}),
      statement_descriptor:'EXPRESS',
    }),
  });
  const data=await res.json().catch(()=>({}));
  if(!res.ok||!data.id||!data.init_point){
    throw Error(data.message||'Mercado Pago no creó el checkout');
  }
  return {provider_order_id:String(data.id),
    checkout_url:String(data.init_point)};
}
async function inspectPayment(row:any,cfg:any) {
  if(row.provider==='veripagos') {
    const res=await fetch(providerUrl(cfg.api_base_url,cfg.status_path),{
      method:'POST',headers:qrHeaders(cfg),
      body:JSON.stringify({
        secret_key:cfg.secret_key,
        movimiento_id:row.provider_order_id,
      }),
    });
    const data=await res.json().catch(()=>({}));
    if(!res.ok||Number(data.Codigo)!==0)throw Error(
      data.Mensaje||'VeriPagos no respondió');
    const p=data.Data||{};
    const status=String(p.estado||'').trim().toLowerCase();
    const ref=String(p.movimiento_id||'');
    const amount=amountNumber(p.monto);
    if(status==='completado') {
      if(ref!==row.provider_order_id ||
         !Number.isFinite(amount) || amount!==amountNumber(row.amount)){
        throw Error('VeriPagos devolvió un comprobante distinto');
      }
      return {paid:true,reference:ref,amount,currency:'BOB'};
    }
    return {paid:false,rejected:['rechazado','cancelado','vencido','fallido']
      .includes(status)};
  }
  const ref='express_wallet:'+row.id;
  const search='https://api.mercadopago.com/v1/payments/search?'+
    new URLSearchParams({
      external_reference:ref,sort:'date_created',
      criteria:'desc',limit:'10',
    }).toString();
  const res=await fetch(search,{
    headers:{Authorization:'Bearer '+String(cfg.access_token),
      Accept:'application/json'},
  });
  const data=await res.json().catch(()=>({}));
  if(!res.ok)throw Error(data.message||'Mercado Pago no pudo verificar');
  const results=Array.isArray(data.results)?data.results:[];
  const match=results.find((r:any)=>
    r.status==='approved' &&
    String(r.external_reference||'')===ref &&
    String(r.currency_id||'')==='CLP' &&
    amountNumber(r.transaction_amount)===amountNumber(row.amount) &&
    String(r.id||'').length>0,
  );
  if(match)return {paid:true,
    reference:row.provider_order_id,
    amount:amountNumber(match.transaction_amount),currency:'CLP'};
  return {paid:false,rejected:false};
}
Deno.serve(async (req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  if(req.method!=='POST')return reply({ok:false,error:'Método no admitido'},405);
  try {
    const header=req.headers.get('authorization')||'';
    if(!header.startsWith('Bearer '))return reply({
      ok:false,error:'Inicia sesión para pagar'},401);
    const token=header.slice(7);
    const sb=userClient(token),root=admin();
    const {data:{user},error:authError}=await sb.auth.getUser(token);
    if(authError||!user)return reply({ok:false,error:'Sesión inválida'},401);
    // Environment is bound server-side to the account; group membership
    // alone is insufficient to identify Preview accounts.
    const binding=assertNoError(await root
      .from('account_runtime_bindings').select('environment')
      .eq('user_id',user.id).maybeSingle(),
      'No se pudo comprobar el entorno de tu cuenta');
    if(binding?.environment!=='production')
      throw Error('Las recargas reales requieren una cuenta de Producción');

    const body=await req.json().catch(()=>({}));
    const action=String(body.action||'');
    if(action==='create'){
      const purpose=body.purpose==='cancellation_debt'
        ?'cancellation_debt':'wallet_topup';
      const account=assertNoError(await root.from('users')
        .select('active_mode,account_status,phone')
        .eq('id',user.id).maybeSingle(),'Cuenta no disponible');
      if(account?.account_status!=='active')throw Error('Cuenta no activa');
      const context=assertNoError(await sb.rpc('current_operating_context'),
        'No se pudo determinar la zona');
      if(!context?.zone_id||!['BO','CL'].includes(context.country_code))
        throw Error('Zona o país no compatible con pagos');
      const {data:isPreview,error:isPreviewErr}=await root.rpc(
        'is_active_audit_user',{p_user_id:user.id});
      if(isPreviewErr || isPreview!==false)
        throw Error('Los pagos reales no están disponibles en Preview');
      let amount=0;
      let debtIds:string[]=[];
      if(purpose==='cancellation_debt'){
        const debts=assertNoError(await root.from('cancellation_fee_debts')
          .select('id,amount,created_at').eq('user_id',user.id)
          .eq('channel','production')
          .eq('country_code',context.country_code).is('paid_at',null)
          .order('created_at',{ascending:true}),
          'No se pudieron consultar las deudas');
        for(const debt of debts||[]){
          const value=amountNumber(debt.amount);
          if(value<=0)continue;
          if(value>5000)throw Error('Una deuda supera el máximo permitido de 5.000. Contacta con soporte.');
          if(amount+value>5000)break;
          amount=amountNumber(amount+value);
          debtIds.push(String(debt.id));
        }
        if(!debtIds.length||amount<=0)throw Error('No tienes deudas de cancelación pendientes en esta zona');
      }else{
        amount=amountNumber(body.amount);
        if(!Number.isFinite(amount)||amount<1||amount>5000)
          throw Error('Monto permitido: entre 1 y 5.000 de la moneda local');
      }
      let profile:any=null;
      if(purpose==='wallet_topup'){
        profile=assertNoError(await root.from('driver_profiles')
          .select('approval_status,zone_id').eq('id',user.id).maybeSingle(),
          'Perfil no disponible');
        const isApprovedDriver=profile?.approval_status==='approved'&&
          !!profile?.zone_id&&account?.active_mode==='driver';
        if(isApprovedDriver&&context.zone_id!==profile.zone_id)
          throw Error('La zona activa no coincide con la del conductor');
        if(!isApprovedDriver){
          const adminDebt=assertNoError(await root
            .from('admin_wallet_adjustment_debts').select('id')
            .eq('user_id',user.id).eq('country_code',context.country_code)
            .eq('channel','production').gt('remaining_amount',0).limit(1),
            'No se pudo comprobar el saldo pendiente');
          if(!adminDebt?.length)throw Error(
            'La recarga está disponible para conductores habilitados o para regularizar un ajuste pendiente');
        }
        if(!/^\+[0-9]{7,15}$/.test(String(account.phone||'')))
          throw Error('Completa tu teléfono antes de recargar');
      }
      const provider=context.country_code==='BO'?'veripagos':'mercado_pago';
      const skeleton={
        user_id:user.id,zone_id:context.zone_id,
        country_code:context.country_code,channel:'production',
        currency_code:context.currency_code,provider,amount,purpose,
        cancellation_debt_ids:debtIds,
      };
      if((provider==='veripagos'&&context.currency_code!=='BOB')||
         (provider==='mercado_pago'&&context.currency_code!=='CLP'))
        throw Error('La moneda no coincide con la zona');
      const pending=assertNoError(await root
        .from('wallet_gateway_checkouts').select('*')
        .eq('user_id',user.id).eq('status','pending')
        .order('created_at',{ascending:false}).limit(1),
        'No se pudo comprobar pagos pendientes');
      if((pending||[]).length){
        const existing=pending[0];
        if(existing.purpose===purpose &&
           existing.country_code===context.country_code &&
           existing.currency_code===context.currency_code &&
           (existing.checkout_url || existing.qr_payload)){
          return reply({ok:true,...safeCheckout(existing),reused:true});
        }
        if(existing.purpose===purpose &&
           (existing.country_code!==context.country_code ||
            existing.currency_code!==context.currency_code)){
          throw Error('Tienes un pago pendiente en otra moneda o zona. Revísalo desde Pagos y billetera antes de iniciar otro.');
        }
        throw Error(existing.purpose==='cancellation_debt'
          ?'Ya tienes un pago de deuda pendiente. Revísalo desde Pagos y billetera antes de iniciar otro.'
          :'Ya tienes una recarga pendiente. Revísala desde Pagos y billetera antes de iniciar otro.');
      }
      const cfg=await getProvider(root,skeleton);
      const created=assertNoError(await root
        .from('wallet_gateway_checkouts').insert(skeleton).select('*')
        .single(),'No se pudo crear el pago');
      try {
        const payment=await makeCheckout(created,cfg,user);
        const saved=assertNoError(await root
          .from('wallet_gateway_checkouts')
          .update(payment).eq('id',created.id).eq('status','pending')
          .select('*').single(),'No se pudo guardar el pago');
        return reply({ok:true,...safeCheckout(saved)});
      }catch(e){
        await root.from('wallet_gateway_checkouts')
          .update({status:'failed'}).eq('id',created.id).eq('status','pending');
        throw e;
      }
    }
    if(action==='status'||action==='pending'){
      if(action==='pending'){
        const {data,error}=await root.from('wallet_gateway_checkouts')
          .select('*').eq('user_id',user.id).eq('status','pending')
          .order('created_at',{ascending:false}).limit(1);
        if(error)throw Error('No se pudo recuperar la recarga');
        return reply({ok:true,checkout:data?.length?safeCheckout(data[0]):null});
      }
      const id=String(body.checkout_id||'');
      if(!/^[0-9a-f-]{36}$/i.test(id))throw Error('Pago inválido');
      const row=assertNoError(await root
        .from('wallet_gateway_checkouts').select('*')
        .eq('id',id).eq('user_id',user.id).maybeSingle(),
        'No se pudo consultar recarga');
      if(!row)throw Error('Recarga no encontrada');
      if(row.status==='paid')return reply({ok:true,approved:true,
        ...safeCheckout(row)});
      if(row.status!=='pending')return reply({ok:true,approved:false,
        ...safeCheckout(row)});
      if(!row.provider_order_id)throw Error('Pago aún no iniciado');
      const cfg=await getProvider(root,row);
      const result=await inspectPayment(row,cfg);
      if(result.paid){
        const finalizeRpc=row.purpose==='cancellation_debt'
          ?'service_finalize_verified_cancellation_debt_gateway'
          :'service_finalize_verified_wallet_gateway';
        const settled=assertNoError(await root.rpc(finalizeRpc,{
          p_checkout_id:row.id,
          p_provider_order_id:result.reference,
          p_verified_amount:result.amount,
          p_verified_currency:result.currency,
        }), row.purpose==='cancellation_debt'
          ?'No se pudo confirmar el pago de la deuda'
          :'No se pudo acreditar el pago confirmado');
        return reply({ok:true,approved:settled.paid===true,
          ...safeCheckout({...row,status:'paid'})});
      }
      if(result.rejected){
        await root.from('wallet_gateway_checkouts')
          .update({status:'failed'}).eq('id',row.id).eq('status','pending');
      }
      return reply({ok:true,approved:false,
        ...safeCheckout({...row,status:result.rejected?'failed':'pending'})});
    }
    return reply({ok:false,error:'Acción desconocida'},400);
  }catch(e) {
    // Never include provider credentials or bearer tokens in the response.
    const error=e instanceof Error?e.message:'No se pudo procesar el pago';
    console.error('driver-wallet-gateway failed',error);
    return reply({ok:false,error},400);
  }
});
