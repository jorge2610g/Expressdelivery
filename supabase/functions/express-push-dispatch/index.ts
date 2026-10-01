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

type FirebaseServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

function bytesToBase64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function textToBase64Url(value: string) {
  return bytesToBase64Url(new TextEncoder().encode(value));
}

function pemPkcs8Bytes(pem: string) {
  const clean = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const raw = atob(clean);
  return Uint8Array.from(raw, (char) => char.charCodeAt(0));
}

async function firebaseAccessToken(account: FirebaseServiceAccount) {
  const now = Math.floor(Date.now() / 1000);
  const tokenUri =
    account.token_uri || "https://oauth2.googleapis.com/token";

  const header = textToBase64Url(
    JSON.stringify({ alg: "RS256", typ: "JWT" }),
  );
  const payload = textToBase64Url(
    JSON.stringify({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: tokenUri,
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = header + "." + payload;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemPkcs8Bytes(account.private_key),
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"],
  );

  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(unsigned),
    ),
  );

  const assertion = unsigned + "." + bytesToBase64Url(signature);

  const response = await fetch(tokenUri, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    throw new Error(
      "No se pudo autenticar Firebase: " + (await response.text()),
    );
  }

  const payloadJson = await response.json();
  const accessToken = payloadJson?.access_token?.toString();
  if (!accessToken) {
    throw new Error("Firebase no devolvió access_token.");
  }

  return accessToken;
}

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

    const [
      { data: subscriptions, error: subscriptionError },
      { data: nativeTokens, error: nativeTokenError },
    ] = await Promise.all([
      supabase
        .from("push_subscriptions")
        .select("id,endpoint,p256dh,auth")
        .eq("user_id", userId)
        .eq("active", true),
      supabase
        .from("native_push_tokens")
        .select("id,token,platform")
        .eq("user_id", userId)
        .eq("active", true),
    ]);

    if (subscriptionError) throw subscriptionError;
    if (nativeTokenError) throw nativeTokenError;

    let webDelivered = 0;
    let webInvalid = 0;

    if (subscriptions?.length) {
      webpush.setVapidDetails(
        "mailto:soporte@expressdelivery.pro",
        config.vapid_public_key!,
        config.vapid_private_key!,
      );

      const message = JSON.stringify({
        title,
        body,
        type,
        notification_id: notificationId,
        url: "/Expressdelivery/",
        urgent,
      });

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
          webDelivered++;
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
            webInvalid++;
            await supabase
              .from("push_subscriptions")
              .update({
                active: false,
                updated_at: new Date().toISOString(),
              })
              .eq("id", subscription.id);
          } else {
            console.error("Web Push delivery failed", error);
          }
        }
      }
    }

    let nativeDelivered = 0;
    let nativeInvalid = 0;
    let nativeConfigured = false;

    const serviceAccountRaw =
      Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";

    if (nativeTokens?.length && serviceAccountRaw) {
      nativeConfigured = true;
      const serviceAccount =
        JSON.parse(serviceAccountRaw) as FirebaseServiceAccount;
      const accessToken = await firebaseAccessToken(serviceAccount);
      const projectId = serviceAccount.project_id;

      for (const device of nativeTokens) {
        if (device.platform !== "android") continue;

        const fcmResponse = await fetch(
          "https://fcm.googleapis.com/v1/projects/" +
            encodeURIComponent(projectId) +
            "/messages:send",
          {
            method: "POST",
            headers: {
              Authorization: "Bearer " + accessToken,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              message: {
                token: device.token,
                notification: {
                  title,
                  body,
                },
                data: {
                  type,
                  notification_id: notificationId ?? "",
                  url: "/Expressdelivery/",
                },
                android: {
                  priority: urgent ? "HIGH" : "NORMAL",
                  ttl: urgent ? "120s" : "900s",
                  notification: {
                    channel_id: "express_urgent",
                    sound: "default",
                    notification_priority: urgent
                      ? "PRIORITY_HIGH"
                      : "PRIORITY_DEFAULT",
                    default_vibrate_timings: urgent,
                    visibility: "PUBLIC",
                  },
                },
              },
            }),
          },
        );

        if (fcmResponse.ok) {
          nativeDelivered++;
          continue;
        }

        const detail = await fcmResponse.text();
        const invalidToken =
          fcmResponse.status === 404 ||
          detail.includes("UNREGISTERED") ||
          detail.includes("registration-token-not-registered");

        if (invalidToken) {
          nativeInvalid++;
          await supabase
            .from("native_push_tokens")
            .update({
              active: false,
              updated_at: new Date().toISOString(),
            })
            .eq("id", device.id);
        } else {
          console.error(
            "FCM delivery failed",
            fcmResponse.status,
            detail,
          );
        }
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        delivered: webDelivered + nativeDelivered,
        web_delivered: webDelivered,
        web_invalid: webInvalid,
        native_delivered: nativeDelivered,
        native_invalid: nativeInvalid,
        native_configured: nativeConfigured,
      }),
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
