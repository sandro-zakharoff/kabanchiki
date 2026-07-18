// Kabanchiki: tg-bot Edge Function — the bot's Telegram webhook.
//
// Registered via setWebhook (see the admin function's register_tg_webhook)
// with a secret_token stored in app_secrets; every request must carry it in
// X-Telegram-Bot-Api-Secret-Token. Handles:
//   - callback_query  ta:<approve|reject|rework>:<task_id>
//                     wd:<approve|decline>:<withdrawal_id>
//     -> bot_act() RPC (service_role), which attributes the journal entry to
//        the owner who pressed the button; the message is edited in place so
//        the buttons cannot be pressed twice.
//   - /start          -> a short welcome with a Mini App button.

import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const ACTIONS: Record<string, { rpc: string; done: string }> = {
  "ta:approve": { rpc: "task_approve", done: "✅ Прийнято" },
  "ta:reject": { rpc: "task_reject", done: "❌ Відхилено" },
  "ta:rework": { rpc: "task_rework", done: "🔁 На доробку" },
  "wd:approve": { rpc: "wd_approve", done: "✅ Схвалено" },
  "wd:decline": { rpc: "wd_decline", done: "❌ Відхилено" },
};

const HUMAN_ERRORS: Record<string, string> = {
  INVALID_STATUS: "Вже неактуально: статус змінився",
  ALREADY_DECIDED: "Цей запит уже вирішено",
  TASK_NOT_FOUND: "Завдання вже не існує",
  WITHDRAWAL_NOT_FOUND: "Запит уже не існує",
  NOT_PARENT: "Немає доступу",
};

async function tg(botToken: string, method: string, payload: unknown) {
  const resp = await fetch(`https://api.telegram.org/bot${botToken}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!resp.ok) console.error(method, await resp.text());
  return resp;
}

Deno.serve(async (req) => {
  const { data: secrets } = await admin
    .from("app_secrets")
    .select("telegram_bot_token, telegram_webhook_secret")
    .eq("id", true).maybeSingle();
  const botToken = secrets?.telegram_bot_token as string | null;
  const webhookSecret = secrets?.telegram_webhook_secret as string | null;

  if (!botToken || !webhookSecret ||
      req.headers.get("x-telegram-bot-api-secret-token") !== webhookSecret) {
    return new Response("forbidden", { status: 403 });
  }

  let update: Record<string, any>;
  try {
    update = await req.json();
  } catch {
    return new Response("bad request", { status: 400 });
  }

  try {
    // ---------------- callback buttons
    const cq = update.callback_query;
    if (cq) {
      const answer = (text: string, alert = false) =>
        tg(botToken, "answerCallbackQuery", {
          callback_query_id: cq.id, text, show_alert: alert,
        });

      const m = /^(ta|wd):(approve|reject|rework|decline):([0-9a-f-]{36})$/.exec(cq.data ?? "");
      const action = m ? ACTIONS[`${m[1]}:${m[2]}`] : undefined;
      if (!m || !action) {
        await answer("Невідома дія");
        return Response.json({ ok: true });
      }

      // Only linked, active owners may act.
      const { data: parent } = await admin
        .from("parents").select("id, display_name, email")
        .eq("telegram_id", cq.from.id).eq("disabled", false).maybeSingle();
      if (!parent) {
        await answer("Немає доступу: цей Telegram не прив'язано до власника", true);
        return Response.json({ ok: true });
      }

      const { error } = await admin.rpc("bot_act", {
        p_parent_id: parent.id,
        p_action: action.rpc,
        p_target: m[3],
        p_note: null,
      });

      if (error) {
        const human = Object.entries(HUMAN_ERRORS)
          .find(([code]) => error.message.includes(code))?.[1] ?? "Не вдалося виконати дію";
        await answer(human, true);
        return Response.json({ ok: true });
      }

      const who = parent.display_name || parent.email || "власник";
      await answer(action.done);
      // Freeze the message: append the outcome, drop the action buttons.
      if (cq.message) {
        const oldMarkup = cq.message.reply_markup?.inline_keyboard ?? [];
        const urlRows = oldMarkup.filter((row: any[]) => row.every((b) => b.url));
        await tg(botToken, "editMessageText", {
          chat_id: cq.message.chat.id,
          message_id: cq.message.message_id,
          text: `${cq.message.text}\n\n${action.done} — ${who}`,
          reply_markup: urlRows.length ? { inline_keyboard: urlRows } : undefined,
        });
      }
      return Response.json({ ok: true });
    }

    // ---------------- plain messages: greet /start
    const msg = update.message;
    if (msg?.text?.startsWith("/start")) {
      const { data: cfg } = await admin
        .from("app_config").select("telegram_bot_username").eq("id", true).maybeSingle();
      const bot = cfg?.telegram_bot_username ?? "";
      await tg(botToken, "sendMessage", {
        chat_id: msg.chat.id,
        text: "Це бот родинної системи завдань Kabanchiki 🐷\n" +
          "Сюди приходять сповіщення про дії виконавців з кнопками швидких рішень.\n" +
          "Керування — у застосунку:",
        reply_markup: bot
          ? { inline_keyboard: [[{ text: "📱 Відкрити Kabanchiki", url: `https://t.me/${bot}?startapp` }]] }
          : undefined,
      });
    }
    return Response.json({ ok: true });
  } catch (e) {
    console.error("tg-bot", e);
    // Always 200 so Telegram doesn't hammer the webhook with retries.
    return Response.json({ ok: false });
  }
});
