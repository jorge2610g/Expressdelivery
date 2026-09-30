import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

type PushConfig = {
  vapid_public_key: string | null;
  vapid_private_key: string | null;
  webhook_secret: string;
};

async function getOrCreateConfig(): Promise<PushConfig> {
  const { data, error } = await supabase
    .from("push_server_config")
    .select("vapid_public_key,vapid_private_key,webhook_secret")
    .eq("id", true)
    .single();

  if (error) throw error;

  let config = data as PushConfig;
  if (!config.vapid_public_key || !config.vapid_private_key) {
    const keys = webpush.generateVAPIDKeys();

    const { data: updated, error: updateError } = await supabase
      .from("push_server_config")
      .update({
        vapid_public_key: keys.publicKey,
        vapid_private_key: keys.privateKey,
        updated_at: new Date().toISOString(),
      })
      .eq("id", true)
      .select("vapid_public_key,vapid_private_key,webhook_secret")
      .single();

    if (updateError) throw updateError;
    config = updated as PushConfig;
  }

  return config;
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-express-push-secret",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }

  try {
    const config = await getOrCreateConfig();

    if (req.method === "GET") {
      return new Response(
        JSON.stringify({ publicKey: config.vapid_public_key }),
        {
          status: 200,
          headers: {
            ...corsHeaders(),
            "Content-Type": "application/json",
            "Cache-Control": "public, max-age=3600",
          },
        },
      );
    }

    if (req.method !== "POST") {
      return new Response("Method not allowed", {
        status: 405,
        headers: corsHeaders(),
      });
    }

    const suppliedSecret =
      req.headers.get("x-express-push-secret") ?? "";
    if (!suppliedSecret || suppliedSecret !== config.webhook_secret) {
      return new Response("Unauthorized", {
        status: 401,
        headers: corsHeaders(),
      });
    }

    const payload = await req.json();
    const userId = payload?.user_id?.toString();
    const title = payload?.title?.toString() ?? "Express";
    const body = payload?.body?.toString() ?? "";
    const type = payload?.type?.toString() ?? "general";
    const notificationId =
      payload?.notification_id?.toString() ?? null;

    if (!userId) {
      return new Response(
        JSON.stringify({ ok: false, error: "Missing user_id" }),
        {
          status: 400,
          headers: {
            ...corsHeaders(),
            "Content-Type": "application/json",
          },
        },
      );
    }

    const { data: subscriptions, error: subscriptionError } =
      await supabase
        .from("push_subscriptions")
        .select("id,endpoint,p256dh,auth")
        .eq("user_id", userId)
        .eq("active", true);

    if (subscriptionError) throw subscriptionError;

    if (!subscriptions?.length) {
      return new Response(
        JSON.stringify({
          ok: true,
          delivered: 0,
          reason: "no_subscriptions",
        }),
        {
          status: 200,
          headers: {
            ...corsHeaders(),
            "Content-Type": "application/json",
          },
        },
      );
    }

    webpush.setVapidDetails(
      "mailto:soporte@expressdelivery.pro",
      config.vapid_public_key!,
      config.vapid_private_key!,
    );

    const urgentTypes = new Set([
      "ride_request",
      "ride_offer",
      "ride_offer_sent",
      "ride_assigned",
      "ride_offer_declined",
      "ride_cancelled",
      "trip_cancelled",
      "trip_status",
      "delivery_assigned",
      "delivery_cancelled",
      "emergency",
    ]);

    const urgent = urgentTypes.has(type);
    const message = JSON.stringify({
      title,
      body,
      type,
      notification_id: notificationId,
      url: "/Expressdelivery/",
      urgent,
    });

    let delivered = 0;
    let invalid = 0;

    for (const subscription of subscriptions) {
      try {
        await webpush.sendNotification(
          {
            endpoint: subscription.endpoint,
            keys: {
              p256dh: subscription.p256dh,
              auth: subscription.auth,
            },
          },
          message,
          {
            TTL: urgent ? 120 : 900,
            urgency: urgent ? "high" : "normal",
          },
        );
        delivered++;
      } catch (error) {
        const statusCode =
          typeof error === "object" &&
          error !== null &&
          "statusCode" in error
            ? Number(
                (error as { statusCode?: number }).statusCode ?? 0,
              )
            : 0;

        if (statusCode === 404 || statusCode === 410) {
          invalid++;
          await supabase
            .from("push_subscriptions")
            .update({
              active: false,
              updated_at: new Date().toISOString(),
            })
            .eq("id", subscription.id);
        } else {
          console.error("Push delivery failed", error);
        }
      }
    }

    return new Response(
      JSON.stringify({ ok: true, delivered, invalid }),
      {
        status: 200,
        headers: {
          ...corsHeaders(),
          "Content-Type": "application/json",
        },
      },
    );
  } catch (error) {
    console.error(error);
    return new Response(
      JSON.stringify({
        ok: false,
        error:
          error instanceof Error ? error.message : String(error),
      }),
      {
        status: 500,
        headers: {
          ...corsHeaders(),
          "Content-Type": "application/json",
        },
      },
    );
  }
});
