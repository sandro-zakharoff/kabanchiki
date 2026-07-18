// Kabanchiki: send-push Edge Function.
//
// Invoked by a Database Webhook on INSERT into public.notifications_outbox.
// Sends a high-priority FCM v1 *data* message to every device of the recipient;
// the Android app renders the notification itself (localized text + custom
// sound via notification channels).
//
// Required secrets (supabase secrets set):
//   FCM_SERVICE_ACCOUNT  - full JSON of the Firebase service account key
//   WEBHOOK_SECRET       - shared secret, must match the webhook's X-Webhook-Secret header
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "npm:@supabase/supabase-js@2";

type OutboxRecord = {
  id: number;
  recipient_id: string;
  event_type: string;
  payload: Record<string, unknown>;
  created_at: string;
};

type WebhookBody = {
  type: "INSERT";
  table: string;
  record: OutboxRecord;
};

const serviceAccount = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
const webhookSecret = Deno.env.get("WEBHOOK_SECRET") ?? "";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// ---- Google OAuth2 (service account JWT bearer flow) ----------------------

let cachedToken: { token: string; expiresAt: number } | null = null;

function base64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) return cachedToken.token;

  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64url(new Uint8Array(signature))}`;

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!resp.ok) throw new Error(`oauth token: ${resp.status} ${await resp.text()}`);
  const json = await resp.json();
  cachedToken = { token: json.access_token, expiresAt: now + (json.expires_in ?? 3600) };
  return cachedToken.token;
}

// ---- FCM -------------------------------------------------------------------

async function sendToDevice(fcmToken: string, record: OutboxRecord): Promise<"ok" | "unregistered" | "error"> {
  const accessToken = await getAccessToken();
  // FCM data values must be strings.
  const data: Record<string, string> = {
    event_type: record.event_type,
    outbox_id: String(record.id),
    created_at: record.created_at,
  };
  for (const [k, v] of Object.entries(record.payload ?? {})) {
    data[k] = typeof v === "string" ? v : JSON.stringify(v);
  }

  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          data,
          android: { priority: "HIGH" },
        },
      }),
    },
  );
  if (resp.ok) return "ok";
  const text = await resp.text();
  console.error(`fcm send failed (${resp.status}): ${text}`);
  if (resp.status === 404 || text.includes("UNREGISTERED") || text.includes("INVALID_ARGUMENT")) {
    return "unregistered";
  }
  return "error";
}

// ---- handler ----------------------------------------------------------------

Deno.serve(async (req) => {
  if (webhookSecret && req.headers.get("x-webhook-secret") !== webhookSecret) {
    return new Response("forbidden", { status: 403 });
  }

  let body: WebhookBody;
  try {
    body = await req.json();
  } catch {
    return new Response("bad request", { status: 400 });
  }
  if (body.type !== "INSERT" || !body.record) {
    return new Response("ignored", { status: 200 });
  }
  const record = body.record;

  const { data: devices, error } = await supabase
    .from("devices")
    .select("id, fcm_token")
    .eq("profile_id", record.recipient_id);
  if (error) {
    console.error("devices query failed", error);
    return new Response("db error", { status: 500 });
  }

  let delivered = 0;
  for (const device of devices ?? []) {
    try {
      const result = await sendToDevice(device.fcm_token, record);
      if (result === "ok") delivered++;
      if (result === "unregistered") {
        await supabase.from("devices").delete().eq("id", device.id);
      }
    } catch (e) {
      console.error("send error", e);
    }
  }

  await supabase
    .from("notifications_outbox")
    .update({ sent_at: new Date().toISOString() })
    .eq("id", record.id);

  return new Response(JSON.stringify({ delivered }), {
    headers: { "Content-Type": "application/json" },
  });
});
