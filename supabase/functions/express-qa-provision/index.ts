import { createClient } from 'npm:@supabase/supabase-js@2';
import { createRemoteJWKSet, jwtVerify } from 'npm:jose@5';

const allowedRepository = 'jorge2610g/Expressdelivery';
const expectedAudience = 'supabase-express-qa-provision';
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

function randomPassword() {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);

  // Keep the ephemeral QA password strictly alphanumeric. Maestro types text
  // through Android input events, where shell-sensitive punctuation can be
  // transformed even though the same credential works through the Auth API.
  const entropy = Array.from(
    bytes,
    (byte) => byte.toString(16).padStart(2, '0'),
  ).join('');

  return `Qa${entropy}9Z`;
}

async function verifyPasswordLogin(email: string, password: string) {
  const authUrl =
    `${Deno.env.get('SUPABASE_URL')}/auth/v1/token?grant_type=password`;
  let lastError = 'unknown';

  for (let attempt = 0; attempt < 4; attempt += 1) {
    const response = await fetch(authUrl, {
      method: 'POST',
      headers: {
        'apikey': serviceKey(),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({email, password}),
    });

    if (response.ok) {
      const payload = await response.json();
      if (payload?.access_token && payload?.user?.id) return;
      lastError = 'missing_access_token';
    } else {
      const detail = await response.text();
      lastError = `status_${response.status}:${detail.slice(0, 240)}`;
    }

    await new Promise((resolve) => setTimeout(resolve, 300 * (attempt + 1)));
  }

  throw new Error(`QA password verification failed for ${email}: ${lastError}`);
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({error: 'Método no permitido'}, 405);

  try {
    await verifyGithub(req);
    const requestBody = await req.json().catch(() => ({}));

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      serviceKey(),
      {auth: {persistSession: false, autoRefreshToken: false}},
    );

    const passengerEmail = 'qa-passenger@expressdelivery.pro';
    const driverEmail = 'qa-driver@expressdelivery.pro';
    const passengerPassword = randomPassword();
    const driverPassword = randomPassword();

    const {data: usersPage, error: listError} =
      await admin.auth.admin.listUsers({page: 1, perPage: 1000});
    if (listError) throw listError;

    async function ensureAuthUser(
      email: string,
      password: string,
      role: 'passenger' | 'driver',
    ) {
      let user = usersPage.users.find(
        (candidate) => candidate.email?.toLowerCase() === email.toLowerCase(),
      );

      if (!user) {
        const {data, error} = await admin.auth.admin.createUser({
          email,
          password,
          email_confirm: true,
          user_metadata: {qa_account: true, qa_role: role},
        });
        if (error) throw error;
        user = data.user;
      } else {
        const {data, error} = await admin.auth.admin.updateUserById(user.id, {
          password,
          email_confirm: true,
          user_metadata: {
            ...(user.user_metadata ?? {}),
            qa_account: true,
            qa_role: role,
          },
        });
        if (error) throw error;
        user = data.user;
      }

      if (!user) throw new Error('No se pudo aprovisionar usuario QA ' + role);
      return user;
    }

    const passenger = await ensureAuthUser(
      passengerEmail,
      passengerPassword,
      'passenger',
    );
    const driver = await ensureAuthUser(
      driverEmail,
      driverPassword,
      'driver',
    );

    // Manual QA passenger used for hands-on Preview testing.
    // Keep the user's existing password; only confirm and isolate the account.
    const manualPreviewEmail = requestBody.manual_preview_email?.toString().trim().toLowerCase() ?? '';
    let manualPreviewUser = usersPage.users.find(
      (candidate) => candidate.email?.toLowerCase() === manualPreviewEmail,
    );

    if (manualPreviewUser) {
      const {data: updatedManual, error: manualAuthError} =
        await admin.auth.admin.updateUserById(manualPreviewUser.id, {
          email_confirm: true,
          user_metadata: {
            ...(manualPreviewUser.user_metadata ?? {}),
            qa_account: true,
            qa_role: 'passenger',
          },
        });
      if (manualAuthError) throw manualAuthError;
      manualPreviewUser = updatedManual.user ?? manualPreviewUser;

      const {error: manualProfileError} = await admin.from('users').upsert({
        id: manualPreviewUser.id,
        full_name: 'pasajero prueba',
        active_mode: 'passenger',
        account_status: 'active',
        updated_at: new Date().toISOString(),
      }, {onConflict: 'id'});
      if (manualProfileError) throw manualProfileError;

      const {data: qaGroup, error: qaGroupError} = await admin
        .from('audit_test_groups')
        .select('id')
        .eq('slug', 'qa-core')
        .single();
      if (qaGroupError) throw qaGroupError;

      const {error: memberError} = await admin
        .from('audit_test_group_members')
        .upsert({
          group_id: qaGroup.id,
          user_id: manualPreviewUser.id,
          role: 'passenger',
          enabled: true,
          updated_at: new Date().toISOString(),
        }, {onConflict: 'user_id'});
      if (memberError) throw memberError;
    }

    // Do not return credentials until Auth itself proves they work. This keeps
    // QA deterministic and catches any provisioning/auth propagation problem
    // before the emulator starts.
    await verifyPasswordLogin(passengerEmail, passengerPassword);
    await verifyPasswordLogin(driverEmail, driverPassword);

    const {error: passengerProfileError} = await admin.from('users').upsert({
      id: passenger.id,
      full_name: 'QA Passenger',
      active_mode: 'passenger',
      account_status: 'active',
      updated_at: new Date().toISOString(),
    }, {onConflict: 'id'});
    if (passengerProfileError) throw passengerProfileError;

    const {error: driverUserError} = await admin.from('users').upsert({
      id: driver.id,
      full_name: 'QA Driver',
      active_mode: 'driver',
      account_status: 'active',
      updated_at: new Date().toISOString(),
    }, {onConflict: 'id'});
    if (driverUserError) throw driverUserError;

    const {error: driverProfileError} = await admin
      .from('driver_profiles')
      .upsert({
        id: driver.id,
        approval_status: 'approved',
        online_status: 'offline',
        vehicle_summary: 'QA Moto',
        city: 'Trinidad',
        latitude: -14.8333,
        longitude: -64.9000,
        updated_at: new Date().toISOString(),
      }, {onConflict: 'id'});
    if (driverProfileError) throw driverProfileError;

    const {data: vehicles, error: vehicleReadError} = await admin
      .from('driver_vehicles')
      .select('id')
      .eq('driver_id', driver.id)
      .limit(1);
    if (vehicleReadError) throw vehicleReadError;

    if (!vehicles || vehicles.length === 0) {
      const {error: vehicleInsertError} = await admin
        .from('driver_vehicles')
        .insert({
          driver_id: driver.id,
          vehicle_type: 'motorcycle',
          brand: 'Express',
          model: 'QA Moto',
          color: 'Blanco',
          plate: 'QA-000',
          year: 2026,
          is_active: true,
        });
      if (vehicleInsertError) throw vehicleInsertError;
    }

    // Reset only dedicated QA identities so every run starts deterministically.
    await admin
      .from('driver_offers')
      .update({status: 'expired'})
      .eq('driver_id', driver.id)
      .eq('status', 'pending');

    await admin
      .from('ride_requests')
      .update({
        status: 'cancelled',
        cancellation_reason: 'QA reset',
        updated_at: new Date().toISOString(),
      })
      .eq('passenger_id', passenger.id)
      .in('status', ['searching', 'offers_received', 'driver_selected']);

    await admin
      .from('trips')
      .update({
        status: 'cancelled',
        cancellation_reason: 'QA reset',
      })
      .or('passenger_id.eq.' + passenger.id + ',driver_id.eq.' + driver.id)
      .in('status', ['driver_assigned', 'driver_arriving', 'driver_waiting', 'in_progress', 'emergency']);

    await admin
      .from('native_push_tokens')
      .update({active: false, updated_at: new Date().toISOString()})
      .in('user_id', [passenger.id, driver.id]);

    return json({
      ok: true,
      passenger: {
        id: passenger.id,
        email: passengerEmail,
        password: passengerPassword,
      },
      driver: {
        id: driver.id,
        email: driverEmail,
        password: driverPassword,
      },
    });
  } catch (error) {
    console.error('Express QA provision failed', error);
    return json(
      {ok: false, error: error instanceof Error ? error.message : String(error)},
      500,
    );
  }
});
