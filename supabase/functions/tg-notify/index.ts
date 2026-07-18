// Kabanchiki: tg-notify Edge Function.
//
// Invoked by a pg_net webhook on INSERT/UPDATE into public.tg_outbox (updates
// come from the pg_cron retry sweep). Sends a Telegram message about an
// assignee action to every linked, active owner, with inline quick actions
// that the tg-bot webhook executes.
//
// Required secrets: WEBHOOK_SECRET (must match the trigger's header).
// Bot token comes from app_secrets (owner-managed), bot username from app_config.

import { createClient } from "npm:@supabase/supabase-js@2";

type OutboxRecord = {
  id: number;
  kind: string;
  payload: {
    action?: string;
    entity?: string;
    entity_id?: string;
    title?: string;
    actor?: string;
    amount?: number | string;
    note?: string;
    at?: string;
  };
  sent_at: string | null;
  attempts: number;
};

const webhookSecret = Deno.env.get("WEBHOOK_SECRET") ?? "";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const esc = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function fmtMoney(v: number | string | undefined): string {
  if (v === undefined || v === null) return "";
  const n = Number(v);
  return isNaN(n) ? "" : `${n.toFixed(2)} ₴`;
}

function fmtTime(iso: string | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  return d.toLocaleString("uk-UA", {
    day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit",
    timeZone: "Europe/Kyiv",
  });
}

// Message text + inline keyboard for one outbox row.
function render(rec: OutboxRecord, botUsername: string) {
  const p = rec.payload;
  const who = esc(p.actor || "Виконавець");
  const title = esc(p.title || "");
  const amount = fmtMoney(p.amount);
  const when = fmtTime(p.at);
  const note = p.note ? `\n💬 ${esc(p.note)}` : "";

  let text = "";
  const keyboard: unknown[][] = [];
  const openRow = botUsername
    ? [{ text: "📱 Відкрити застосунок", url: `https://t.me/${botUsername}?startapp` }]
    : [];

  switch (rec.kind) {
    case "task_submitted":
      text = `📥 <b>${who}</b> відправив(ла) на перевірку завдання\n«${title}»${amount ? ` · ${amount}` : ""}${note}`;
      keyboard.push([
        { text: "✅ Прийняти", callback_data: `ta:approve:${p.entity_id}` },
        { text: "❌ Відхилити", callback_data: `ta:reject:${p.entity_id}` },
      ]);
      keyboard.push([{ text: "🔁 На доробку", callback_data: `ta:rework:${p.entity_id}` }]);
      break;
    case "task_completed":
      text = `✅ <b>${who}</b> виконав(ла) завдання\n«${title}»${amount ? ` · ${amount}` : ""}`;
      break;
    case "task_started":
      text = `▶️ <b>${who}</b> почав(ла) виконувати «${title}»`;
      break;
    case "task_declined":
      text = `🚫 <b>${who}</b> відмовився(лась) від завдання «${title}»${note}`;
      break;
    case "withdrawal_requested":
      text = `💸 <b>${who}</b> просить вивід <b>${amount || "?"}</b>`;
      keyboard.push([
        { text: "✅ Схвалити", callback_data: `wd:approve:${p.entity_id}` },
        { text: "❌ Відхилити", callback_data: `wd:decline:${p.entity_id}` },
      ]);
      break;
    case "withdrawal_confirmed":
      text = `💵 <b>${who}</b> підтвердив(ла) отримання готівки${amount ? ` · ${amount}` : ""}`;
      break;
    case "task_deadline_overdue":
      text = `⏰ Завдання <b>«${title}»</b> прострочено${p.actor ? ` (${who})` : ""}`;
      break;
    default:
      text = `ℹ️ <b>${who}</b>: ${rec.kind} «${title}»${amount ? ` · ${amount}` : ""}`;
  }
  if (when) text += `\n🕐 ${when}`;
  if (openRow.length) keyboard.push(openRow);
  return { text, keyboard };
}

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== webhookSecret) {
    return new Response("forbidden", { status: 403 });
  }

  let rec: OutboxRecord;
  try {
    rec = (await req.json()).record;
  } catch {
    return new Response("bad request", { status: 400 });
  }
  if (!rec || rec.sent_at) return Response.json({ ok: true, skipped: true });

  const mark = (fields: Record<string, unknown>) =>
    admin.from("tg_outbox").update(fields).eq("id", rec.id);

  try {
    const { data: secret } = await admin
      .from("app_secrets").select("telegram_bot_token").eq("id", true).maybeSingle();
    const botToken = secret?.telegram_bot_token as string | null;
    if (!botToken) {
      await mark({ sent_at: new Date().toISOString(), last_error: "bot_not_configured" });
      return Response.json({ ok: true, skipped: "no token" });
    }

    const { data: cfg } = await admin
      .from("app_config").select("telegram_bot_username").eq("id", true).maybeSingle();
    const { data: owners } = await admin
      .from("parents").select("telegram_id")
      .not("telegram_id", "is", null).eq("disabled", false);

    if (!owners || owners.length === 0) {
      // Nobody linked yet — nothing to deliver; don't spin the retry loop.
      await mark({ sent_at: new Date().toISOString(), last_error: "no linked owners" });
      return Response.json({ ok: true, skipped: "no recipients" });
    }

    const { text, keyboard } = render(rec, cfg?.telegram_bot_username ?? "");
    const errors: string[] = [];
    let delivered = 0;

    for (const o of owners) {
      const resp = await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: o.telegram_id,
          text,
          parse_mode: "HTML",
          reply_markup: keyboard.length ? { inline_keyboard: keyboard } : undefined,
        }),
      });
      if (resp.ok) {
        delivered++;
      } else {
        errors.push(`${o.telegram_id}: ${(await resp.text()).slice(0, 160)}`);
      }
    }

    if (delivered > 0) {
      await mark({
        sent_at: new Date().toISOString(),
        last_error: errors.length ? errors.join("; ").slice(0, 500) : null,
      });
    } else {
      await mark({
        attempts: rec.attempts + 1,
        last_error: errors.join("; ").slice(0, 500) || "send failed",
      });
      // Journal the failure once retries are exhausted.
      if (rec.attempts + 1 >= 5) {
        await admin.from("events").insert({
          actor_kind: "system", actor_name: "", action: "notify_failed",
          entity: rec.payload.entity ?? "task", entity_id: rec.payload.entity_id,
          entity_title: rec.payload.title ?? "", child_id: null,
          details: { kind: rec.kind, error: errors.join("; ").slice(0, 300) },
        });
      }
    }
    return Response.json({ ok: true, delivered, errors: errors.length });
  } catch (e) {
    console.error("tg-notify", e);
    await mark({ attempts: rec.attempts + 1, last_error: String(e).slice(0, 500) });
    return Response.json({ ok: false }, { status: 500 });
  }
});
