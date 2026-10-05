import { createClient } from 'npm:@supabase/supabase-js@2';
import { createRemoteJWKSet, jwtVerify } from 'npm:jose@5';

const allowedRepository = 'jorge2610g/Expressdelivery';
const expectedAudience = 'supabase-express-qa-monitor';
const issuer = 'https://token.actions.githubusercontent.com';
const jwks = createRemoteJWKSet(
  new URL('https://token.actions.githubusercontent.com/.well-known/jwks'),
);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {'Content-Type': 'application/json'},
  });
}

async function verifyGithub(req: Request) {
  const auth = req.headers.get('authorization') ?? '';
  if (!auth.startsWith('Bearer ')) throw new Error('Falta token OIDC');
  const token = auth.slice(7);
  const {payload} = await jwtVerify(token, jwks, {
    issuer,
    audience: expectedAudience,
  });

  if (payload.repository !== allowedRepository) {
    throw new Error('Repositorio no autorizado');
  }
  if (payload.ref !== 'refs/heads/main') {
    throw new Error('Rama no autorizada');
  }
  const workflowRef = payload.workflow_ref?.toString() ?? '';
  if (!workflowRef.includes('/.github/workflows/express-qa.yml@refs/heads/main')) {
    throw new Error('Workflow no autorizado');
  }
}

function serviceKey() {
  const legacy = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (legacy) return legacy;
  const raw = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (!raw) throw new Error('No hay clave de servicio disponible');
  const parsed = JSON.parse(raw);
  if (!parsed.default) throw new Error('No hay secret key default');
  return parsed.default;
}

function ts(value: unknown) {
  const n = Date.parse(String(value ?? ''));
  return Number.isFinite(n) ? n : 0;
}

function transientNetwork(message: string) {
  return /failed to fetch|software caused connection abort|connection (reset|closed|refused)|socketexception|timeout|timed out|network is unreachable|clientexception: connection/i.test(message);
}

function keyOf(row: any) {
  return `${row.source ?? ''}|${row.event_name ?? ''}|${String(row.message ?? '').slice(0, 180)}`;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({error: 'Método no permitido'}, 405);

  try {
    await verifyGithub(req);
    const payload = await req.json().catch(() => ({}));
    const minutesRaw = Number(payload.minutes ?? 30);
    const minutes = Math.min(
      Math.max(Number.isFinite(minutesRaw) ? minutesRaw : 30, 5),
      180,
    );
    const since = new Date(Date.now() - minutes * 60_000).toISOString();

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      serviceKey(),
      {auth: {persistSession: false, autoRefreshToken: false}},
    );

    const [
      {data: errors, error: errorsError},
      {data: flows, error: flowsError},
      {count: activeTokens, error: tokenError},
    ] = await Promise.all([
      admin
        .from('app_error_logs')
        .select('created_at,user_id,environment,level,source,event_name,message,app_version,build_number,context')
        .gte('created_at', since)
        .order('created_at', {ascending: false})
        .limit(200),
      admin
        .from('app_flow_events')
        .select('created_at,event_type,entity_type,entity_id,status,metadata')
        .gte('created_at', since)
        .order('created_at', {ascending: false})
        .limit(300),
      admin
        .from('native_push_tokens')
        .select('id', {count: 'exact', head: true})
        .eq('active', true),
    ]);

    if (errorsError) throw errorsError;
    if (flowsError) throw flowsError;
    if (tokenError) throw tokenError;

    const {data: activeGroups, error: groupsError} = await admin
      .from('audit_test_groups')
      .select('id')
      .eq('active', true);
    if (groupsError) throw groupsError;

    const activeGroupIds = (activeGroups ?? [])
      .map((row: any) => row.id?.toString())
      .filter((value: string | undefined) => value);
    let auditUserIds = new Set<string>();
    if (activeGroupIds.length > 0) {
      const {data: auditMembers, error: membersError} = await admin
        .from('audit_test_group_members')
        .select('user_id')
        .eq('enabled', true)
        .in('group_id', activeGroupIds);
      if (membersError) throw membersError;
      auditUserIds = new Set(
        (auditMembers ?? [])
          .map((row: any) => row.user_id?.toString())
          .filter((value: string | undefined) => value),
      );
    }

    const safeErrors = (errors ?? []).map((row: any) => ({
      created_at: row.created_at,
      user_id: row.user_id?.toString() ?? null,
      qa_user: row.user_id ? auditUserIds.has(row.user_id.toString()) : false,
      environment: row.environment,
      level: row.level,
      source: row.source,
      event_name: row.event_name,
      message: String(row.message ?? '').slice(0, 500),
      app_version: row.app_version,
      build_number: row.build_number,
      context: row.context ?? {},
    }));

    const monitorErrors = monitorErrors.filter(
      (row: any) => row.user_id == null || row.qa_user === true,
    );
    const realUserErrors = monitorErrors.filter(
      (row: any) => row.user_id != null && row.qa_user !== true,
    );

    const safeFlows = (flows ?? []).map((row: any) => ({
      created_at: row.created_at,
      event_type: row.event_type,
      entity_type: row.entity_type,
      entity_id: row.entity_id,
      status: row.status,
      metadata: row.metadata ?? {},
    }));

    const confirmed: any[] = [];
    const warnings: any[] = [];
    const transient: any[] = [];

    // Fatal runtime errors are always product failures.
    for (const row of monitorErrors.filter((e: any) => e.level === 'fatal')) {
      confirmed.push({
        code: 'FATAL_RUNTIME',
        at: row.created_at,
        source: row.source,
        event_name: row.event_name,
        message: row.message,
      });
    }

    // One network error may be transient; repeated identical failures are not
    // allowed to disappear from QA evidence.
    const transientRows = monitorErrors.filter((e: any) =>
      transientNetwork(e.message),
    );
    const transientGrouped = new Map<string, any[]>();
    for (const row of transientRows) {
      const key = keyOf(row);
      const list = transientGrouped.get(key) ?? [];
      list.push(row);
      transientGrouped.set(key, list);
    }
    for (const rows of transientGrouped.values()) {
      const first = rows[0];
      if (rows.length >= 3) {
        warnings.push({
          code: 'REPEATED_NETWORK_FAILURE',
          count: rows.length,
          at: first.created_at,
          source: first.source,
          event_name: first.event_name,
          message: first.message,
          evidence: 'same_network_failure_repeated_in_monitor_window',
        });
      } else {
        for (const row of rows) {
          transient.push({
            code: 'TRANSIENT_NETWORK',
            at: row.created_at,
            source: row.source,
            event_name: row.event_name,
            message: row.message,
          });
        }
      }
    }

    // Repeated non-network errors are stronger evidence than one isolated log.
    const grouped = new Map<string, any[]>();
    for (const row of monitorErrors.filter((e: any) =>
      (e.level === 'error' || e.level === 'warning') &&
      !transientNetwork(e.message)
    )) {
      const key = keyOf(row);
      const list = grouped.get(key) ?? [];
      list.push(row);
      grouped.set(key, list);
    }
    for (const rows of grouped.values()) {
      const first = rows[0];
      if (first.event_name === 'LIVE_OFFERS_NOT_MOUNTED') continue;
      if (rows.length >= 3 && first.level === 'error') {
        confirmed.push({
          code: 'REPEATED_APP_ERROR',
          count: rows.length,
          at: first.created_at,
          source: first.source,
          event_name: first.event_name,
          message: first.message,
          evidence: `${first.source ?? ''}|${first.event_name ?? ''}|${String(first.message ?? '').slice(0, 180)}`,
        });
      } else {
        warnings.push({
          code: 'ISOLATED_APP_SIGNAL',
          count: rows.length,
          source: first.source,
          event_name: first.event_name,
          message: first.message,
        });
      }
    }

    // Offer UI regression needs correlation, not just a warning row.
    const offerNotMounted = monitorErrors.filter(
      (e: any) => e.event_name === 'LIVE_OFFERS_NOT_MOUNTED',
    );
    const offerReceived = monitorErrors.filter(
      (e: any) => e.event_name === 'PASSENGER_LIVE_OFFERS_RECEIVED',
    );
    const offerMounted = monitorErrors.filter(
      (e: any) => e.event_name === 'LIVE_OFFERS_CARD_MOUNTED',
    );

    for (const miss of offerNotMounted) {
      const rideId = String(
        miss.context?.live_ride_id ?? miss.context?.data_ride_id ?? '',
      );
      const missTs = ts(miss.created_at);
      const hadFeed = offerReceived.some((r: any) => {
        const rRide = String(r.context?.ride_id ?? '');
        const delta = missTs - ts(r.created_at);
        return rRide === rideId && delta >= 0 && delta <= 20_000;
      });
      const recovered = offerMounted.some((r: any) => {
        const rRide = String(r.context?.ride_id ?? '');
        const delta = ts(r.created_at) - missTs;
        return rRide === rideId && delta >= 0 && delta <= 12_000;
      });
      const liveCount = Number(miss.context?.live_offer_count ?? 0);

      if (hadFeed && liveCount > 0 && !recovered) {
        confirmed.push({
          code: 'LIVE_OFFER_UI_CONFIRMED',
          at: miss.created_at,
          ride_id: rideId,
          live_offer_count: liveCount,
          evidence: 'feed_received_but_card_not_mounted_and_no_recovery',
        });
      } else {
        warnings.push({
          code: 'LIVE_OFFER_UI_RECOVERED_OR_UNCORROBORATED',
          at: miss.created_at,
          ride_id: rideId,
          recovered,
          had_feed: hadFeed,
        });
      }
    }

    // The app logs this event when the same foreground push is surfaced both
    // as an Android notification and inside the app. The user reported this as
    // a duplicate-notification regression, so it must block a clean QA pass.
    const foregroundDoubleSurface = monitorErrors.filter(
      (e: any) => e.event_name === 'FCM_FOREGROUND_SYSTEM_PLUS_IN_APP',
    );
    if (foregroundDoubleSurface.length > 0) {
      const first = foregroundDoubleSurface[0];
      warnings.push({
        code: 'FOREGROUND_DOUBLE_NOTIFICATION_SURFACE',
        count: foregroundDoubleSurface.length,
        at: first.created_at,
        source: first.source,
        event_name: first.event_name,
        message: 'Foreground push produced Android + in-app surfaces.',
        evidence: 'FCM_FOREGROUND_SYSTEM_PLUS_IN_APP',
      });
    }

    // FCM not-delivered needs repetition. A delivered event is positive evidence.
    const fcmNotDelivered = safeFlows.filter(
      (f: any) =>
        f.event_type === 'FCM_DISPATCH_RESULT' &&
        f.status === 'not_delivered',
    );
    if (fcmNotDelivered.length >= 2) {
      confirmed.push({
        code: 'FCM_REPEATED_NOT_DELIVERED',
        count: fcmNotDelivered.length,
      });
    } else if (fcmNotDelivered.length === 1) {
      warnings.push({
        code: 'FCM_SINGLE_NOT_DELIVERED',
        count: 1,
      });
    }

    const verdict = confirmed.length > 0
      ? 'confirmed_product_failure'
      : warnings.length > 0
      ? 'warning'
      : 'healthy';

    const summary = {
      since,
      minutes,
      verdict,
      confirmed_product_failures: confirmed,
      warnings,
      ignored_transient_signals: transient,
      active_push_tokens: activeTokens ?? 0,
      fatal_count: monitorErrors.filter((e: any) => e.level === 'fatal').length,
      error_count: monitorErrors.filter((e: any) => e.level === 'error').length,
      warning_count: monitorErrors.filter((e: any) => e.level === 'warning').length,
      qa_error_count: monitorErrors.length,
      real_user_error_count: realUserErrors.length,
      real_user_production_error_count: realUserErrors.filter(
        (e: any) => e.environment === 'production',
      ).length,
      real_user_preview_error_count: realUserErrors.filter(
        (e: any) => e.environment === 'preview',
      ).length,
      flow_event_count: safeFlows.length,
      fcm_dispatch_count: safeFlows.filter(
        (e: any) => e.event_type === 'FCM_DISPATCH_RESULT',
      ).length,
      recent_errors: monitorErrors.slice(0, 25),
      recent_real_user_errors: realUserErrors.slice(0, 25),
      recent_flow: safeFlows.slice(0, 60),
    };

    return json(summary);
  } catch (error) {
    return json(
      {error: error instanceof Error ? error.message : String(error)},
      401,
    );
  }
});
