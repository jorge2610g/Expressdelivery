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

async function firebaseScopedAccessToken(
  account: FirebaseServiceAccount,
  scope: string,
) {
  const now = Math.floor(Date.now() / 1000);
  const tokenUri =
    account.token_uri || "https://oauth2.googleapis.com/token";
  const header = textToBase64Url(
    JSON.stringify({ alg: "RS256", typ: "JWT" }),
  );
  const payload = textToBase64Url(
    JSON.stringify({
      iss: account.client_email,
      scope,
      aud: tokenUri,
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = header + "." + payload;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemPkcs8Bytes(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
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
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error(
      "No se pudo autenticar Firebase Management: " +
        (await response.text()),
    );
  }
  const body = await response.json();
  const token = body?.access_token?.toString() ?? "";
  if (!token) throw new Error("Firebase Management no devolvió access_token.");
  return token;
}

async function resolveAndroidClientConfig(packageName: string) {
  const serviceAccountRaw =
    Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";
  if (!serviceAccountRaw) return null;

  const account = JSON.parse(serviceAccountRaw) as FirebaseServiceAccount;
  const accessToken = await firebaseScopedAccessToken(
    account,
    "https://www.googleapis.com/auth/firebase.readonly",
  );
  const listResponse = await fetch(
    "https://firebase.googleapis.com/v1beta1/projects/" +
      encodeURIComponent(account.project_id) +
      "/androidApps",
    { headers: { Authorization: "Bearer " + accessToken } },
  );
  if (!listResponse.ok) {
    console.error(
      "Firebase Android app list failed",
      listResponse.status,
      await listResponse.text(),
    );
    return null;
  }
  const list = await listResponse.json();
  const apps = Array.isArray(list?.apps) ? list.apps : [];
  const app = apps.find(
    (item: Record<string, unknown>) =>
      item?.packageName?.toString() === packageName,
  );
  if (!app?.appId) return null;

  const configResponse = await fetch(
    "https://firebase.googleapis.com/v1beta1/projects/-/androidApps/" +
      encodeURIComponent(app.appId.toString()) +
      "/config",
    { headers: { Authorization: "Bearer " + accessToken } },
  );
  if (!configResponse.ok) {
    console.error(
      "Firebase Android config failed",
      configResponse.status,
      await configResponse.text(),
    );
    return null;
  }
  const configEnvelope = await configResponse.json();
  const encoded = configEnvelope?.configFileContents?.toString() ?? "";
  if (!encoded) return null;
  const googleServices = JSON.parse(atob(encoded));
  const projectInfo = googleServices?.project_info ?? {};
  const clients = Array.isArray(googleServices?.client)
    ? googleServices.client
    : [];
  const client = clients.find(
    (item: Record<string, any>) =>
      item?.client_info?.android_client_info?.package_name === packageName,
  );
  const apiKeys = Array.isArray(client?.api_key) ? client.api_key : [];
  const apiKey = apiKeys[0]?.current_key?.toString() ?? "";
  const appId =
    client?.client_info?.mobilesdk_app_id?.toString() ?? "";
  const messagingSenderId =
    projectInfo?.project_number?.toString() ?? "";
  const projectId =
    projectInfo?.project_id?.toString() ?? account.project_id;
  const storageBucket =
    projectInfo?.storage_bucket?.toString() ?? "";
  if (!apiKey || !appId || !messagingSenderId || !projectId) return null;
  return { apiKey, appId, messagingSenderId, projectId, storageBucket };
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
      const url = new URL(req.url);
      if (url.searchParams.get("client_config") === "android") {
        const packageName = url.searchParams.get("package") ?? "";
        const expectedPackage =
          Deno.env.get("FIREBASE_ANDROID_PACKAGE_NAME") ??
          Deno.env.get("EXPRESS_FIREBASE_PACKAGE_NAME") ??
          "com.express.usuario.preview";

        const apiKey =
          Deno.env.get("FIREBASE_ANDROID_API_KEY") ??
          Deno.env.get("EXPRESS_PREVIEW_FIREBASE_API_KEY") ??
          Deno.env.get("FIREBASE_API_KEY") ??
          "";
        const appId =
          Deno.env.get("FIREBASE_ANDROID_APP_ID") ??
          Deno.env.get("EXPRESS_PREVIEW_FIREBASE_APP_ID") ??
          Deno.env.get("FIREBASE_APP_ID") ??
          "";
        const messagingSenderId =
          Deno.env.get("FIREBASE_MESSAGING_SENDER_ID") ??
          Deno.env.get("EXPRESS_PREVIEW_FIREBASE_MESSAGING_SENDER_ID") ??
          "";
        let projectId =
          Deno.env.get("FIREBASE_PROJECT_ID") ??
          Deno.env.get("EXPRESS_PREVIEW_FIREBASE_PROJECT_ID") ??
          "";
        const storageBucket =
          Deno.env.get("FIREBASE_STORAGE_BUCKET") ??
          Deno.env.get("EXPRESS_PREVIEW_FIREBASE_STORAGE_BUCKET") ??
          "";

        if (!projectId) {
          try {
            const accountRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";
            if (accountRaw) {
              projectId = JSON.parse(accountRaw)?.project_id?.toString() ?? "";
            }
          } catch (_) {}
        }

        const packageAccepted =
          packageName.isEmpty ||
          packageName === expectedPackage ||
          packageName === "com.express.usuario1" ||
          packageName === "com.express.usuario" ||
          packageName === "com.express.usuario.preview";

        let resolved = packageAccepted &&
            apiKey.length > 0 &&
            appId.length > 0 &&
            messagingSenderId.length > 0 &&
            projectId.length > 0
          ? { apiKey, appId, messagingSenderId, projectId, storageBucket }
          : null;

        if (!resolved && packageAccepted && packageName) {
          try {
            resolved = await resolveAndroidClientConfig(packageName);
          } catch (error) {
            console.error("Firebase client config resolve failed", error);
          }
        }

        return new Response(
          JSON.stringify({
            found: resolved != null,
            apiKey: resolved?.apiKey,
            appId: resolved?.appId,
            messagingSenderId: resolved?.messagingSenderId,
            projectId: resolved?.projectId,
            storageBucket: resolved?.storageBucket || undefined,
          }),
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
    const metadataRaw = payload?.metadata;
    const metadata: Record<string, unknown> =
      metadataRaw &&
          typeof metadataRaw === "object" &&
          !Array.isArray(metadataRaw)
        ? metadataRaw as Record<string, unknown>
        : {};
    const dataMetadata: Record<string, string> = {};
    for (
      const key of [
        "ride_request_id",
        "offer_id",
        "trip_id",
        "zone_id",
        "mode",
        "deep_link",
      ]
    ) {
      const value = metadata[key];
      if (value !== undefined && value !== null && String(value).length > 0) {
        dataMetadata[key] = String(value);
      }
    }

    const campaignId =
      metadata["campaign_id"] !== undefined &&
          metadata["campaign_id"] !== null &&
          String(metadata["campaign_id"]).length > 0
        ? String(metadata["campaign_id"])
        : null;

    async function logDeliveryEvent(
      channel: string,
      event: string,
      providerStatus: string,
      details: Record<string, unknown> = {},
    ) {
      if (!notificationId) return;
      try {
        const { error } = await supabase
          .from("notification_delivery_events")
          .insert({
            notification_id: notificationId,
            campaign_id: campaignId,
            user_id: userId,
            channel,
            event,
            provider_status: providerStatus,
            details,
          });
        if (error) {
          console.error("Push analytics insert failed", error);
        }
      } catch (error) {
        // Analytics are best-effort: never fail an actual push because
        // telemetry could not be stored.
        console.error("Push analytics logging failed", error);
      }
    }

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
      "passenger_on_way",
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
        metadata,
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
          await logDeliveryEvent(
            "web",
            "provider_accepted",
            "accepted",
            { subscription_id: subscription.id },
          );
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
            await logDeliveryEvent(
              "web",
              "provider_invalid",
              statusCode.toString(),
              { subscription_id: subscription.id },
            );
            await supabase
              .from("push_subscriptions")
              .update({
                active: false,
                updated_at: new Date().toISOString(),
              })
              .eq("id", subscription.id);
          } else {
            await logDeliveryEvent(
              "web",
              "provider_error",
              statusCode > 0 ? statusCode.toString() : "error",
              { subscription_id: subscription.id },
            );
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
                  ...dataMetadata,
                },
                android: {
                  priority: urgent ? "HIGH" : "NORMAL",
                  ttl: urgent ? "120s" : "900s",
                  notification: {
                    channel_id: "express_urgent",
                    icon: "ic_stat_express",
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
          await logDeliveryEvent(
            "android",
            "provider_accepted",
            fcmResponse.status.toString(),
            { token_id: device.id },
          );
          continue;
        }

        const detail = await fcmResponse.text();
        const invalidToken =
          fcmResponse.status === 404 ||
          detail.includes("UNREGISTERED") ||
          detail.includes("registration-token-not-registered");

        if (invalidToken) {
          nativeInvalid++;
          await logDeliveryEvent(
            "android",
            "provider_invalid",
            fcmResponse.status.toString(),
            { token_id: device.id },
          );
          await supabase
            .from("native_push_tokens")
            .update({
              active: false,
              updated_at: new Date().toISOString(),
            })
            .eq("id", device.id);
        } else {
          await logDeliveryEvent(
            "android",
            "provider_error",
            fcmResponse.status.toString(),
            { token_id: device.id },
          );
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
