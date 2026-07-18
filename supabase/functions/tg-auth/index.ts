// Kabanchiki: Telegram Mini App authentication.
//
// The Mini App has no Supabase session yet. It sends Telegram's signed initData
// (and, on first link, the one-time code the parent generated in the desktop).
// This function:
//   1. verifies the initData HMAC with the bot token (server-only secret),
//   2. maps the Telegram user to a parent — binding by link code on first use,
//   3. mints a magic-link token the Mini App exchanges for a real session.
// The bot token never leaves the server; the Mini App only ever sees a token it
// immediately trades via supabase.auth.verifyOtp().

import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const MAX_AUTH_AGE = 24 * 60 * 60; // initData older than a day is rejected

// The bot token is configured by the owner from the desktop and stored in
// app_secrets (readable only by service_role). Fall back to an env var if set.
async function getBotToken(): Promise<string> {
  const { data } = await admin
    .from("app_secrets").select("telegram_bot_token").eq("id", true).maybeSingle();
  return (data?.telegram_bot_token as string | null) || Deno.env.get("TELEGRAM_BOT_TOKEN") || "";
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  // "apikey" and "x-client-info" are sent by supabase-js / the Mini App fetch;
  // without them the browser preflight fails and WebKit reports "Load failed".
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

async function hmac(key: ArrayBuffer | Uint8Array, message: string): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(message));
  return new Uint8Array(sig);
}

function toHex(bytes: Uint8Array): string {
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Validate Telegram Mini App initData; return the parsed fields or null.
async function verifyInitData(initData: string, botToken: string): Promise<URLSearchParams | null> {
  if (!initData) return null;
  const params = new URLSearchParams(initData);
  const hash = params.get("hash");
  if (!hash) return null;
  params.delete("hash");

  const dataCheckString = [...params.entries()]
    .map(([k, v]) => `${k}=${v}`)
    .sort()
    .join("\n");

  const secretKey = await hmac(new TextEncoder().encode("WebAppData"), botToken);
  const computed = toHex(await hmac(secretKey, dataCheckString));
  if (computed !== hash) return null;

  const authDate = Number(params.get("auth_date") ?? "0");
  if (!authDate || (Date.now() / 1000 - authDate) > MAX_AUTH_AGE) return null;

  return params;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const botToken = await getBotToken();
  if (!botToken) return json({ error: "bot_not_configured" }, 503);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }

  const params = await verifyInitData(String(body.initData ?? ""), botToken);
  if (!params) return json({ error: "invalid_init_data" }, 401);

  let tgUser: { id?: number };
  try {
    tgUser = JSON.parse(params.get("user") ?? "{}");
  } catch {
    tgUser = {};
  }
  const tgId = Number(tgUser.id ?? 0);
  if (!tgId) return json({ error: "no_user" }, 400);

  // start_param comes from the initData (deep link) or an explicit field.
  const linkCode = String(body.start_param ?? params.get("start_param") ?? "").trim();

  try {
    // 1. Already linked? (disabled parents cannot sign in)
    let { data: parent } = await admin
      .from("parents").select("id").eq("telegram_id", tgId)
      .eq("disabled", false).maybeSingle();

    // 2. First-time link via one-time code.
    if (!parent && linkCode) {
      const { data: byCode } = await admin
        .from("parents").select("id, link_code_expires")
        .eq("link_code", linkCode).eq("disabled", false).maybeSingle();
      if (byCode && byCode.link_code_expires && new Date(byCode.link_code_expires) > new Date()) {
        const { error: bindErr } = await admin.from("parents")
          .update({ telegram_id: tgId, link_code: null, link_code_expires: null })
          .eq("id", byCode.id);
        if (bindErr) return json({ error: "link_failed" }, 400);
        parent = { id: byCode.id };
      }
    }

    if (!parent) return json({ error: "not_linked" }, 403);

    // 3. Mint a magic-link token for the parent's auth account.
    const { data: authUser } = await admin.auth.admin.getUserById(parent.id);
    const email = authUser?.user?.email;
    if (!email) return json({ error: "no_email" }, 500);

    const { data: link, error: linkErr } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (linkErr || !link?.properties?.hashed_token) {
      return json({ error: linkErr?.message ?? "token_failed" }, 500);
    }

    return json({ token_hash: link.properties.hashed_token, email });
  } catch (e) {
    console.error("tg-auth", e);
    return json({ error: String(e) }, 500);
  }
});
