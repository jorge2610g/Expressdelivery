import { createClient, SupabaseClient } from 'npm:@supabase/supabase-js@2';

const MAX_ENTITIES = 250;
const SANDBOX_LOAD_PASSENGER_EMAIL = 'qa-load-passenger@expressdelivery.pro';
const SANDBOX_DRIVER_EMAIL_PREFIX = 'qa-load-driver-';
const PRODUCTION_LOAD_PASSENGER_EMAIL = 'qa-prod-load-passenger@expressdelivery.pro';
const PRODUCTION_DRIVER_EMAIL_PREFIX = 'qa-prod-load-driver-';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {...corsHeaders, 'Content-Type': 'application/json'},
  });
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

function randomPassword() {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '') + 'Aa1!';
}

async function assertAdmin(req: Request) {
  const authorization = req.headers.get('authorization') ?? '';
  if (!authorization.startsWith('Bearer ')) {
    throw new Error('Sesión administrativa requerida');
  }

  const client = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    {
      global: {headers: {Authorization: authorization}},
      auth: {persistSession: false, autoRefreshToken: false},
    },
  );

  const {data, error} = await client.rpc('is_admin');
  if (error || data !== true) throw new Error('No autorizado');

  const {data: userData, error: userError} = await client.auth.getUser();
  if (userError || !userData.user) throw new Error('Sesión inválida');
  return userData.user;
}

async function listAllUsers(admin: SupabaseClient) {
  const users: any[] = [];
  for (let page = 1; page <= 10; page++) {
    const {data, error} = await admin.auth.admin.listUsers({
      page,
      perPage: 1000,
    });
    if (error) throw error;
    users.push(...data.users);
    if (data.users.length < 1000) break;
  }
  return users;
}

async function ensureAuthUser(
  admin: SupabaseClient,
  users: any[],
  email: string,
  metadata: Record<string, unknown>,
) {
  let user = users.find(
    (candidate) => candidate.email?.toLowerCase() === email.toLowerCase(),
  );

  if (!user) {
    const {data, error} = await admin.auth.admin.createUser({
      email,
      password: randomPassword(),
      email_confirm: true,
      user_metadata: metadata,
    });
    if (error) throw error;
    user = data.user;
    if (user) users.push(user);
  } else {
    const {data, error} = await admin.auth.admin.updateUserById(user.id, {
      email_confirm: true,
      user_metadata: {
        ...(user.user_metadata ?? {}),
        ...metadata,
      },
    });
    if (error) throw error;
    user = data.user;
  }

  if (!user) throw new Error('No se pudo crear ' + email);
  return user;
}

function pointAround(
  centerLat: number,
  centerLng: number,
  radiusKm: number,
  index: number,
  count: number,
) {
  const golden = 2.399963229728653;
  const angle = index * golden;
  const radius = radiusKm * Math.sqrt((index + 1) / Math.max(1, count)) * 0.92;
  const northKm = Math.cos(angle) * radius;
  const eastKm = Math.sin(angle) * radius;
  const lat = centerLat + northKm / 111.32;
  const lng = centerLng + eastKm / (111.32 * Math.cos(centerLat * Math.PI / 180));
  return {lat, lng};
}

async function chunks<T>(
  values: T[],
  size: number,
  worker: (value: T, index: number) => Promise<void>,
) {
  for (let offset = 0; offset < values.length; offset += size) {
    const slice = values.slice(offset, offset + size);
    await Promise.all(
      slice.map((value, inner) => worker(value, offset + inner)),
    );
  }
}

async function cleanupRuns(admin: SupabaseClient, runId?: string) {
  let query = admin
    .from('audit_load_test_runs')
    .select('id,status')
    .in('status', ['creating', 'active', 'failed']);
  if (runId) query = query.eq('id', runId);

  const {data: runs, error: runError} = await query;
  if (runError) throw runError;

  let removedRequests = 0;
  let offlineDrivers = 0;

  for (const run of runs ?? []) {
    await admin
      .from('audit_load_test_runs')
      .update({status: 'cleaning', updated_at: new Date().toISOString()})
      .eq('id', run.id);

    const {data: entities, error: entityError} = await admin
      .from('audit_load_test_entities')
      .select('entity_type,user_id,ride_request_id')
      .eq('run_id', run.id);
    if (entityError) throw entityError;

    const rideIds = (entities ?? [])
      .filter((row) => row.entity_type === 'ride_request' && row.ride_request_id)
      .map((row) => row.ride_request_id);
    const driverIds = (entities ?? [])
      .filter((row) => row.entity_type === 'driver' && row.user_id)
      .map((row) => row.user_id);

    if (rideIds.length) {
      const {error} = await admin
        .from('ride_requests')
        .delete()
        .in('id', rideIds);
      if (error) throw error;
      removedRequests += rideIds.length;
    }

    if (driverIds.length) {
      const {error} = await admin
        .from('driver_profiles')
        .update({
          online_status: 'offline',
          updated_at: new Date().toISOString(),
        })
        .in('id', driverIds);
      if (error) throw error;
      offlineDrivers += driverIds.length;
    }

    await admin
      .from('audit_load_test_runs')
      .update({
        status: 'cleaned',
        cleaned_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', run.id);
  }

  return {runs: runs?.length ?? 0, removedRequests, offlineDrivers};
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {headers: corsHeaders});
  }
  if (req.method !== 'POST') return json({error: 'Método no permitido'}, 405);

  try {
    const caller = await assertAdmin(req);
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      serviceKey(),
      {auth: {persistSession: false, autoRefreshToken: false}},
    );

    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? 'seed');
    const requestedScope = String(body.scope ?? 'sandbox').toLowerCase();
    const scope = requestedScope === 'production' ? 'production' : 'sandbox';
    const productionMode = scope === 'production';

    if (action === 'cleanup') {
      const result = await cleanupRuns(
        admin,
        body.run_id ? String(body.run_id) : undefined,
      );
      return json({ok: true, action, ...result});
    }

    if (action !== 'seed') {
      return json({error: 'Acción no soportada'}, 400);
    }

    const driverCount = Math.min(
      MAX_ENTITIES,
      Math.max(1, Number(body.drivers ?? 100) || 100),
    );
    const requestCount = Math.min(
      MAX_ENTITIES,
      Math.max(1, Number(body.requests ?? 100) || 100),
    );
    const centerLat = Number(body.center_latitude ?? -14.8333);
    const centerLng = Number(body.center_longitude ?? -64.9000);
    const radiusKm = Math.min(
      8,
      Math.max(0.5, Number(body.radius_km ?? 3) || 3),
    );

    const cleanup = await cleanupRuns(admin);

    const {data: group, error: groupError} = await admin
      .from('audit_test_groups')
      .select('id,active')
      .eq('slug', 'qa-core')
      .single();
    if (groupError) throw groupError;
    if (!group.active) {
      const {error} = await admin
        .from('audit_test_groups')
        .update({active: true, updated_at: new Date().toISOString()})
        .eq('id', group.id);
      if (error) throw error;
    }

    const {data: run, error: runError} = await admin
      .from('audit_load_test_runs')
      .insert({
        group_id: group.id,
        label: (productionMode ? '[PROD] ' : '[QA] ') +
          'Trinidad ' + driverCount + 'D/' + requestCount + 'S',
        city: 'Trinidad',
        center_latitude: centerLat,
        center_longitude: centerLng,
        radius_km: radiusKm,
        driver_count: driverCount,
        request_count: requestCount,
        status: 'creating',
        created_by: caller.id,
      })
      .select()
      .single();
    if (runError) throw runError;

    const startedAt = performance.now();
    const users = await listAllUsers(admin);

    const passenger = await ensureAuthUser(
      admin,
      users,
      productionMode
        ? PRODUCTION_LOAD_PASSENGER_EMAIL
        : SANDBOX_LOAD_PASSENGER_EMAIL,
      {
        qa_account: true,
        qa_role: 'passenger',
        load_lab: true,
        persistent_load_observer: true,
        load_scope: scope,
      },
    );

    const {error: passengerProfileError} = await admin.from('users').upsert({
      id: passenger.id,
      full_name: productionMode ? 'QA PROD Load Passenger' : 'QA Load Passenger',
      active_mode: 'passenger',
      account_status: 'active',
      updated_at: new Date().toISOString(),
    }, {onConflict: 'id'});
    if (passengerProfileError) throw passengerProfileError;

    if (productionMode) {
      const {error: passengerScopeError} = await admin
        .from('audit_test_group_members')
        .delete()
        .eq('user_id', passenger.id);
      if (passengerScopeError) throw passengerScopeError;
    } else {
      const {error: passengerMemberError} = await admin
        .from('audit_test_group_members')
        .upsert({
          group_id: group.id,
          user_id: passenger.id,
          role: 'passenger',
          enabled: true,
          updated_at: new Date().toISOString(),
        }, {onConflict: 'group_id,user_id'});
      if (passengerMemberError) throw passengerMemberError;
    }

    const wanted = Array.from({length: driverCount}, (_, i) => i + 1);
    const drivers: any[] = new Array(driverCount);

    await chunks(wanted, 10, async (number, index) => {
      const suffix = String(number).padStart(3, '0');
      const email = (productionMode
        ? PRODUCTION_DRIVER_EMAIL_PREFIX
        : SANDBOX_DRIVER_EMAIL_PREFIX) + suffix + '@expressdelivery.pro';
      drivers[index] = await ensureAuthUser(admin, users, email, {
        qa_account: true,
        qa_role: 'driver',
        load_lab: true,
        load_index: number,
        load_scope: scope,
      });
    });

    const nowIso = new Date().toISOString();
    const publicUsers = drivers.map((driver, i) => ({
      id: driver.id,
      full_name: (productionMode ? 'QA PROD Load Driver ' : 'QA Load Driver ') +
        String(i + 1).padStart(3, '0'),
      active_mode: 'driver',
      account_status: 'active',
      updated_at: nowIso,
    }));
    const {error: usersError} = await admin
      .from('users')
      .upsert(publicUsers, {onConflict: 'id'});
    if (usersError) throw usersError;

    if (productionMode) {
      const productionDriverIds = drivers.map((driver) => driver.id);
      const {error: membersError} = await admin
        .from('audit_test_group_members')
        .delete()
        .in('user_id', productionDriverIds);
      if (membersError) throw membersError;
    } else {
      const memberships = drivers.map((driver) => ({
        group_id: group.id,
        user_id: driver.id,
        role: 'driver',
        enabled: true,
        updated_at: nowIso,
      }));
      const {error: membersError} = await admin
        .from('audit_test_group_members')
        .upsert(memberships, {onConflict: 'group_id,user_id'});
      if (membersError) throw membersError;
    }

    const profiles = drivers.map((driver, i) => {
      const point = pointAround(centerLat, centerLng, radiusKm, i, driverCount);
      return {
        id: driver.id,
        approval_status: 'approved',
        online_status: 'online',
        vehicle_summary: 'QA Load Moto ' + String(i + 1).padStart(3, '0'),
        city: 'Trinidad',
        latitude: point.lat,
        longitude: point.lng,
        updated_at: nowIso,
      };
    });
    const {error: profileError} = await admin
      .from('driver_profiles')
      .upsert(profiles, {onConflict: 'id'});
    if (profileError) throw profileError;

    const driverIds = drivers.map((driver) => driver.id);
    const {data: currentVehicles, error: currentVehicleError} = await admin
      .from('driver_vehicles')
      .select('id,driver_id')
      .in('driver_id', driverIds);
    if (currentVehicleError) throw currentVehicleError;

    if ((currentVehicles ?? []).length) {
      const {error: deactivateVehicleError} = await admin
        .from('driver_vehicles')
        .update({
          is_active: false,
          updated_at: nowIso,
        })
        .in('driver_id', driverIds);
      if (deactivateVehicleError) throw deactivateVehicleError;
    }

    const chosenVehicleIds: string[] = [];
    const vehicleDrivers = new Set<string>();
    for (const row of currentVehicles ?? []) {
      if (vehicleDrivers.has(row.driver_id)) continue;
      vehicleDrivers.add(row.driver_id);
      chosenVehicleIds.push(row.id);
    }

    if (chosenVehicleIds.length) {
      const {error: updateVehicleError} = await admin
        .from('driver_vehicles')
        .update({
          vehicle_type: 'motorcycle',
          is_active: true,
          updated_at: nowIso,
        })
        .in('id', chosenVehicleIds);
      if (updateVehicleError) throw updateVehicleError;
    }

    const missingVehicles = drivers
      .map((driver, i) => ({driver, i}))
      .filter(({driver}) => !vehicleDrivers.has(driver.id))
      .map(({driver, i}) => ({
        driver_id: driver.id,
        vehicle_type: 'motorcycle',
        brand: 'Express',
        model: 'QA Moto',
        color: 'Negro',
        plate: 'QA-M' + String(i + 1).padStart(3, '0'),
        year: 2026,
        is_active: true,
        updated_at: nowIso,
      }));
    if (missingVehicles.length) {
      const {error: insertVehicleError} = await admin
        .from('driver_vehicles')
        .insert(missingVehicles);
      if (insertVehicleError) throw insertVehicleError;
    }

    const driverEntities = drivers.map((driver) => ({
      run_id: run.id,
      entity_type: 'driver',
      user_id: driver.id,
    }));
    const {error: driverEntityError} = await admin
      .from('audit_load_test_entities')
      .insert(driverEntities);
    if (driverEntityError) throw driverEntityError;

    const requests = Array.from({length: requestCount}, (_, i) => {
      const pickup = pointAround(
        centerLat,
        centerLng,
        Math.min(radiusKm, 2.8),
        i,
        requestCount,
      );
      const destination = pointAround(
        centerLat,
        centerLng,
        Math.min(radiusKm + 1.5, 5),
        i + Math.floor(requestCount / 3) + 7,
        requestCount,
      );
      const n = String(i + 1).padStart(3, '0');
      return {
        passenger_id: passenger.id,
        category: 'motorcycle',
        pickup_address: '[LOADTEST:' + run.id.slice(0, 8) + '] Origen #' + n,
        pickup_latitude: pickup.lat,
        pickup_longitude: pickup.lng,
        destination_address: 'Destino QA #' + n + ' · Trinidad',
        destination_latitude: destination.lat,
        destination_longitude: destination.lng,
        proposed_fare: 10 + (i % 21),
        currency: 'BOB',
        payment_method: 'cash',
        status: 'searching',
        pricing_mode: 'offer',
        route_distance_km: 2 + (i % 10) * 0.6,
        route_duration_minutes: 5 + (i % 18),
        expires_at: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
        updated_at: nowIso,
      };
    });

    const {data: insertedRequests, error: requestsError} = await admin
      .from('ride_requests')
      .insert(requests)
      .select('id');
    if (requestsError) throw requestsError;

    const rideEntities = (insertedRequests ?? []).map((ride) => ({
      run_id: run.id,
      entity_type: 'ride_request',
      ride_request_id: ride.id,
    }));
    if (rideEntities.length) {
      const {error: rideEntityError} = await admin
        .from('audit_load_test_entities')
        .insert(rideEntities);
      if (rideEntityError) throw rideEntityError;
    }

    const durationMs = Math.round(performance.now() - startedAt);
    const metrics = {
      seed_duration_ms: durationMs,
      drivers_online: driverCount,
      requests_active: insertedRequests?.length ?? 0,
      center: {latitude: centerLat, longitude: centerLng},
      radius_km: radiusKm,
      push_suppressed: true,
      scope_mode: scope,
      production_visible: productionMode,
      previous_cleanup: cleanup,
    };

    const {error: finishError} = await admin
      .from('audit_load_test_runs')
      .update({
        status: 'active',
        metrics,
        updated_at: new Date().toISOString(),
      })
      .eq('id', run.id);
    if (finishError) throw finishError;

    return json({
      ok: true,
      action: 'seed',
      run_id: run.id,
      drivers: driverCount,
      requests: insertedRequests?.length ?? 0,
      duration_ms: durationMs,
      center_latitude: centerLat,
      center_longitude: centerLng,
      radius_km: radiusKm,
      push_suppressed: true,
      scope_mode: scope,
      production_visible: productionMode,
    });
  } catch (error) {
    console.error('Express load lab failed', error);
    return json(
      {ok: false, error: error instanceof Error ? error.message : String(error)},
      500,
    );
  }
});
