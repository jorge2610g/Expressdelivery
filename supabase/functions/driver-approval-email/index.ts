import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': 'https://expressviajes.online',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const escapeHtml = (value: string) =>
  value.replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[character] ?? character);

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (request.method !== 'POST') {
    return Response.json(
      { error: 'Method not allowed' },
      { status: 405, headers: corsHeaders },
    );
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const resendApiKey = Deno.env.get('RESEND_API_KEY');
  const from = Deno.env.get('DRIVER_APPROVAL_EMAIL_FROM');
  if (!supabaseUrl || !serviceRoleKey || !resendApiKey || !from) {
    return Response.json(
      { error: 'Approval email service is not configured' },
      { status: 503, headers: corsHeaders },
    );
  }

  const authHeader = request.headers.get('authorization') ?? '';
  if (authHeader !== `Bearer ${serviceRoleKey}`) {
    return Response.json(
      { error: 'Unauthorized' },
      { status: 401, headers: corsHeaders },
    );
  }

  let payload: { outbox_id?: string };
  try {
    payload = await request.json();
  } catch {
    return Response.json(
      { error: 'Invalid JSON body' },
      { status: 400, headers: corsHeaders },
    );
  }
  if (!payload.outbox_id || !/^[0-9a-f-]{36}$/i.test(payload.outbox_id)) {
    return Response.json(
      { error: 'Invalid outbox id' },
      { status: 400, headers: corsHeaders },
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: event, error: loadError } = await supabase
    .from('driver_approval_email_outbox')
    .select('id,recipient_email,recipient_name,sent_at')
    .eq('id', payload.outbox_id)
    .maybeSingle();

  if (loadError || !event) {
    return Response.json(
      { error: 'Approval email event not found' },
      { status: 404, headers: corsHeaders },
    );
  }
  if (event.sent_at) {
    return Response.json(
      { ok: true, already_sent: true },
      { headers: corsHeaders },
    );
  }

  const name = escapeHtml(event.recipient_name || 'Conductor');
  const textBody =
    `Hola ${event.recipient_name || 'Conductor'}, tu registro como conductor de Express fue aprobado. Descarga la aplicación oficial en https://play.google.com/store/apps/details?id=com.express.usuario1 e inicia sesión con la misma cuenta que usaste para registrarte.`;
  const htmlBody =
    `<p>Hola ${name},</p><p>Tu registro como conductor de Express fue aprobado.</p><p>Descarga la aplicación oficial y entra con la misma cuenta que usaste para registrarte:</p><p><a href="https://play.google.com/store/apps/details?id=com.express.usuario1">Descargar Express</a></p>`;

  const result = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${resendApiKey}`,
      'Content-Type': 'application/json',
      'Idempotency-Key': `driver-approval-${event.id}`,
    },
    body: JSON.stringify({
      from,
      to: [event.recipient_email],
      subject: 'Tu registro de conductor fue aprobado',
      text: textBody,
      html: htmlBody,
    }),
  });

  if (!result.ok) {
    const detail = (await result.text()).slice(0, 1000);
    await supabase.from('driver_approval_email_outbox').update({
      attempts: 1,
      last_error: detail,
    }).eq('id', event.id);
    return Response.json(
      { error: 'Email provider rejected the message' },
      { status: 502, headers: corsHeaders },
    );
  }

  const { error: markError } = await supabase
    .from('driver_approval_email_outbox')
    .update({
      sent_at: new Date().toISOString(),
      attempts: 1,
      last_error: null,
    })
    .eq('id', event.id)
    .is('sent_at', null);

  if (markError) {
    return Response.json(
      { error: 'Email sent but event could not be marked as delivered' },
      { status: 500, headers: corsHeaders },
    );
  }

  return Response.json({ ok: true }, { headers: corsHeaders });
});
