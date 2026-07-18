// Kabanchiki: privileged auth-admin operations for parents.
//
// The desktop and the Telegram Mini App authenticate as a parent and call this
// function; it verifies the caller is a parent (or owner where required) and
// then performs auth.users operations with the service_role key. The key never
// leaves the server.

import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const EMAIL_DOMAIN = "kabanchiki.local";
const BAN = "876000h"; // ~100 years

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user) return json({ error: "unauthorized" }, 401);

  const { data: parent } = await admin
    .from("parents").select("id, is_owner, disabled").eq("id", user.id).maybeSingle();
  if (!parent || parent.disabled) return json({ error: "not a parent" }, 403);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const action = String(body.action ?? "");

  try {
    switch (action) {
      case "create_child": {
        const username = String(body.username ?? "").trim().toLowerCase();
        const email = `${username}@${EMAIL_DOMAIN}`;
        const created = await admin.auth.admin.createUser({
          email,
          password: String(body.password ?? ""),
          email_confirm: true,
          user_metadata: { username, display_name: body.display_name },
        });
        if (created.error || !created.data.user) {
          return json({ error: created.error?.message ?? "create failed" }, 400);
        }
        const pErr = (await admin.from("profiles").insert({
          id: created.data.user.id,
          username,
          display_name: String(body.display_name ?? "").trim(),
          avatar_color: String(body.avatar_color ?? "#CDB1B1"),
        })).error;
        if (pErr) {
          await admin.auth.admin.deleteUser(created.data.user.id);
          return json({ error: pErr.message }, 400);
        }
        return json({ id: created.data.user.id });
      }

      case "set_child_password": {
        const { error } = await admin.auth.admin.updateUserById(
          String(body.child_id), { password: String(body.password ?? "") },
        );
        return error ? json({ error: error.message }, 400) : json({ ok: true });
      }

      case "set_child_blocked": {
        const childId = String(body.child_id);
        const blocked = body.blocked === true;
        await admin.from("profiles").update({ blocked }).eq("id", childId);
        await admin.auth.admin.updateUserById(childId, { ban_duration: blocked ? BAN : "none" });
        return json({ ok: true });
      }

      case "delete_child": {
        const { error } = await admin.auth.admin.deleteUser(String(body.child_id));
        return error ? json({ error: error.message }, 400) : json({ ok: true });
      }

      case "create_parent": {
        if (!parent.is_owner) return json({ error: "owner only" }, 403);
        const email = String(body.email ?? "").trim().toLowerCase();
        const created = await admin.auth.admin.createUser({
          email,
          password: String(body.password ?? ""),
          email_confirm: true,
        });
        if (created.error || !created.data.user) {
          return json({ error: created.error?.message ?? "create failed" }, 400);
        }
        const pErr = (await admin.from("parents").insert({
          id: created.data.user.id,
          display_name: String(body.display_name ?? "").trim(),
          email,
          is_owner: body.is_owner === true,
        })).error;
        if (pErr) {
          await admin.auth.admin.deleteUser(created.data.user.id);
          return json({ error: pErr.message }, 400);
        }
        return json({ id: created.data.user.id });
      }

      case "delete_parent": {
        if (!parent.is_owner) return json({ error: "owner only" }, 403);
        const target = String(body.parent_id);
        if (target === user.id) return json({ error: "cannot delete yourself" }, 400);
        const { error } = await admin.auth.admin.deleteUser(target);
        return error ? json({ error: error.message }, 400) : json({ ok: true });
      }

      case "register_tg_webhook": {
        // Point the bot's webhook at tg-bot with a fresh secret token.
        if (!parent.is_owner) return json({ error: "owner only" }, 403);
        const { data: secrets } = await admin
          .from("app_secrets").select("telegram_bot_token").eq("id", true).maybeSingle();
        const botToken = secrets?.telegram_bot_token as string | null;
        if (!botToken) return json({ error: "bot_not_configured" }, 400);

        const secret = crypto.randomUUID().replace(/-/g, "") +
          crypto.randomUUID().replace(/-/g, "");
        const { error: sErr } = await admin.from("app_secrets")
          .update({ telegram_webhook_secret: secret }).eq("id", true);
        if (sErr) return json({ error: sErr.message }, 500);

        const resp = await fetch(`https://api.telegram.org/bot${botToken}/setWebhook`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            url: `${Deno.env.get("SUPABASE_URL")}/functions/v1/tg-bot`,
            secret_token: secret,
            allowed_updates: ["callback_query", "message"],
          }),
        });
        const tg = await resp.json().catch(() => ({}));
        if (!resp.ok || !tg.ok) {
          return json({ error: tg.description ?? `setWebhook failed (${resp.status})` }, 502);
        }
        return json({ ok: true });
      }

      case "update_parent": {
        // Everyone edits their own profile; owners edit anyone's.
        const target = String(body.parent_id ?? user.id);
        if (target !== user.id && !parent.is_owner) return json({ error: "owner only" }, 403);
        const fields: Record<string, string> = {
          display_name: String(body.display_name ?? "").trim(),
          phone: String(body.phone ?? "").trim(),
          note: String(body.note ?? "").trim(),
        };
        const email = String(body.email ?? "").trim().toLowerCase();
        if (email) {
          // Email is the login: change it in auth first, then mirror it.
          const { error } = await admin.auth.admin.updateUserById(target, {
            email, email_confirm: true,
          });
          if (error) return json({ error: error.message }, 400);
          fields.email = email;
        }
        const { error: uErr } = await admin.from("parents").update(fields).eq("id", target);
        return uErr ? json({ error: uErr.message }, 400) : json({ ok: true });
      }

      case "set_parent_disabled": {
        if (!parent.is_owner) return json({ error: "owner only" }, 403);
        const target = String(body.parent_id);
        const disabled = body.disabled === true;
        if (target === user.id) return json({ error: "cannot disable yourself" }, 400);
        if (disabled) {
          // The family must keep at least one active owner.
          const { count } = await admin.from("parents")
            .select("id", { count: "exact", head: true })
            .eq("is_owner", true).eq("disabled", false).neq("id", target);
          if (!count) return json({ error: "last active owner" }, 400);
        }
        await admin.from("parents").update({ disabled }).eq("id", target);
        await admin.auth.admin.updateUserById(target, { ban_duration: disabled ? BAN : "none" });
        return json({ ok: true });
      }

      case "set_parent_password": {
        // A parent can change their own password; an owner can change anyone's.
        const target = String(body.parent_id ?? user.id);
        if (target !== user.id && !parent.is_owner) return json({ error: "owner only" }, 403);
        const { error } = await admin.auth.admin.updateUserById(
          target, { password: String(body.password ?? "") },
        );
        return error ? json({ error: error.message }, 400) : json({ ok: true });
      }

      default:
        return json({ error: "unknown action" }, 400);
    }
  } catch (e) {
    console.error(action, e);
    return json({ error: String(e) }, 500);
  }
});
