// Kabanchiki Mini App — controller: auth, realtime, rendering, actions.

import * as api from "./api.js?v=218";
import { AuthNeeded, NotLinked, NetworkError, AuthFailed, supabase, serverNow } from "./api.js?v=218";
import { ONLINE_WINDOW_MS } from "./config.js?v=218";
import {
  acornsHtml, acornWords, duration, dateTimeLocal, parseTs, initials, escapeHtml, deadline,
  DIFFICULTY_COLORS, TASK_STATUS, WITHDRAWAL_STATUS,
} from "./format.js?v=218";
import * as ui from "./ui.js?v=218";
import { optimizeImage } from "./images.js?v=218";

const tg = window.Telegram?.WebApp;
const $ = (sel) => document.querySelector(sel);
const view = () => $("#view");
const COPYRIGHT = `© ${new Date().getFullYear()} Zakharoff · Oleksandr Zakharov`;
const haptic = ui.haptic;

const state = {
  parent: null,
  tab: "tasks",
  taskFilter: "submitted",
  taskAuthor: "",
  journalFilter: "", journalChild: "", journalPeriod: "", journalQuery: "",
  loaded: false, loadError: false,
  children: [], devices: [], tasks: [], jobs: [], jobStats: [],
  withdrawals: [], bonuses: [], events: [], locations: [], parents: [],
  attachments: [], ledger: [], latestRelease: null,
  wdChild: "", wdStatus: "", ledgerChild: "", moneyTab: "balances",
};

// ------------------------------------------------------------------ boot

async function boot() {
  if (tg) {
    tg.ready(); tg.expand(); tg.setHeaderColor?.("secondary_bg_color");
    // A swipe down on a bottom sheet must not collapse the whole Mini App
    // (Bot API 7.7+; older clients fall back to CSS overscroll containment).
    tg.disableVerticalSwipes?.();
  }
  applyTheme();
  applyViewport();
  tg?.onEvent?.("themeChanged", applyTheme);
  tg?.onEvent?.("viewportChanged", applyViewport);
  // Stacked layers (option sheets, lightbox…) close first; then the main sheet.
  tg?.BackButton?.onClick?.(() => { if (!ui.closeTopLayer()) closeSheet(); });
  tg?.MainButton?.onClick?.(onMainButton);

  try {
    // Resume an existing session first (avoids re-minting a token each open).
    let parent = await api.currentParent();
    if (!parent) {
      const initData = tg?.initData || "";
      const startParam = tg?.initDataUnsafe?.start_param || "";
      parent = await api.signInWithTelegram(initData, startParam);
    }
    state.parent = parent;
  } catch (e) {
    console.error("boot failed", e);
    if (e instanceof AuthNeeded) return showGate("open");
    if (e instanceof NotLinked) return showGate("link");
    return showGate("error", signInErrorText(e), String(e.message || e));
  }

  // Signed in: show the shell right away (skeletons), then fill with data.
  renderShell();
  render();
  api.syncClock();
  await loadData();
  subscribeRealtime();
  startTicker();
}

// First load and every manual retry of the data layer.
async function loadData() {
  state.loadError = false;
  try {
    await reloadAll();
    state.loaded = true;
  } catch (e) {
    console.error("data load failed", e);
    state.loadError = true;
  }
  render();
}

// A human explanation of why sign-in failed and what to do about it.
function signInErrorText(e) {
  if (e instanceof NetworkError) {
    return "Немає зв'язку з сервером. Перевірте інтернет і спробуйте ще раз.";
  }
  if (e instanceof AuthFailed) {
    switch (e.code) {
      case "bot_not_configured":
        return "Бот ще не налаштований. У Windows-програмі відкрийте Налаштування → Telegram і збережіть токен бота.";
      case "invalid_init_data":
        return "Telegram не підтвердив вхід. Найчастіше це означає, що токен бота в налаштуваннях не відповідає боту, через якого відкрито Mini App.";
      case "no_email":
      case "link_failed":
        return "Не вдалося прив'язати акаунт. Згенеруйте нове посилання у Windows-програмі (Налаштування → Telegram) і спробуйте ще раз.";
      default:
        return "Сервер відхилив вхід. Спробуйте ще раз за хвилину.";
    }
  }
  return "Щось пішло не так. Спробуйте ще раз.";
}

// True only inside a real Telegram client (the SDK also loads in plain browsers).
const inTelegram = () => !!tg?.initData;

function applyTheme() {
  const p = tg?.themeParams || {};
  const dark = tg?.colorScheme === "dark";
  // Telegram's colors win; brand fallbacks match the scheme so a dark client
  // without themeParams never gets light backgrounds with dark-theme chips.
  const v = {
    "--tg-bg": p.bg_color || (dark ? "#201F24" : "#F7F3F1"),
    "--tg-secondary-bg": p.secondary_bg_color || (dark ? "#17161A" : "#ECE6E3"),
    "--tg-text": p.text_color || (dark ? "#F3F0F2" : "#38333B"),
    "--tg-hint": p.hint_color || (dark ? "#9C93A0" : "#A29AA5"),
  };
  const root = document.documentElement.style;
  for (const [k, val] of Object.entries(v)) root.setProperty(k, val);
  // The root element paints the whole WebView canvas: keep it in lockstep
  // with --bg so short pages never show a mismatched band under the content.
  root.background = v["--tg-secondary-bg"];
  document.body.dataset.scheme = dark ? "dark" : "light";
}

// Keep sheets inside the visible viewport (keyboard open shrinks it).
function applyViewport() {
  const h = tg?.viewportStableHeight;
  if (h) document.documentElement.style.setProperty("--tg-vh", `${h}px`);
}

// ------------------------------------------------------------------ gates

function showGate(kind, text = "", detail = "") {
  const gates = {
    open: {
      title: "Відкрийте у Telegram",
      text: "Цей застосунок працює лише всередині Telegram — через кнопку меню бота Kabanchiki.",
      retry: false,
    },
    link: {
      title: "Потрібно прив'язати акаунт",
      text: "Відкрийте Windows-програму Kabanchiki → Налаштування → Telegram → «Прив'язати мій Telegram» і перейдіть за посиланням ще раз.",
      retry: true,
    },
    error: {
      title: "Не вдалося увійти",
      text: escapeHtml(text) || "Спробуйте пізніше.",
      retry: true,
    },
  };
  const g = gates[kind];
  document.body.innerHTML =
    `<div class="gate"><img class="gate-logo" src="./assets/logo.png" alt="Kabanchiki">` +
    `<h1>${g.title}</h1><p>${g.text}</p>` +
    (g.retry ? `<button class="btn gate-retry" data-action="retry">Повторити</button>` : "") +
    (detail ? `<p class="gate-detail">${escapeHtml(detail)}</p>` : "") +
    `<p class="copyright">${COPYRIGHT}</p></div>`;
}

// ------------------------------------------------------------------ data

let reloadTimer = null;
function scheduleReload() {
  clearTimeout(reloadTimer);
  reloadTimer = setTimeout(async () => { await reloadAll(); render(); }, 250);
}

async function reloadAll() {
  const [children, devices, tasks, jobs, jobStats,
    withdrawals, bonuses, events, locations, parents, attachments,
    ledger, latestRelease, , config] = await Promise.all([
    api.listChildren(), api.listDevices(), api.listTasks(),
    api.listJobs(), api.listJobStats(), api.listWithdrawals(), api.listBonuses(),
    api.listEvents(), api.listLocations(), api.listParents(), api.listAttachments(),
    api.listLedger(), api.latestRelease(), api.loadStorageConfig(), api.loadAppConfig(),
  ]);
  Object.assign(state, {
    children, devices, tasks, jobs, jobStats, withdrawals, bonuses,
    events, locations, parents, attachments, ledger, latestRelease, config,
  });
}

// Realtime with self-healing: on channel failure, drop it and resubscribe.
let liveChannel = null;
function subscribeRealtime() {
  const ch = supabase.channel(`parent-live-${Date.now()}`)
    .on("postgres_changes", { event: "*", schema: "public" }, scheduleReload)
    .subscribe((status) => {
      if (ch !== liveChannel) return; // stale channel we already replaced
      if (status === "SUBSCRIBED") scheduleReload();
      if (["CHANNEL_ERROR", "TIMED_OUT", "CLOSED"].includes(status)) {
        setTimeout(() => {
          if (ch !== liveChannel) return;
          supabase.removeChannel(ch);
          subscribeRealtime();
        }, 5000);
      }
    });
  liveChannel = ch;
}

// Coming back to the app after a while — refresh silently.
document.addEventListener("visibilitychange", () => {
  if (!document.hidden && state.loaded) scheduleReload();
});

// ------------------------------------------------------------------ helpers

const childById = (id) => state.children.find((c) => c.id === id);
const taskAttachments = (taskId, role) =>
  state.attachments.filter((a) => a.task_id === taskId && a.role === role);

function presence(child) {
  const seen = parseTs(child.last_seen_at);
  if (seen && serverNow() - seen < ONLINE_WINDOW_MS) return "online";
  if (state.devices.some((d) => d.profile_id === child.id)) return "reachable";
  return "offline";
}
const PRESENCE = {
  online: { dot: "on", label: "у мережі" },
  reachable: { dot: "reach", label: "офлайн (дійде сповіщення)" },
  offline: { dot: "off", label: "офлайн" },
};

// Best (newest) registered device of an assignee + how it compares to the
// latest published build — mirrors the desktop's version badge.
function childAppInfo(childId) {
  const devices = state.devices.filter((d) => d.profile_id === childId && d.app_version);
  if (!devices.length) return { version: "", outdated: false };
  const best = devices.reduce((a, b) =>
    (b.app_version_code || 0) > (a.app_version_code || 0) ? b : a);
  const latest = state.latestRelease;
  return {
    version: best.app_version,
    outdated: !!latest && (best.app_version_code || 0) < latest.version_code,
  };
}

// Avatar: real photo when set, initials on the brand color otherwise.
function avatar(child, size = 40) {
  const url = api.avatarUrl(child, size <= 40 ? 160 : 320);
  const color = child?.avatar_color || "#CDB1B1";
  const inner = url
    ? `<img src="${url}" alt="" loading="lazy">`
    : initials(child?.display_name);
  return `<div class="avatar" style="--c:${color};width:${size}px;height:${size}px;` +
    `font-size:${size * 0.42}px">${inner}</div>`;
}

function chip(text, cls) { return `<span class="chip ${cls}">${text}</span>`; }
function taskStatusChip(t) {
  const s = TASK_STATUS[t.status] || { label: t.status, cls: "" };
  return chip(s.label, s.cls);
}

// live earnings for a running job member (earned flows to the personal balance)
function liveStat(stat) {
  const running = stat.status === "running" && stat.running_since;
  const snap = parseTs(stat.snapshot_at) || serverNow();
  const extra = running ? Math.max(0, (serverNow() - snap) / 1000) : 0;
  const earnedSeconds = (stat.earned_seconds || 0) + extra;
  const totalSeconds = (stat.total_seconds || 0) + extra;
  // Tick the exact acorn-seconds accumulator and floor by 3600, exactly as
  // settle_job_member() does, so the live number is precisely what the next
  // settlement will credit and the balance never jumps when the cron lands.
  const acornSeconds = Number(stat.accrued_acorn_seconds || 0)
    + Math.floor(extra) * Number(stat.hourly_rate || 0);
  const earned = Math.floor(Math.max(0, acornSeconds) / 3600);
  return {
    running,
    earnedSeconds,
    totalSeconds,
    earned,
    // Non-negative by construction; a negative value would mean the snapshot
    // and the ledger disagree, so clamp instead of eating into the balance.
    uncredited: Math.max(0, earned - Number(stat.credited_amount || 0)),
  };
}

// Live personal balance = ledger sum + uncredited job accrual.
function childBalance(childId) {
  const ledgerSum = state.ledger
    .filter((e) => e.child_id === childId)
    .reduce((s, e) => s + Number(e.amount || 0), 0);
  const tail = state.jobStats
    .filter((s) => s.child_id === childId)
    .reduce((sum, s) => sum + liveStat(s).uncredited, 0);
  return ledgerSum + tail;
}

// Human labels + icon per ledger kind.
const LEDGER_KIND = {
  task: { label: "Завдання", icon: "✓" },
  job: { label: "Робота", icon: "⏱" },
  bonus: { label: "Бонус", icon: "★" },
  adjustment: { label: "Коригування", icon: "±" },
  withdrawal: { label: "Вивід", icon: "↑" },
  reversal: { label: "Повернення", icon: "↺" },
};

// Ledger source types that map onto a journal entity, so a transaction can
// open the story of whatever produced it.
const LEDGER_ENTITY = { task: "task", job: "job", withdrawal: "withdrawal", bonus: "bonus" };

function ledgerRowHtml(e) {
  const k = LEDGER_KIND[e.kind] || { label: e.kind, icon: "•" };
  const amt = Number(e.amount);
  const sign = amt >= 0 ? "+" : "";
  const title = e.note ? `${k.label} · ${escapeHtml(e.note)}` : k.label;
  const entity = LEDGER_ENTITY[e.source_type];
  const tap = entity && e.source_id
    ? ` tap" data-action="timeline" data-entity="${entity}" data-id="${e.source_id}`
    : "";
  return `<div class="ledger-row${tap}">
    <span class="lg-ic lg-${e.kind}">${k.icon}</span>
    <div class="lg-b"><div class="lg-t">${title}</div>
      <div class="lg-s">${dateTimeLocal(e.created_at)}${e.actor_name ? " · " + escapeHtml(e.actor_name) : ""}</div></div>
    <div class="lg-a ${amt >= 0 ? "pos" : "neg"}">${acornsHtml(amt, { signed: true })}</div></div>`;
}

// Weekly / monthly positive earnings from the ledger (for the balances card).
function earnedWindow(childId, days) {
  const cutoff = serverNow() - days * 86400 * 1000;
  return state.ledger.filter((e) =>
    e.child_id === childId &&
    ["task", "job", "bonus", "adjustment"].includes(e.kind) &&
    Number(e.amount) > 0 &&
    (parseTs(e.created_at) || 0) >= cutoff,
  ).reduce((s, e) => s + Number(e.amount), 0);
}

// ------------------------------------------------------------------ shell

const ICON = {
  tasks: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/></svg>`,
  jobs: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7.5v5l3.2 2"/></svg>`,
  assignees: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="3.6"/><path d="M5 20c0-3.6 3.2-5.6 7-5.6s7 2 7 5.6"/></svg>`,
  journal: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 6.5h11M8 12h11M8 17.5h11"/><circle cx="4" cy="6.5" r="1.1"/><circle cx="4" cy="12" r="1.1"/><circle cx="4" cy="17.5" r="1.1"/></svg>`,
  withdrawals: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="6" width="18" height="13" rx="2.5"/><path d="M3 10h18"/><path d="M16 14.5h2"/></svg>`,
  balances: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="9" r="5"/><path d="M15.5 5.3a5 5 0 0 1 0 9.4"/><path d="M9 6.8v4.4M7.4 8h3.2"/></svg>`,
};

const TABS = [
  { id: "tasks", label: "Завдання", icon: ICON.tasks },
  { id: "jobs", label: "Роботи", icon: ICON.jobs },
  { id: "money", label: "Гроші", icon: ICON.balances },
  { id: "assignees", label: "Виконавці", icon: ICON.assignees },
  { id: "journal", label: "Журнал", icon: ICON.journal },
];

function renderShell() {
  document.body.innerHTML =
    `<header id="topbar"></header><main id="view"></main>` +
    // The FAB lives OUTSIDE #view: the view's enter animation applies a
    // transform, which would turn position:fixed relative to it (the button
    // visibly jumped on every tab switch).
    `<button id="fab" class="fab hidden"></button>` +
    `<nav id="tabbar">${TABS.map((t) =>
      `<button class="tabbtn" data-action="tab" data-id="${t.id}">` +
      `<span class="ti">${t.icon}</span><span>${t.label}</span></button>`).join("")}` +
    `</nav><div id="sheet" class="sheet-overlay hidden"></div>`;
}

// One persistent floating action button, re-pointed per tab.
const FAB_BY_TAB = {
  tasks: { action: "task-create", label: "Нове завдання" },
  jobs: { action: "job-create", label: "Нова робота" },
  assignees: { action: "child-add", label: "Додати виконавця" },
};

function syncFab() {
  const el = $("#fab");
  if (!el) return;
  const cfg = state.loaded && !state.loadError ? FAB_BY_TAB[state.tab] : null;
  if (!cfg) { el.classList.add("hidden"); return; }
  el.textContent = `＋ ${cfg.label}`;
  el.dataset.action = cfg.action;
  el.classList.remove("hidden");
}

function renderTopbar() {
  const pending = state.tasks.filter((t) => t.status === "submitted").length;
  const wd = state.withdrawals.filter((w) => w.status === "requested" || w.status === "approved").length;
  const name = escapeHtml(state.parent?.display_name || "");
  $("#topbar").innerHTML =
    `<div class="tb-row"><div class="tb-brand">` +
    `<img class="tb-logo" src="./assets/logo.png" alt=""><div class="tb-title">Kabanchiki</div></div>` +
    `<div class="tb-sub">${name}</div></div>` +
    ((pending || wd)
      ? `<div class="tb-badges">` +
        (pending ? chip(`${pending} на перевірці`, "st-review") : "") +
        (wd ? chip(`${wd} на вивід`, "pay-await") : "") + `</div>`
      : "");
}

function render() {
  if (!$("#tabbar")) return;
  renderTopbar();
  [...document.querySelectorAll(".tabbtn")].forEach((b) =>
    b.classList.toggle("active", b.dataset.id === state.tab));
  const map = {
    tasks: renderTasks, jobs: renderJobs, money: renderMoney,
    assignees: renderAssignees, journal: renderJournal,
  };
  const v = view();
  v.innerHTML = state.loadError ? errorState()
    : !state.loaded ? skeletonList()
    : map[state.tab]();
  v.scrollTop = 0;
  syncFab();
  // replay the entering animation on tab switches
  v.style.animation = "none";
  void v.offsetHeight;
  v.style.animation = "";
}

function skeletonList() {
  return `<div class="skel-seg skel"></div><div class="list">` +
    Array.from({ length: 6 }, () => `<div class="skel skel-card"></div>`).join("") + `</div>`;
}

function errorState() {
  return `<div class="empty"><img class="empty-logo" src="./assets/logo.png" alt="">` +
    `<p>Не вдалося завантажити дані.<br>Перевірте інтернет і спробуйте ще раз.</p>` +
    `<button class="btn gate-retry" data-action="reload-data">Повторити</button></div>`;
}

// ------------------------------------------------------------------ TASKS

const TASK_FILTERS = [
  { id: "submitted", label: "На перевірці" },
  { id: "active", label: "Активні" },
  { id: "done", label: "Виконані" },
  { id: "all", label: "Усі" },
];

function filterTasks() {
  const f = state.taskFilter;
  return state.tasks.filter((t) => {
    if (f === "all") return true;
    if (f === "submitted") return t.status === "submitted";
    if (f === "done") return t.status === "done";
    if (f === "active") return ["new", "in_progress", "paused", "declined"].includes(t.status);
    return true;
  });
}

function renderTasks() {
  const seg = `<div class="segment">${TASK_FILTERS.map((f) => {
    const n = f.id === "submitted"
      ? state.tasks.filter((t) => t.status === "submitted").length : 0;
    return `<button class="seg ${state.taskFilter === f.id ? "on" : ""}" ` +
      `data-action="task-filter" data-id="${f.id}">${f.label}` +
      (n ? `<i>${n}</i>` : "") + `</button>`;
  }).join("")}</div>`;

  // Author filter appears once the family has more than one owner.
  const authorName = state.parents.find((p) => p.id === state.taskAuthor);
  const author = state.parents.length > 1
    ? ui.pickField({
        action: "author-pick", compact: true,
        value: authorName ? (authorName.display_name || authorName.email) : "",
        placeholder: "Усі автори",
        extra: 'style="margin-bottom:12px"',
      })
    : "";

  const rows = filterTasks()
    .filter((t) => !state.taskAuthor || t.created_by === state.taskAuthor);
  const list = rows.length ? rows.map(taskCard).join("")
    : emptyState("Немає завдань у цій вкладці");

  return seg + author + `<div class="list">${list}</div>`;
}

function deadlineChip(t) {
  if (t.status === "done" || t.status === "declined") return "";
  const d = deadline(t.deadline_at);
  if (d.state === "none") return "";
  const cls = d.state === "overdue" ? "st-declined" : d.state === "soon" ? "st-pause" : "";
  return chip(`⏰ ${escapeHtml(d.text)}`, cls);
}

function taskCard(t) {
  const child = t.profiles || childById(t.child_id) || {};
  const diff = DIFFICULTY_COLORS[t.difficulty] || "#8598B5";
  const reward = t.reward_type === "hourly"
    ? `${acornsHtml(t.reward_amount)}/год` : acornsHtml(t.reward_amount);
  return `<div class="card tap" data-action="task-detail" data-id="${t.id}">
    <div class="card-l"><span class="diffbar" style="background:${diff}"></span>
      ${avatar(child, 34)}</div>
    <div class="card-b">
      <div class="card-t">${escapeHtml(t.title)}</div>
      <div class="card-s">${escapeHtml(child.display_name || "")} · ${reward}</div>
      <div class="chips">${taskStatusChip(t)} ${deadlineChip(t)}</div>
    </div>
    <div class="card-r">›</div></div>`;
}

// Current galleries of the open detail sheet: index -> attachment row.
let galleryCtx = { task: [], proof: [] };

async function galleryHtml(atts, group) {
  if (!atts.length) return "";
  const urls = await Promise.all(atts.map((a) => api.attachmentUrl(a, true)));
  return `<div class="gal">${urls.map((u, i) =>
    `<button type="button" class="gcell" data-action="gal-open" data-g="${group}" data-i="${i}">
      <img src="${u}" alt="" loading="lazy"></button>`).join("")}</div>`;
}

async function openTaskDetail(id) {
  const t = state.tasks.find((x) => x.id === id);
  if (!t) return;
  const child = t.profiles || childById(t.child_id) || {};

  galleryCtx = { task: taskAttachments(t.id, "task"), proof: taskAttachments(t.id, "proof") };
  const [media, proofGal] = await Promise.all([
    galleryHtml(galleryCtx.task, "task"),
    galleryHtml(galleryCtx.proof, "proof"),
  ]);
  const reward = t.reward_type === "hourly"
    ? `${acornsHtml(t.reward_amount)}/год` : acornsHtml(t.reward_amount);

  let actions = "";
  if (t.status === "submitted") {
    // Primary decision full-width; the two alternatives share the next row.
    actions =
      `<button class="btn ok" data-action="task-approve" data-id="${t.id}">Прийняти</button>` +
      `</div><div class="actions sub">` +
      `<button class="btn warn" data-action="task-rework" data-id="${t.id}">На доробку</button>` +
      `<button class="btn danger" data-action="task-reject" data-id="${t.id}">Відхилити</button>`;
  } else if (t.status === "done" && t.earned_amount != null) {
    actions = `<div class="paid-note">✓ Нараховано на баланс: <b>${acornsHtml(t.earned_amount)}</b></div>`;
  }

  const rows = [];
  if (t.description) rows.push(field("Опис", escapeHtml(t.description)));
  if (t.created_by_name) rows.push(field("Створив", escapeHtml(t.created_by_name)));
  if (t.requirements) rows.push(field("Вимоги", escapeHtml(t.requirements)));
  rows.push(field("Тип", t.completion_mode === "simple" ? "Без таймера" : "З таймером"));
  if (t.total_seconds) rows.push(field("Витрачено часу", duration(t.total_seconds)));
  if (t.earned_amount != null) rows.push(field("Нараховано", acornsHtml(t.earned_amount)));
  if (t.decline_reason) rows.push(field("Коментар", escapeHtml(t.decline_reason)));
  if (t.proof_text_content) rows.push(field("Звіт (текст)", escapeHtml(t.proof_text_content)));

  const proof = proofGal
    ? `<div class="field-l" style="margin-top:10px">Звіт (фото)</div>${proofGal}` : "";

  openSheet(`
    <div class="sheet-head">${avatar(child, 44)}
      <div><div class="sheet-title">${escapeHtml(t.title)}</div>
      <div class="sheet-sub">${escapeHtml(child.display_name || "")} · ${reward}</div></div></div>
    <div class="chips lg">${taskStatusChip(t)} ${deadlineChip(t)}</div>
    ${media}${rows.join("")}${proof}
    <div class="actions">${actions}</div>
    <div class="actions sub">
      ${t.status === "new"
        ? `<button class="btn ghost" data-action="task-edit" data-id="${t.id}">Редагувати</button>` : ""}
      <button class="btn ghost" data-action="task-duplicate" data-id="${t.id}">Продублювати</button>
      <button class="btn ghost danger" data-action="task-delete" data-id="${t.id}">Видалити</button>
    </div>`);
}

async function openGallery(group, index) {
  const atts = galleryCtx[group] || [];
  if (!atts.length) return;
  const urls = await Promise.all(atts.map((a) => api.attachmentUrl(a, false)));
  ui.lightbox(urls, index);
}

// ------------------------------------------------------------------ JOBS

function renderJobs() {
  if (!state.jobs.length) return emptyState("Ще немає робіт");
  return `<div class="list">${state.jobs.map(jobCard).join("")}</div>`;
}

function jobCard(job) {
  const members = state.jobStats.filter((s) => s.job_id === job.id);
  const running = job.status === "running";
  const memberRows = members.map((s) => {
    const child = childById(s.child_id) || {};
    const live = liveStat(s);
    return `<div class="member">${avatar(child, 30)}
      <div class="member-b"><div class="member-n">${escapeHtml(child.display_name || "")}</div>
      <div class="member-s">Зароблено: <b id="bal-${job.id}-${s.child_id}">${acornsHtml(live.earned)}</b>
        · <span id="ern-${job.id}-${s.child_id}">${duration(live.earnedSeconds)}</span></div></div></div>`;
  }).join("") || `<div class="member-empty">Немає виконавців</div>`;

  const timer = members.length ? liveStat(members[0]).totalSeconds : job._t || 0;
  const ctrl = running
    ? `<button class="btn danger" data-action="job-stop" data-id="${job.id}">Стоп</button>`
    : `<button class="btn ok" data-action="job-start" data-id="${job.id}">Старт</button>`;

  return `<div class="card job ${running ? "live" : ""}">
    <div class="job-top">
      <div><div class="card-t">${escapeHtml(job.title)}</div>
        <div class="card-s">${acornsHtml(job.hourly_rate)}/год</div></div>
      <div class="job-timer ${running ? "run" : ""}" id="tmr-${job.id}">${duration(timer)}</div>
    </div>
    <div class="members">${memberRows}</div>
    <div class="job-actions">
      ${ctrl}
      <div class="job-actions-row">
        <button class="btn ghost sm" data-action="job-edit" data-id="${job.id}">Редагувати</button>
        <button class="btn ghost sm" data-action="job-archive" data-id="${job.id}">Архівувати</button>
        <button class="btn ghost danger sm" data-action="job-delete" data-id="${job.id}">Видалити</button>
      </div>
    </div></div>`;
}

// Job details from the journal — same info as the jobs tab card, in a sheet.
function openJobDetail(id) {
  const job = state.jobs.find((j) => j.id === id);
  if (!job) return;
  const running = job.status === "running";
  const members = state.jobStats.filter((s) => s.job_id === job.id);
  const memberRows = members.map((s) => {
    const child = childById(s.child_id) || {};
    const live = liveStat(s);
    return field(escapeHtml(child.display_name || "—"),
      `${acornsHtml(live.earned)} · ${duration(live.earnedSeconds)}`);
  }).join("") || field("Виконавці", `<span class="muted">нікого не призначено</span>`);
  const timer = members.length ? liveStat(members[0]).totalSeconds : 0;

  openSheet(`
    <div class="sheet-head">
      <div><div class="sheet-title">${escapeHtml(job.title)}</div>
      <div class="sheet-sub">${acornsHtml(job.hourly_rate)}/год</div></div></div>
    <div class="chips lg">
      ${chip(running ? "Виконується" : "Зупинено", running ? "st-run" : "st-pause")}
      ${chip(`⏱ ${duration(timer)}`, "")}
    </div>
    ${job.description ? field("Опис", escapeHtml(job.description)) : ""}
    ${memberRows}
    <div class="actions">
      ${running
        ? `<button class="btn danger" data-action="jd-stop" data-id="${job.id}">Стоп</button>`
        : `<button class="btn ok" data-action="jd-start" data-id="${job.id}">Старт</button>`}
    </div>
    <div class="actions sub">
      <button class="btn ghost" data-action="job-edit" data-id="${job.id}">Редагувати</button>
      <button class="btn ghost" data-action="jd-archive" data-id="${job.id}">Архівувати</button>
      <button class="btn ghost danger" data-action="jd-delete" data-id="${job.id}">Видалити</button>
    </div>`);
}

// ------------------------------------------------------------------ ASSIGNEES

function renderAssignees() {
  if (!state.children.length) return emptyState("Ще немає виконавців");
  const cards = state.children.map((c) => {
    const p = PRESENCE[presence(c)];
    const app = childAppInfo(c.id);
    const tasks = state.tasks.filter((t) =>
      t.child_id === c.id && ["new", "in_progress", "paused", "submitted"].includes(t.status)).length;
    const bal = childBalance(c.id);
    return `<div class="card tap" data-action="child-detail" data-id="${c.id}">
      ${avatar(c, 44)}
      <div class="card-b"><div class="card-t">${escapeHtml(c.display_name)}
        ${c.blocked ? chip("заблоковано", "st-declined") : ""}
        ${app.outdated ? chip("є оновлення", "st-pause") : ""}</div>
        <div class="card-s"><span class="dot ${p.dot}"></span>${p.label}</div>
        <div class="card-s2">${tasks} активних · баланс <span data-live-bal="${c.id}">${acornsHtml(bal)}</span></div></div>
      <div class="card-r">›</div></div>`;
  }).join("");
  return `<div class="list">${cards}</div>`;
}

function openChildDetail(id) {
  const c = childById(id);
  if (!c) return;
  const p = PRESENCE[presence(c)];
  // Compact balance only — detailed history lives in the "Баланси" tab.
  const balLine = field("Баланс", `<b class="bal-inline" data-live-bal="${id}">${acornsHtml(childBalance(id))}</b>`);

  // Latest reported location (newest first in state.locations).
  const loc = state.locations.find((l) => l.child_id === id);
  const coords = loc ? `${loc.lat.toFixed(5)}, ${loc.lng.toFixed(5)}` : "";
  const locLine = loc
    ? field("Локація",
        `<span id="loc-place">${escapeHtml(loc.locality || coords)}</span>` +
        ` · ${dateTimeLocal(loc.created_at)} · ` +
        `<a class="loc-link" href="https://www.openstreetmap.org/?mlat=${loc.lat}&mlon=${loc.lng}#map=16/${loc.lat}/${loc.lng}" target="_blank" rel="noopener">на мапі</a>`)
    : field("Локація", `<span class="muted">даних ще немає — вмикається на телефоні виконавця (Профіль → Геолокація)</span>`);

  // App version of the assignee's phone (+ "update available" hint).
  const dev = state.devices.filter((d) => d.profile_id === id && d.app_version)
    .sort((a, b) => (b.app_version_code || 0) - (a.app_version_code || 0))[0];
  const app = childAppInfo(id);
  const appLine = app.version
    ? field("Версія застосунку",
        `${escapeHtml(app.version)}` +
        (app.outdated ? ` · ${chip(`є оновлення${state.latestRelease ? " до " + escapeHtml(state.latestRelease.version_name) : ""}`, "st-pause")}` : "") +
        (dev ? ` · <span class="muted">востаннє ${dateTimeLocal(dev.updated_at)}</span>` : ""))
    : field("Версія застосунку", `<span class="muted">пристрій ще не підключено</span>`);

  openSheet(`
    <div class="sheet-head">${avatar(c, 48)}
      <div><div class="sheet-title">${escapeHtml(c.display_name)}</div>
      <div class="sheet-sub"><span class="dot ${p.dot}"></span>${p.label} · @${escapeHtml(c.username)}</div></div></div>
    ${balLine}
    ${appLine}
    ${locLine}
    <div class="actions">
      <button class="btn" data-action="child-adjust" data-id="${id}">Коригувати баланс</button>
      ${c.blocked
        ? `<button class="btn ok" data-action="child-unblock" data-id="${id}">Розблокувати</button>`
        : `<button class="btn warn" data-action="child-block" data-id="${id}">Заблокувати</button>`}
    </div>
    <div class="actions sub">
      <button class="btn ghost" data-action="child-edit" data-id="${id}">Редагувати</button>
      <button class="btn ghost" data-action="child-password" data-id="${id}">Змінити пароль</button>
      <button class="btn ghost danger" data-action="child-delete" data-id="${id}">Видалити</button>
    </div>`);

  // The phone's geocoder sometimes stores no locality name (rural point,
  // offline maintenance-window wake). Resolve it from OpenStreetMap, show it,
  // and write it back so the desktop/Android read the name from the DB too
  // (one lookup per point, system-wide).
  if (loc && !loc.locality) {
    reverseGeocode(loc.lat, loc.lng).then((name) => {
      if (!name) return;
      const el = $("#loc-place");
      if (el) el.textContent = name;
      loc.locality = name; // reflect locally
      api.setLocationPlace(loc.id, name).catch(() => { /* best effort */ });
    });
  }
}

// Reverse-geocode via OpenStreetMap Nominatim (same provider as the "на мапі"
// link). Cached per rounded coordinate; failures fall back to coordinates.
const geocodeCache = new Map();
async function reverseGeocode(lat, lng) {
  const key = `${lat.toFixed(4)},${lng.toFixed(4)}`;
  if (geocodeCache.has(key)) return geocodeCache.get(key);
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2` +
      `&lat=${lat}&lon=${lng}&zoom=13&accept-language=uk`;
    const resp = await fetch(url, { headers: { Accept: "application/json" } });
    const data = await resp.json();
    const a = data.address || {};
    const name = a.village || a.town || a.city || a.hamlet || a.municipality ||
      a.suburb || a.county || a.state || data.name || "";
    geocodeCache.set(key, name);
    return name;
  } catch {
    return "";
  }
}

// ---- child create/edit with avatar -----------------------------------------

const AVATAR_COLORS = ["#CDB1B1", "#A5B8CD", "#9DBFA9", "#D9B98A", "#C99A9A", "#A79AC9", "#8FB7C9", "#B8A98F"];

function colorSwatches(name, current) {
  return `<div class="picks" data-swatches="${name}">${AVATAR_COLORS.map((c) => `
    <label class="pick" style="padding:6px">
      <input type="radio" name="${name}" value="${c}" ${c.toLowerCase() === String(current).toLowerCase() ? "checked" : ""}>
      <span class="avatar" style="--c:${c};width:26px;height:26px"></span>
    </label>`).join("")}</div>`;
}
const swatchValue = (name) =>
  document.querySelector(`input[name="${name}"]:checked`)?.value || AVATAR_COLORS[0];

// Pending avatar choice for the open child form:
// undefined = unchanged, null = remove, Blob = new photo.
let childAvatarBlob;
let childAvatarPreview = "";

function avatarEditor(c) {
  const url = childAvatarPreview || (c ? api.avatarUrl(c, 320) : "");
  const color = c?.avatar_color || AVATAR_COLORS[0];
  const inner = url ? `<img src="${url}" alt="">` : initials(c?.display_name || "?");
  return `<div class="ava-row">
    <div class="avatar" id="ava-preview" style="--c:${color};width:72px;height:72px;font-size:30px">${inner}</div>
    <div class="ava-actions">
      <button type="button" class="btn ghost sm" data-action="ava-pick">${url ? "Змінити фото" : "Додати фото"}</button>
      ${url ? `<button type="button" class="btn ghost danger sm" data-action="ava-clear">Прибрати</button>` : ""}
    </div>
    <input type="file" accept="image/*" hidden id="ava-file">
  </div>`;
}

function wireAvatarEditor() {
  const file = $("#ava-file");
  if (!file) return;
  file.addEventListener("change", () => {
    const f = file.files[0];
    file.value = "";
    if (!f) return;
    ui.cropSheet(f, (blob) => {
      childAvatarBlob = blob;
      if (childAvatarPreview) URL.revokeObjectURL(childAvatarPreview);
      childAvatarPreview = URL.createObjectURL(blob);
      const prev = $("#ava-preview");
      if (prev) prev.innerHTML = `<img src="${childAvatarPreview}" alt="">`;
    });
  });
}

function childCreateForm() {
  childAvatarBlob = undefined;
  childAvatarPreview = "";
  openSheet(`
    <div class="sheet-title">Новий виконавець</div>
    ${avatarEditor(null)}
    <label class="fl">Ім'я<input id="c-name" class="inp"></label>
    ${fieldErr("cname")}
    <label class="fl">Логін (лат., цифри, _)<input id="c-user" class="inp" autocapitalize="none"></label>
    ${fieldErr("cuser")}
    <label class="fl">Пароль<input id="c-pass" class="inp" type="text"></label>
    ${fieldErr("cpass")}
    <div class="fl">Колір (тло без фото)</div>
    ${colorSwatches("c-color", AVATAR_COLORS[0])}
    <div class="actions"><button class="btn ghost" data-action="close">Скасувати</button>
      <button class="btn" data-main="1" data-action="child-save">Створити</button></div>`);
  wireAvatarEditor();
}

async function saveChild() {
  clearErrs();
  const name = $("#c-name").value.trim();
  const user = $("#c-user").value.trim().toLowerCase();
  const pass = $("#c-pass").value;
  let bad = false;
  if (!name) { setErr("cname", "Вкажіть ім'я"); bad = true; }
  if (!/^[a-z0-9_]{3,24}$/.test(user)) { setErr("cuser", "3–24 символи: a–z, 0–9, _"); bad = true; }
  if (pass.length < 3) { setErr("cpass", "Пароль закороткий"); bad = true; }
  if (bad) return;
  const blob = childAvatarBlob;
  await submitSheet(async () => {
    await api.createChild(user, name, pass, swatchValue("c-color"));
    if (blob) {
      const children = await api.listChildren();
      const fresh = children.find((c) => c.username === user);
      if (fresh) await api.setChildAvatar(fresh.id, blob);
    }
  }, "Виконавця створено");
}

function childEditForm(id) {
  const c = childById(id);
  if (!c) return;
  childAvatarBlob = undefined;
  childAvatarPreview = "";
  openSheet(`
    <div class="sheet-title">Редагувати виконавця</div>
    ${avatarEditor(c)}
    <label class="fl">Ім'я<input id="ce-name" class="inp" value="${escAttr(c.display_name)}"></label>
    ${fieldErr("cename")}
    <div class="fl">Колір (тло без фото)</div>
    ${colorSwatches("ce-color", c.avatar_color || AVATAR_COLORS[0])}
    <div class="actions"><button class="btn ghost" data-action="close">Скасувати</button>
      <button class="btn" data-main="1" data-action="child-edit-save" data-id="${id}">Зберегти</button></div>`);
  wireAvatarEditor();
}

async function saveChildEdit(id) {
  clearErrs();
  const name = $("#ce-name").value.trim();
  if (!name) return setErr("cename", "Вкажіть ім'я");
  const blob = childAvatarBlob;
  await submitSheet(async () => {
    await api.updateChild(id, name, swatchValue("ce-color"));
    if (blob) await api.setChildAvatar(id, blob);
    else if (blob === null) await api.clearChildAvatar(id);
  }, "Збережено");
}

// ------------------------------------------------------------------ JOURNAL

const JOURNAL_FILTERS = [
  { id: "", label: "Усі" },
  { id: "task", label: "Завдання" },
  { id: "job", label: "Роботи" },
  { id: "withdrawal", label: "Виводи" },
  { id: "bonus", label: "Бонуси" },
];

const EVENT_ENTITY = {
  task: "Завдання", job: "Робота", withdrawal: "Вивід",
  bonus: "Бонус", child: "Виконавець",
};
const EVENT_ACTION = {
  created: { label: "створено", cls: "st-new" },
  updated: { label: "змінено", cls: "st-new" },
  deleted: { label: "видалено", cls: "st-declined" },
  started: { label: "запущено", cls: "st-run" },
  paused: { label: "пауза", cls: "st-pause" },
  stopped: { label: "зупинено", cls: "st-pause" },
  archived: { label: "в архів", cls: "" },
  submitted: { label: "на перевірку", cls: "st-review" },
  approved: { label: "прийнято", cls: "st-done" },
  completed: { label: "виконано", cls: "st-done" },
  rejected: { label: "відхилено", cls: "st-declined" },
  rework: { label: "на доробку", cls: "st-pause" },
  declined: { label: "відмова", cls: "st-declined" },
  requested: { label: "запит", cls: "pay-await" },
  paid: { label: "виплачено", cls: "pay-paid" },
  confirmed: { label: "підтверджено", cls: "st-done" },
  overdue: { label: "прострочено", cls: "st-declined" },
  payment_changed: { label: "оплата", cls: "pay-paid" },
  granted: { label: "нараховано", cls: "st-done" },
  assigned: { label: "призначено", cls: "st-new" },
  unassigned: { label: "знято", cls: "" },
  blocked: { label: "заблоковано", cls: "st-declined" },
  unblocked: { label: "розблоковано", cls: "st-done" },
  status_changed: { label: "статус", cls: "st-new" },
};

const JOURNAL_PERIODS = [
  { id: "", label: "Весь час" },
  { id: "today", label: "Сьогодні" },
  { id: "7d", label: "7 днів" },
  { id: "30d", label: "30 днів" },
];

function journalRows() {
  const q = state.journalQuery.trim().toLowerCase();
  let cutoff = 0;
  if (state.journalPeriod === "today") {
    const d = new Date(); d.setHours(0, 0, 0, 0); cutoff = d.getTime();
  } else if (state.journalPeriod === "7d") {
    cutoff = Date.now() - 7 * 86400_000;
  } else if (state.journalPeriod === "30d") {
    cutoff = Date.now() - 30 * 86400_000;
  }
  return state.events.filter((e) => {
    if (state.journalFilter && e.entity !== state.journalFilter) return false;
    if (state.journalChild && e.child_id !== state.journalChild) return false;
    if (cutoff && (parseTs(e.created_at) || 0) < cutoff) return false;
    if (q) {
      const child = childById(e.child_id) || {};
      const hay = `${e.entity_title || ""} ${e.actor_name || ""} ` +
        `${child.display_name || ""} ${(e.details || {}).note || ""}`.toLowerCase();
      if (!hay.includes(q)) return false;
    }
    return true;
  });
}

function journalFeedHtml() {
  const rows = journalRows();
  return rows.length
    ? `<div class="list">${rows.slice(0, 150).map(journalEvent).join("")}</div>`
    : emptyState("Немає подій за цими фільтрами");
}

// ------------------------------------------------------------------ MONEY (Гроші)

// One money tab with a top segment: balances (cards + operations) / withdrawals.
function renderMoney() {
  const tabs = [{ id: "balances", label: "Баланси" }, { id: "withdrawals", label: "Виводи" }];
  const wd = state.withdrawals.filter((w) => w.status === "requested" || w.status === "approved").length;
  const seg = `<div class="segment">${tabs.map((t) =>
    `<button class="seg ${state.moneyTab === t.id ? "on" : ""}" data-action="money-tab" data-id="${t.id}">` +
    `${t.label}${t.id === "withdrawals" && wd ? ` <span class="seg-badge">${wd}</span>` : ""}</button>`).join("")}</div>`;
  return seg + (state.moneyTab === "withdrawals" ? renderWithdrawals() : renderBalances());
}

// ------------------------------------------------------------------ BALANCES

function balanceCard(c) {
  const bal = childBalance(c.id);
  return `<div class="card bal-card">
    <div class="bal-card-top">${avatar(c, 40)}
      <div class="card-b"><div class="card-t">${escapeHtml(c.display_name)}</div>
        <div class="card-s2">тиждень ${acornWords(earnedWindow(c.id, 7))} · місяць ${acornWords(earnedWindow(c.id, 30))}</div></div>
      <div class="bal-card-amt" data-live-bal="${c.id}">${acornsHtml(bal)}</div></div>
    <button class="btn payout-btn" data-action="child-payout" data-id="${c.id}" ${bal > 0 ? "" : "disabled"}>Виплатити</button>
    <div class="actions row">
      <button class="btn ghost sm" data-action="child-adjust" data-id="${c.id}">Коригувати</button>
      <button class="btn ghost sm ${state.ledgerChild === c.id ? "on" : ""}" data-action="bal-history" data-id="${c.id}">Історія</button>
    </div></div>`;
}

function renderBalances() {
  if (!state.children.length) return emptyState("Ще немає виконавців");
  const cards = state.children.map(balanceCard).join("");
  const sel = state.ledgerChild;
  const ops = state.ledger.filter((e) => !sel || e.child_id === sel).slice(0, 120);
  const head = `<div class="ops-head">
    <span>Операції${sel ? " · " + escapeHtml(childById(sel)?.display_name || "") : ""}</span>
    ${sel ? `<button class="btn ghost sm" data-action="bal-history-clear">Усі</button>` : ""}</div>`;
  const opsHtml = ops.length
    ? `<div class="card ops-card">${ops.map(ledgerRowHtml).join("")}</div>`
    : emptyState("Ще немає операцій");
  return `<div class="list">${cards}</div>${head}${opsHtml}<p class="copyright">${COPYRIGHT}</p>`;
}

// ------------------------------------------------------------------ WITHDRAWALS

const WD_FILTERS = [
  { id: "", label: "Усі" },
  { id: "requested", label: "Запити" },
  { id: "approved", label: "Схвалені" },
  { id: "paid", label: "Виплачені" },
  { id: "confirmed", label: "Закриті" },
  { id: "rejected", label: "Відхилені" },
];

function receiptsHtml(w) {
  const rec = state.attachments.filter((a) => a.withdrawal_id === w.id && a.role === "receipt");
  if (!rec.length) return "";
  return `<div class="rcpts">` + rec.map((a, i) =>
    `<button class="rcpt" data-action="wd-receipt" data-id="${w.id}" data-idx="${i}">📎 Квитанція ${rec.length > 1 ? i + 1 : ""}</button>`).join("") + `</div>`;
}

function withdrawalCard(w) {
  const child = w.profiles || childById(w.child_id) || {};
  const s = WITHDRAWAL_STATUS[w.status] || { label: w.status, cls: "" };
  const methodChip = w.method ? " " + chip(w.method === "card" ? "на карту" : "готівка", "") : "";
  const lines = [];
  if (w.comment) lines.push(`<div class="card-s">Коментар: ${escapeHtml(w.comment)}</div>`);
  if (w.status === "rejected" && w.reject_reason) {
    const reason = w.reject_reason === "not_received" ? "Виконавець не отримав готівку"
      : w.reject_reason === "cancelled" ? "Скасовано виконавцем"
      : "Причина: " + escapeHtml(w.reject_reason);
    lines.push(`<div class="card-s neg">${reason}</div>`);
  }
  if (w.paid_at) lines.push(`<div class="card-s muted">виплачено ${dateTimeLocal(w.paid_at)}` +
    (w.confirmed_at ? ` · підтверджено ${dateTimeLocal(w.confirmed_at)}` : "") + `</div>`);
  const history = `<button class="btn ghost sm" data-action="timeline"
      data-entity="withdrawal" data-id="${w.id}">Історія</button>`;
  const act = w.status === "requested"
    ? `<div class="actions row">${history}
       <button class="btn danger sm" data-action="wd-decline" data-id="${w.id}">Відхилити</button>
       <button class="btn ok sm" data-action="wd-approve" data-id="${w.id}">Схвалити</button></div>`
    : (w.status === "approved"
      ? `<div class="actions row">${history}
         <button class="btn sm" data-action="wd-pay" data-id="${w.id}">Виплатити…</button></div>`
      : `<div class="actions row">${history}</div>`);
  return `<div class="card col">
    <div class="card-row">${avatar(child, 36)}<div class="card-b">
      <div class="card-t">Вивід ${acornsHtml(w.amount)}</div>
      <div class="card-s">${escapeHtml(child.display_name || "")} · ${dateTimeLocal(w.requested_at)}</div>
      <div class="chips">${chip(s.label, s.cls)}${methodChip}</div>
      ${lines.join("")}${receiptsHtml(w)}</div></div>${act}</div>`;
}

function renderWithdrawals() {
  const seg = `<div class="segment wrap">${WD_FILTERS.map((f) =>
    `<button class="seg ${state.wdStatus === f.id ? "on" : ""}" ` +
    `data-action="wd-filter" data-id="${f.id}">${f.label}</button>`).join("")}</div>`;
  const childName = childById(state.wdChild)?.display_name || "";
  const controls = `<div class="pickrow">
    ${ui.pickField({ action: "wd-child-pick", compact: true, value: childName, placeholder: "Усі виконавці" })}</div>`;

  let list = state.withdrawals.slice();
  if (state.wdStatus) list = list.filter((w) => w.status === state.wdStatus);
  if (state.wdChild) list = list.filter((w) => w.child_id === state.wdChild);

  const body = list.length
    ? `<div class="list">${list.map(withdrawalCard).join("")}</div>`
    : emptyState("Немає виводів за цими фільтрами");
  return seg + controls + body + `<p class="copyright">${COPYRIGHT}</p>`;
}

function renderJournal() {
  // Withdrawals that need the owner: requested (approve/reject) or approved (pay).
  const attention = state.withdrawals.filter((w) =>
    w.status === "requested" || w.status === "approved");
  const attentionHtml = attention.length
    ? `<div class="att-title">Потребують уваги</div><div class="list att">` +
      attention.map(journalWithdrawal).join("") + `</div>`
    : "";

  const seg = `<div class="segment">${JOURNAL_FILTERS.map((f) =>
    `<button class="seg ${state.journalFilter === f.id ? "on" : ""}" ` +
    `data-action="journal-filter" data-id="${f.id}">${f.label}</button>`).join("")}</div>`;

  const childName = childById(state.journalChild)?.display_name || "";
  const periodLabel = JOURNAL_PERIODS.find((p) => p.id === state.journalPeriod && p.id)?.label || "";
  const controls = `<div class="pickrow">
    ${ui.pickField({ action: "j-child-pick", compact: true, value: childName, placeholder: "Усі виконавці" })}
    ${ui.pickField({ action: "j-period-pick", compact: true, value: periodLabel, placeholder: "Весь час" })}
  </div>
  <input id="j-search" class="inp jsearch" placeholder="Пошук: завдання, виконавець, нотатка…"
         value="${escAttr(state.journalQuery)}">`;

  return attentionHtml + seg + controls +
    `<div id="j-feed">${journalFeedHtml()}</div>` +
    `<p class="copyright">${COPYRIGHT}</p>`;
}

function journalEvent(e) {
  const child = childById(e.child_id) || {};
  const meta = EVENT_ACTION[e.action] || { label: e.action, cls: "" };
  const details = e.details || {};
  const amount = details.amount ?? details.earned;
  const who = e.actor_kind === "system" ? "Система" : (e.actor_name || child.display_name || "—");
  // A granted bonus that still exists stays manageable from its entry.
  const liveBonus = e.entity === "bonus" && e.action === "granted"
    && state.bonuses.some((b) => b.id === e.entity_id);
  const bonusActs = liveBonus
    ? `<div class="actions row">
        <button class="btn ghost sm" data-action="bonus-edit" data-id="${e.entity_id}">Редагувати</button>
        <button class="btn ghost danger sm" data-action="bonus-delete" data-id="${e.entity_id}">Видалити</button>
      </div>` : "";

  const inner = `
    ${avatar(e.actor_kind === "child" ? child : { display_name: who, avatar_color: "#CDB1B1" }, 30)}
    <div class="card-b">
      <div class="card-s"><b>${escapeHtml(who)}</b> · ${dateTimeLocal(e.created_at)}</div>
      <div class="card-t sm">${escapeHtml(e.entity_title || "")}` +
      (child.display_name && e.entity !== "child" ? ` — ${escapeHtml(child.display_name)}` : "") + `</div>
      <div class="chips">${chip(`${EVENT_ENTITY[e.entity] || e.entity} · ${meta.label}`, meta.cls)}` +
      (details.note ? chip(escapeHtml(details.note), "") : "") + `</div>
    </div>` +
    (amount != null ? `<div class="card-r sm">${acornsHtml(amount)}</div>` : "") +
    `<div class="card-r">›</div>`;

  if (bonusActs) {
    return `<div class="card col"><div class="card-row">${inner}</div>${bonusActs}</div>`;
  }
  // Tapping an entry opens that entity's full story; the sheet itself offers a
  // jump to the live task/job when one still exists.
  return `<div class="card tap" data-action="timeline"
      data-entity="${e.entity}" data-id="${e.entity_id}">${inner}</div>`;
}

// ---------------------------------------------------------------- entity timeline

/** Human line under a timeline step: actor plus whatever the event carries. */
function timelineMeta(e) {
  const d = e.details || {};
  const bits = [];
  const who = e.actor_kind === "system" ? "Система" : (e.actor_name || "");
  if (who) bits.push(`<b>${escapeHtml(who)}</b>`);
  const amount = d.amount ?? d.earned;
  if (amount != null) bits.push(acornWords(amount));
  if (d.method) bits.push(d.method === "card" ? "на карту" : "готівка");
  if (d.note) bits.push(`«${escapeHtml(d.note)}»`);
  if (d.reason) {
    const r = d.reason === "not_received" ? "не отримано"
      : d.reason === "cancelled" ? "скасовано виконавцем" : escapeHtml(d.reason);
    bits.push(`«${r}»`);
  }
  if (d.old_name) bits.push(`було: ${escapeHtml(d.old_name)}`);
  return bits.join(" · ");
}

/** The story of one entity, step by step, as a card. */
async function timelineSheet(entity, entityId) {
  const label = EVENT_ENTITY[entity] || entity;
  openSheet(`
    <div class="sheet-title">Історія · ${label}</div>
    <div class="tl-load">Завантаження…</div>`);
  let steps = [];
  try {
    steps = await api.entityTimeline(entity, entityId);
  } catch (e) {
    console.error("timeline failed", e);
    const box = $("#sheet .tl-load");
    if (box) box.textContent = "Не вдалося завантажити історію";
    return;
  }
  const card = $("#sheet .sheet-card");
  if (!card) return;   // sheet closed while loading

  const title = steps.length ? steps[steps.length - 1].entity_title : "";
  // Context: who it belongs to, taken from whichever row we still have loaded.
  const src = entity === "task" ? state.tasks.find((t) => t.id === entityId)
    : entity === "withdrawal" ? state.withdrawals.find((w) => w.id === entityId)
      : entity === "bonus" ? state.bonuses.find((b) => b.id === entityId) : null;
  const child = src ? childById(src.child_id) : (entity === "child" ? childById(entityId) : null);

  const rows = steps.map((e) => {
    const meta = EVENT_ACTION[e.action] || { label: e.action, cls: "" };
    const sub = timelineMeta(e);
    return `<li class="tl-step">
      <span class="tl-dot ${meta.cls}"></span>
      <div class="tl-body">
        <div class="tl-head"><span class="tl-act">${meta.label}</span>
          <span class="tl-time">${dateTimeLocal(e.created_at)}</span></div>
        ${sub ? `<div class="tl-sub">${sub}</div>` : ""}
      </div></li>`;
  }).join("");

  // Jump to the live entity when it still exists.
  const openable = (entity === "task" && state.tasks.some((t) => t.id === entityId))
    ? "task-detail"
    : (entity === "job" && state.jobs.some((j) => j.id === entityId)) ? "job-detail" : "";

  card.innerHTML = `<div class="sheet-grip"></div>
    <div class="sheet-title">Історія · ${label}</div>
    ${title || child ? `<div class="sheet-sub">${escapeHtml(title || "")}` +
      (child ? ` — ${escapeHtml(child.display_name)}` : "") + `</div>` : ""}
    ${steps.length
      ? `<ol class="tl">${rows}</ol>`
      : `<div class="empty-sm">Подій ще немає</div>`}
    <div class="actions">
      <button class="btn ghost" data-action="close">Закрити</button>
      ${openable
        ? `<button class="btn" data-action="${openable}" data-id="${entityId}">Відкрити</button>`
        : ""}
    </div>`;
  attachSheetDrag(card);
}

function bonusEditForm(id) {
  const b = state.bonuses.find((x) => x.id === id);
  if (!b) return;
  const c = childById(b.child_id);
  openSheet(`
    <div class="sheet-title">Редагувати бонус${c ? ` — ${escapeHtml(c.display_name)}` : ""}</div>
    <label class="fl">Скільки жолудів (від'ємне — штраф)
      <input id="be-amt" class="inp" type="number" step="1" inputmode="numeric" value="${b.amount}"></label>
    ${fieldErr("beamt")}
    <label class="fl">Причина<input id="be-note" class="inp" value="${escAttr(b.note)}"></label>
    <div class="actions"><button class="btn ghost" data-action="close">Скасувати</button>
      <button class="btn" data-main="1" data-action="bonus-edit-save" data-id="${id}">Зберегти</button></div>`);
}
async function saveBonusEdit(id) {
  clearErrs();
  const amt = Math.trunc(Number($("#be-amt").value || 0));
  if (!amt) return setErr("beamt", "Вкажіть суму");
  await submitSheet(() => api.updateBonus(id, amt, $("#be-note").value), "Збережено");
}

function journalWithdrawal(w) {
  const child = w.profiles || childById(w.child_id) || {};
  const s = WITHDRAWAL_STATUS[w.status] || { label: w.status, cls: "" };
  const methodChip = w.method ? " " + chip(w.method === "card" ? "на карту" : "готівка", "") : "";
  const act = w.status === "requested"
    ? `<div class="actions row"><button class="btn ok sm" data-action="wd-approve" data-id="${w.id}">Схвалити</button>
       <button class="btn danger sm" data-action="wd-decline" data-id="${w.id}">Відхилити</button></div>`
    : (w.status === "approved"
      ? `<div class="actions row"><button class="btn sm" data-action="wd-pay" data-id="${w.id}">Виплатити…</button></div>`
      : "");
  return `<div class="card col">
    <div class="card-row">${avatar(child, 30)}<div class="card-b">
      <div class="card-t sm">Вивід ${acornsHtml(w.amount)}</div>
      <div class="card-s">${escapeHtml(child.display_name || "")} · ${dateTimeLocal(w.requested_at)}</div>
      <div class="chips">${chip(s.label, s.cls)}${methodChip}</div></div></div>${act}</div>`;
}

// ------------------------------------------------------------------ small UI

function field(label, value) {
  return `<div class="field"><div class="field-l">${label}</div><div class="field-v">${value}</div></div>`;
}
function emptyState(text) {
  return `<div class="empty"><img class="empty-logo" src="./assets/logo.png" alt=""><p>${text}</p></div>`;
}

// modal sheet
function openSheet(html) {
  const s = $("#sheet");
  s.innerHTML = `<div class="sheet-card"><div class="sheet-grip"></div>${html}</div>`;
  s.classList.remove("hidden");
  requestAnimationFrame(() => s.classList.add("show"));
  attachSheetDrag(s.querySelector(".sheet-card"));
  tg?.BackButton?.show?.();
  syncMainButton();
}

// Drag-to-close: pulling the sheet down (from the grip, or from anywhere once
// its content is scrolled to the top) moves the sheet itself and closes it
// past the threshold. Upward pulls hand over to native content scrolling.
function attachSheetDrag(card) {
  if (!card) return;
  let startY = 0, delta = 0, armed = false, committed = false;

  card.addEventListener("touchstart", (e) => {
    const fromGrip = !!e.target.closest(".sheet-grip");
    armed = fromGrip || card.scrollTop <= 0;
    committed = false;
    delta = 0;
    startY = e.touches[0].clientY;
  }, { passive: true });

  card.addEventListener("touchmove", (e) => {
    if (!armed) return;
    const dy = e.touches[0].clientY - startY;
    if (!committed) {
      if (dy < 0) { armed = false; return; }   // pulling up -> native scroll
      if (dy < 8) return;                       // ignore jitter
      committed = true;
      card.style.transition = "none";
    }
    delta = Math.max(0, dy);
    e.preventDefault();                         // own the gesture entirely
    card.style.transform = `translateY(${delta}px)`;
  }, { passive: false });

  const finish = () => {
    if (!committed) { armed = false; return; }
    committed = false; armed = false;
    card.style.transition = "";
    if (delta > Math.min(140, card.offsetHeight * 0.3)) {
      card.style.transition = "transform 0.2s ease-in";
      card.style.transform = "translateY(100%)";
      closeSheet();
    } else {
      card.style.transform = "";                // spring back
    }
  };
  card.addEventListener("touchend", finish);
  card.addEventListener("touchcancel", finish);
}
function closeSheet() {
  const s = $("#sheet");
  s.classList.remove("show");
  setTimeout(() => { s.classList.add("hidden"); s.innerHTML = ""; }, 200);
  tg?.BackButton?.hide?.();
  tg?.MainButton?.hide?.();
}

// Every sheet renders its own branded, padded button row (see .actions): the
// native MainButton is edge-to-edge in Telegram's theme colour and detaches
// below the WebView, which clashes with the fully custom design — so we keep it
// hidden and never mirror to it. The in-sheet primary button stays visible.
function syncMainButton() {
  tg?.MainButton?.hide?.();
}
function onMainButton() {
  const el = $("#sheet [data-main]");
  if (!el) return;
  const fn = HANDLERS[el.dataset.action];
  if (fn) { haptic("impact"); fn(el); }
}

// Keep the focused field visible above the keyboard.
document.addEventListener("focusin", (ev) => {
  if (ev.target.closest?.(".sheet-card")) {
    setTimeout(() => ev.target.scrollIntoView({ block: "center", behavior: "smooth" }), 250);
  }
});

function toast(msg) {
  const t = document.createElement("div");
  t.className = "toast"; t.textContent = msg;
  document.body.appendChild(t);
  requestAnimationFrame(() => t.classList.add("show"));
  setTimeout(() => { t.classList.remove("show"); setTimeout(() => t.remove(), 250); }, 2200);
}

async function confirmDlg(message) {
  return new Promise((resolve) => {
    if (tg?.showConfirm) tg.showConfirm(message, (ok) => resolve(ok));
    else resolve(window.confirm(message));
  });
}

async function guard(fn, okMsg) {
  try { await fn(); if (okMsg) toast(okMsg); haptic("success"); }
  catch (e) { haptic("error"); toast("Помилка: " + (e.message || e)); }
}

// ------------------------------------------------------------------ ticker

// One 1-second tick refreshes every live number in the current DOM by id /
// attribute — no re-render, no recursion. Skips entirely while nothing accrues.
function startTicker() {
  setInterval(() => {
    if (!state.jobs.some((j) => j.status === "running")) return;

    // Running jobs: shared timer + per-member earned (jobs tab, if visible).
    for (const job of state.jobs) {
      if (job.status !== "running") continue;
      const members = state.jobStats.filter((s) => s.job_id === job.id);
      if (!members.length) continue;
      const tmr = document.getElementById(`tmr-${job.id}`);
      if (tmr) tmr.textContent = duration(liveStat(members[0]).totalSeconds);
      for (const s of members) {
        const live = liveStat(s);
        const b = document.getElementById(`bal-${job.id}-${s.child_id}`);
        const e = document.getElementById(`ern-${job.id}-${s.child_id}`);
        if (b) b.innerHTML = acornsHtml(live.earned);
        if (e) e.textContent = duration(live.earnedSeconds);
      }
    }

    // Personal balances wherever they are shown (cards, lists, open popups).
    document.querySelectorAll("[data-live-bal]").forEach((el) => {
      el.innerHTML = acornsHtml(childBalance(el.getAttribute("data-live-bal")));
    });
  }, 1000);
}

// ------------------------------------------------------------------ forms

function multiChildPicker(id, checkedIds = []) {
  return state.children.map((c) =>
    `<label class="pick"><input type="checkbox" name="${id}" value="${c.id}"` +
    `${checkedIds.includes(c.id) ? " checked" : ""}>` +
    `${avatar(c, 26)}<span>${escapeHtml(c.display_name)}</span></label>`).join("");
}
function pickedChildren(name) {
  return [...document.querySelectorAll(`input[name="${name}"]:checked`)].map((i) => i.value);
}

const escAttr = (s) => escapeHtml(String(s ?? "")).replace(/"/g, "&quot;");
const formSec = (t) => `<div class="form-sec">${t}</div>`;
const fieldErr = (id) => `<div class="field-err" id="err-${id}"></div>`;

function setErr(id, msg) {
  const el = $(`#err-${id}`);
  if (!el) return;
  el.textContent = msg;
  if (msg) el.scrollIntoView({ block: "center", behavior: "smooth" });
}
function clearErrs() {
  [...document.querySelectorAll(".field-err")].forEach((e) => { e.textContent = ""; });
}

// ---- unified create/edit task form -----------------------------------------

// Live state of the open task form.
let taskDeadline = null;       // Date | null
let taskUploader = null;       // PhotoUploader
let taskFormMode = "simple";   // completion mode segment mirror

const PROOF_OPTS = [
  { value: "none", label: "Не треба" },
  { value: "optional", label: "За бажанням" },
  { value: "required", label: "Обов'язково" },
];

function deadlineFieldValue() {
  if (!taskDeadline) return "";
  const d = deadline(taskDeadline.toISOString());
  return d.state === "none" ? dateTimeLocal(taskDeadline.toISOString()) : d.text;
}

function refreshDeadlineField() {
  const el = $('[data-action="dl-open"] .pf-v');
  if (!el) return;
  const has = !!taskDeadline;
  el.textContent = has ? deadlineFieldValue() : "Без дедлайну";
  el.classList.toggle("pf-empty", !has);
}

async function taskForm(t = null) {
  const edit = !!t;
  taskDeadline = t?.deadline_at ? new Date(t.deadline_at) : null;
  taskFormMode = t?.completion_mode ?? "simple";

  taskUploader = new ui.PhotoUploader({ optimize: optimizeImage, onChange: syncMainButton });
  if (edit) {
    const atts = taskAttachments(t.id, "task");
    taskUploader.existing = await Promise.all(atts.map(async (a) => ({
      id: a.id, att: a, url: await api.attachmentUrl(a, true),
    })));
  }

  openSheet(`
    <div class="sheet-title">${edit ? "Редагувати завдання" : "Нове завдання"}</div>
    <input type="hidden" id="t-edit" value="${t?.id || ""}">

    ${formSec("Основне")}
    <label class="fl">Назва
      <input id="t-title" class="inp" maxlength="200" value="${escAttr(t?.title)}"></label>
    ${fieldErr("title")}
    <label class="fl">Опис
      <textarea id="t-desc" class="inp" rows="2">${escapeHtml(t?.description || "")}</textarea></label>
    ${edit ? "" : `<div class="fl">Виконавці<div class="picks">${multiChildPicker("t-child")}</div></div>${fieldErr("child")}`}

    ${formSec("Виконання")}
    <div class="fl">Тип завдання</div>
    ${ui.segmented("t-mode", [
      { value: "simple", label: "Без таймера" },
      { value: "timer", label: "З таймером" },
    ], taskFormMode)}
    <div class="fl">Нагорода</div>
    <div id="t-rtype-wrap">${rewardSegment(t?.reward_type ?? "fixed")}</div>
    <label class="fl">Скільки жолудів
      <input id="t-amount" class="inp" type="number" min="0" step="1"
             inputmode="numeric" value="${t?.reward_amount ?? ""}" placeholder="0"></label>
    ${fieldErr("amount")}
    <div class="fl">Складність</div>
    ${ui.difficultyPicker(t?.difficulty ?? 2)}

    ${formSec("Підтвердження")}
    <label class="fl">Вимоги<input id="t-req" class="inp" value="${escAttr(t?.requirements)}"></label>
    <div class="fl">Звіт текстом</div>
    ${ui.segmented("t-ptext", PROOF_OPTS, t?.proof_text ?? "none")}
    <div class="fl">Звіт фото</div>
    ${ui.segmented("t-pphoto", PROOF_OPTS, t?.proof_photo ?? "none")}

    ${formSec("Дедлайн")}
    ${ui.pickField({ action: "dl-open", value: taskDeadline ? deadlineFieldValue() : "", placeholder: "Без дедлайну" })}
    ${fieldErr("deadline")}

    ${formSec("Фото")}
    ${taskUploader.render()}

    <div class="actions"><button class="btn ghost" data-action="close">Скасувати</button>
      <button class="btn" data-main="1" data-action="task-save">${edit ? "Зберегти" : "Створити"}</button></div>`);

  const card = $("#sheet .sheet-card");
  taskUploader.wire(card);
  ui.wireDifficulty(card);
  ui.wireSegments(card, (name, value) => {
    if (name === "t-mode") {
      taskFormMode = value;
      // Hourly pay needs a timer (DB constraint) — rebuild the reward segment.
      const cur = value === "simple" ? "fixed" : ui.segValue(card, "t-rtype") || "fixed";
      $("#t-rtype-wrap").innerHTML = rewardSegment(cur);
    }
  });
}

function rewardSegment(current) {
  const opts = taskFormMode === "simple"
    ? [{ value: "fixed", label: "Фіксована" }]
    : [{ value: "fixed", label: "Фіксована" }, { value: "hourly", label: "Погодинна" }];
  return ui.segmented("t-rtype", opts, current === "hourly" && taskFormMode === "simple" ? "fixed" : current);
}

let savingSheet = false; // double-submit guard for every sheet form

async function submitSheet(fn, okMsg) {
  if (savingSheet) return;
  savingSheet = true;
  const btn = $("#sheet [data-main]");
  if (btn) { btn.disabled = true; btn.classList.add("loading"); }
  try {
    await fn();
    toast(okMsg);
    haptic("success");
    closeSheet();
  } catch (e) {
    haptic("error");
    toast("Помилка: " + (e.message || e));
    if (btn) { btn.disabled = false; btn.classList.remove("loading"); }
  } finally {
    savingSheet = false;
  }
}

async function saveTask() {
  clearErrs();
  const card = $("#sheet .sheet-card");
  const editId = $("#t-edit").value;
  const title = $("#t-title").value.trim();
  const amount = Math.trunc(Number($("#t-amount").value || 0));
  const childIds = editId ? [] : pickedChildren("t-child");
  let bad = false;
  if (!title) { setErr("title", "Вкажіть назву"); bad = true; }
  if (!editId && !childIds.length) { setErr("child", "Оберіть хоча б одного виконавця"); bad = true; }
  if (!(amount >= 0)) { setErr("amount", "Сума не може бути від'ємною"); bad = true; }
  if (!editId && taskDeadline && taskDeadline.getTime() <= Date.now()) {
    setErr("deadline", "Дедлайн не може бути в минулому");
    bad = true;
  }
  if (bad) return;

  const fields = {
    title,
    description: $("#t-desc").value.trim(),
    completion_mode: ui.segValue(card, "t-mode") || "simple",
    reward_type: ui.segValue(card, "t-rtype") || "fixed",
    reward_amount: amount,
    difficulty: ui.difficultyValue(card),
    requirements: $("#t-req").value.trim(),
    proof_text: ui.segValue(card, "t-ptext") || "none",
    proof_photo: ui.segValue(card, "t-pphoto") || "none",
    deadline_at: taskDeadline ? taskDeadline.toISOString() : null,
  };
  const uploader = taskUploader;
  const photos = uploader.pending().map((a) => ({
    key: a.key, full: { blob: a.blob, mime: a.mime, ext: a.mime === "image/webp" ? "webp" : "jpg" },
    thumb: a.thumbBlob ? { blob: a.thumbBlob, mime: a.thumbBlob.type, ext: a.thumbBlob.type === "image/webp" ? "webp" : "jpg" } : null,
  }));
  const onPhoto = (key, pct) => uploader.setProgress(key, pct);

  if (editId) {
    const task = state.tasks.find((x) => x.id === editId);
    await submitSheet(async () => {
      await api.updateTask(editId, fields);
      for (const att of uploader.removedExisting) await api.deleteAttachment(att);
      if (photos.length && task) await api.addTaskPhotos(task, photos, onPhoto);
    }, "Збережено");
  } else {
    await submitSheet(() => api.createTask(fields, childIds, photos, onPhoto), "Завдання створено");
  }
}

function jobForm(job = null) {
  const edit = !!job;
  const memberIds = edit
    ? state.jobStats.filter((s) => s.job_id === job.id).map((s) => s.child_id)
    : [];
  openSheet(`
    <div class="sheet-title">${edit ? "Редагувати роботу" : "Нова робота"}</div>
    <input type="hidden" id="j-edit" value="${job?.id || ""}">
    <label class="fl">Назва
      <input id="j-title" class="inp" maxlength="200" value="${escAttr(job?.title)}"></label>
    ${fieldErr("jtitle")}
    <label class="fl">Опис
      <textarea id="j-desc" class="inp" rows="2">${escapeHtml(job?.description || "")}</textarea></label>
    <label class="fl">Жолудів за годину
      <input id="j-rate" class="inp" type="number" min="0" step="1" inputmode="numeric"
             value="${job?.hourly_rate ?? 0}"></label>
    <div class="hint">Заробіток автоматично йде на баланс виконавця.</div>
    <div class="fl">Виконавці<div class="picks">${multiChildPicker("j-child", memberIds)}</div></div>
    <div class="actions"><button class="btn ghost" data-action="close">Скасувати</button>
      <button class="btn" data-main="1" data-action="job-save">${edit ? "Зберегти" : "Створити"}</button></div>`);
}
async function saveJob() {
  clearErrs();
  const editId = $("#j-edit").value;
  const title = $("#j-title").value.trim();
  if (!title) return setErr("jtitle", "Вкажіть назву");
  const fields = {
    title, description: $("#j-desc").value.trim(),
    hourly_rate: Math.trunc(Number($("#j-rate").value || 0)),
  };
  const picks = pickedChildren("j-child");
  if (editId) {
    await submitSheet(() => api.updateJob(editId, fields, picks), "Збережено");
  } else {
    await submitSheet(() => api.createJob(fields, picks), "Роботу створено");
  }
}


function adjustForm(childId) {
  const c = childById(childId);
  openSheet(`
    <div class="sheet-title">Коригувати баланс${c ? ` — ${escapeHtml(c.display_name)}` : ""}</div>
    <label class="fl">Скільки жолудів (від'ємне — штраф)
      <input id="adj-amt" class="inp" type="number" step="1" inputmode="numeric" placeholder="0"></label>
    ${fieldErr("adjamt")}
    <label class="fl">Коментар (обов'язково)<input id="adj-note" class="inp" placeholder="напр. за гарну поведінку / виправлення"></label>
    ${fieldErr("adjnote")}
    <div class="actions"><button class="btn ghost" data-action="close">Скасувати</button>
      <button class="btn" data-main="1" data-action="adjust-save" data-id="${childId}">Застосувати</button></div>`);
}
async function saveAdjust(childId) {
  clearErrs();
  const amt = Math.trunc(Number($("#adj-amt").value || 0));
  const note = ($("#adj-note").value || "").trim();
  if (!amt) return setErr("adjamt", "Вкажіть суму");
  if (!note) return setErr("adjnote", "Додайте коментар");
  await submitSheet(() => api.adjustBalance(childId, amt, note), "Баланс змінено");
}

function wdRejectForm(id) {
  openSheet(`
    <div class="sheet-title">Відхилити вивід</div>
    <label class="fl">Причина (виконавець побачить)<textarea id="wr-note" class="inp" rows="3"></textarea></label>
    <div class="actions"><button class="btn ghost" data-action="close">Скасувати</button>
      <button class="btn danger" data-main="1" data-action="wd-reject-save" data-id="${id}">Відхилити</button></div>`);
}

let payMethod = "card";
let receiptUploader = null;     // PhotoUploader for the card receipt

/** The receipt block is only meaningful for card payouts. */
function toggleReceiptBlock(method) {
  const box = $("#wd-receipt-box") || $("#po-receipt-box");
  if (box) box.classList.toggle("hidden", method !== "card");
}

/**
 * Upload the picked receipt (if any) and attach it to the withdrawal.
 * childId is passed explicitly because a just-created payout is not in state yet.
 */
async function attachPickedReceipt(withdrawalId, childId) {
  const pending = receiptUploader ? receiptUploader.pending() : [];
  if (pending.length === 0) return;
  const a = pending[0];
  const photo = {
    full: { blob: a.blob, mime: a.mime, ext: a.mime === "image/webp" ? "webp" : "jpg" },
    thumb: a.thumbBlob
      ? { blob: a.thumbBlob, mime: a.thumbBlob.type, ext: a.thumbBlob.type === "image/webp" ? "webp" : "jpg" }
      : null,
  };
  const info = await api.uploadTaskPhoto(childId, photo,
    (p) => receiptUploader.setProgress(a.key, p));
  await api.attachReceipt(withdrawalId, info);
}

function receiptBlock(boxId) {
  const required = state.config?.require_receipt_for_card;
  return `<div id="${boxId}" class="rcpt-box">
      ${formSec(required ? "Квитанція (обов'язково)" : "Квитанція (необов'язково)")}
      ${receiptUploader.render()}</div>`;
}

function wdPayForm(id) {
  const w = state.withdrawals.find((x) => x.id === id);
  if (!w) return;
  const c = childById(w.child_id);
  payMethod = "card";
  receiptUploader = new ui.PhotoUploader({ optimize: optimizeImage, max: 1, onChange: syncMainButton });
  openSheet(`
    <div class="sheet-title">Виплата ${acornWords(w.amount)}${c ? ` — ${escapeHtml(c.display_name)}` : ""}</div>
    <div class="segment">
      <button class="seg on" data-action="wd-method" data-val="card">На карту</button>
      <button class="seg" data-action="wd-method" data-val="cash">Готівка</button></div>
    <div id="wd-cash-hint" class="hint hidden">Виконавцю прийде запит підтвердити отримання готівки.</div>
    ${receiptBlock("wd-receipt-box")}
    ${fieldErr("wdrcpt")}
    <label class="fl">Коментар (необов'язково)<input id="wd-comment" class="inp" placeholder="напр. решта 3 жолуді за мною"></label>
    <div class="actions"><button class="btn ghost" data-action="close">Скасувати</button>
      <button class="btn" data-main="1" data-action="wd-pay-do" data-id="${id}">Підтвердити виплату</button></div>`);
  receiptUploader.wire($("#sheet .sheet-card"));
}
async function payWithdrawal(id) {
  clearErrs();
  const needReceipt = payMethod === "card" && state.config?.require_receipt_for_card;
  if (needReceipt && receiptUploader.pending().length === 0) {
    return setErr("wdrcpt", "Додайте квитанцію");
  }
  const childId = state.withdrawals.find((x) => x.id === id)?.child_id || "";
  await submitSheet(async () => {
    // Attach first: the RPC refuses a card payout without a required receipt.
    if (payMethod === "card") await attachPickedReceipt(id, childId);
    await api.withdrawalPay(id, payMethod, $("#wd-comment")?.value || "");
  }, payMethod === "cash" ? "Позначено як видане готівкою" : "Виплачено на карту");
}

// Owner-initiated payout to an assignee.
let payoutMethod = "card";
function payoutForm(childId) {
  const c = childById(childId);
  const bal = childBalance(childId);
  payoutMethod = "card";
  receiptUploader = new ui.PhotoUploader({ optimize: optimizeImage, max: 1, onChange: syncMainButton });
  openSheet(`
    <div class="sheet-title">Виплата${c ? ` — ${escapeHtml(c.display_name)}` : ""}</div>
    <div class="sheet-sub">Баланс: <b data-live-bal="${childId}">${acornsHtml(bal)}</b></div>
    <label class="fl">Скільки жолудів</label>
    <div class="amt-field">
      <input id="po-amt" type="number" step="1" inputmode="numeric" placeholder="0">
      <button class="amt-all" data-action="po-all" data-id="${childId}">Усе</button>
    </div>
    ${fieldErr("poamt")}
    <label class="fl">Спосіб виплати</label>
    <div class="segment">
      <button class="seg on" data-action="payout-method" data-val="card">На карту</button>
      <button class="seg" data-action="payout-method" data-val="cash">Готівка</button></div>
    <div id="po-cash-hint" class="hint hidden">Виконавцю прийде запит підтвердити отримання готівки.</div>
    ${receiptBlock("po-receipt-box")}
    ${fieldErr("porcpt")}
    <label class="fl">Коментар (необов'язково)<input id="po-comment" class="inp" placeholder="напр. решта 3 жолуді за мною"></label>
    <div class="actions"><button class="btn ghost" data-action="close">Скасувати</button>
      <button class="btn" data-main="1" data-action="payout-do" data-id="${childId}">Виплатити</button></div>`);
  receiptUploader.wire($("#sheet .sheet-card"));
}
async function savePayout(childId) {
  clearErrs();
  const bal = childBalance(childId);
  const amt = Math.trunc(Number($("#po-amt").value || 0));
  if (amt <= 0) return setErr("poamt", "Вкажіть суму");
  if (amt > bal + 0.001) return setErr("poamt", "Більше за доступний баланс");
  if (payoutMethod === "card" && state.config?.require_receipt_for_card
      && receiptUploader.pending().length === 0) {
    return setErr("porcpt", "Додайте квитанцію");
  }
  await submitSheet(async () => {
    const passAmt = Math.abs(amt - bal) < 0.01 ? null : amt;   // exact all → server uses live balance
    const id = await api.createWithdrawal(childId, passAmt);
    // Attach before paying: the RPC refuses a card payout without a required receipt.
    if (payoutMethod === "card") await attachPickedReceipt(id, childId);
    await api.withdrawalPay(id, payoutMethod, ($("#po-comment") || {}).value || "");
  }, payoutMethod === "cash" ? "Позначено готівкою" : "Виплачено на карту");
}

function passwordForm(childId) {
  const c = childById(childId);
  openSheet(`
    <div class="sheet-title">Пароль для ${escapeHtml(c?.display_name || "")}</div>
    <label class="fl">Новий пароль<input id="p-pass" class="inp" type="text"></label>
    <div class="actions"><button class="btn ghost" data-action="close">Скасувати</button>
      <button class="btn" data-main="1" data-action="password-save" data-id="${childId}">Зберегти</button></div>`);
}
async function savePassword(childId) {
  const p = $("#p-pass").value;
  if (p.length < 3) return toast("Пароль закороткий");
  await guard(async () => { await api.setChildPassword(childId, p); closeSheet(); }, "Пароль змінено");
}

function reworkForm(taskId) {
  openSheet(`
    <div class="sheet-title">Відправити на доробку</div>
    <label class="fl">Що виправити (необов'язково)<textarea id="rw-note" class="inp" rows="3"></textarea></label>
    <div class="actions"><button class="btn ghost" data-action="close">Скасувати</button>
      <button class="btn warn" data-main="1" data-action="rework-save" data-id="${taskId}">На доробку</button></div>`);
}
function rejectForm(taskId) {
  openSheet(`
    <div class="sheet-title">Відхилити завдання</div>
    <label class="fl">Причина (необов'язково)<textarea id="rj-note" class="inp" rows="3"></textarea></label>
    <div class="actions"><button class="btn ghost" data-action="close">Скасувати</button>
      <button class="btn danger" data-main="1" data-action="reject-save" data-id="${taskId}">Відхилити</button></div>`);
}

// ------------------------------------------------------------------ actions

const HANDLERS = {
  tab: (el) => { state.tab = el.dataset.id; render(); },
  close: () => closeSheet(),
  retry: () => location.reload(),
  "reload-data": () => { state.loaded = false; render(); loadData(); },
  "task-filter": (el) => { state.taskFilter = el.dataset.id; render(); },
  "journal-filter": (el) => { state.journalFilter = el.dataset.id; render(); },
  timeline: (el) => timelineSheet(el.dataset.entity, el.dataset.id),
  "task-detail": (el) => openTaskDetail(el.dataset.id),
  "task-create": () => taskForm(),
  "task-edit": (el) => taskForm(state.tasks.find((t) => t.id === el.dataset.id)),
  "task-save": () => saveTask(),
  "task-approve": (el) => guard(async () => { await api.reviewTask(el.dataset.id, "approve"); closeSheet(); }, "Прийнято"),
  "task-rework": (el) => reworkForm(el.dataset.id),
  "rework-save": (el) => guard(async () => { await api.reviewTask(el.dataset.id, "rework", $("#rw-note").value); closeSheet(); }, "На доробку"),
  "task-reject": (el) => rejectForm(el.dataset.id),
  "reject-save": (el) => guard(async () => { await api.reviewTask(el.dataset.id, "reject", $("#rj-note").value); closeSheet(); }, "Відхилено"),
  "task-duplicate": (el) => guard(async () => { await api.duplicateTask(el.dataset.id); closeSheet(); }, "Продубльовано"),
  "task-delete": async (el) => {
    if (await confirmDlg("Видалити завдання?"))
      guard(async () => { await api.deleteTask(el.dataset.id); closeSheet(); }, "Видалено");
  },
  "gal-open": (el) => openGallery(el.dataset.g, Number(el.dataset.i)),
  "dl-open": () => ui.deadlineSheet({
    value: taskDeadline,
    onDone: (d) => { taskDeadline = d; refreshDeadlineField(); },
  }),
  "author-pick": () => ui.optionSheet({
    title: "Автор завдань",
    options: [{ value: "", label: "Усі автори" }].concat(
      state.parents.map((p) => ({ value: p.id, label: p.display_name || p.email || "—" }))),
    current: state.taskAuthor,
    onPick: (v) => { state.taskAuthor = v; render(); },
  }),
  "j-child-pick": () => ui.optionSheet({
    title: "Виконавець",
    options: [{ value: "", label: "Усі виконавці" }].concat(
      state.children.map((c) => ({ value: c.id, label: c.display_name }))),
    current: state.journalChild,
    onPick: (v) => { state.journalChild = v; render(); },
  }),
  "j-period-pick": () => ui.optionSheet({
    title: "Період",
    options: JOURNAL_PERIODS.map((p) => ({ value: p.id, label: p.label })),
    current: state.journalPeriod,
    onPick: (v) => { state.journalPeriod = v; render(); },
  }),
  "ava-pick": () => $("#ava-file")?.click(),
  "ava-clear": () => {
    childAvatarBlob = null;
    if (childAvatarPreview) URL.revokeObjectURL(childAvatarPreview);
    childAvatarPreview = "";
    const prev = $("#ava-preview");
    const name = ($("#ce-name") || $("#c-name"))?.value || "?";
    if (prev) prev.textContent = initials(name);
  },
  "job-create": () => jobForm(),
  "job-detail": (el) => openJobDetail(el.dataset.id),
  "job-edit": (el) => jobForm(state.jobs.find((j) => j.id === el.dataset.id)),
  "job-save": () => saveJob(),
  // Job actions from the detail sheet (close it after acting).
  "jd-start": (el) => guard(async () => { await api.jobStart(el.dataset.id); closeSheet(); }, "Запущено"),
  "jd-stop": (el) => guard(async () => { await api.jobStop(el.dataset.id); closeSheet(); }, "Зупинено"),
  "jd-archive": async (el) => {
    if (await confirmDlg("Архівувати роботу? Вона зникне зі списків, історія виводів збережеться."))
      guard(async () => { await api.jobArchive(el.dataset.id); closeSheet(); }, "В архіві");
  },
  "jd-delete": async (el) => {
    if (await confirmDlg("Видалити роботу разом з усією історією? Це незворотно."))
      guard(async () => { await api.jobDelete(el.dataset.id); closeSheet(); }, "Видалено");
  },
  "job-start": (el) => guard(() => api.jobStart(el.dataset.id), "Запущено"),
  "job-stop": (el) => guard(() => api.jobStop(el.dataset.id), "Зупинено"),
  "job-archive": async (el) => {
    if (await confirmDlg("Архівувати роботу? Вона зникне зі списків, історія виводів збережеться."))
      guard(() => api.jobArchive(el.dataset.id), "В архіві");
  },
  "job-delete": async (el) => {
    if (await confirmDlg("Видалити роботу разом з усією історією? Це незворотно."))
      guard(() => api.jobDelete(el.dataset.id), "Видалено");
  },
  "wd-approve": (el) => guard(() => api.withdrawalApprove(el.dataset.id), "Схвалено"),
  "wd-decline": (el) => wdRejectForm(el.dataset.id),
  "wd-reject-save": (el) => submitSheet(() => api.withdrawalReject(el.dataset.id, $("#wr-note").value), "Відхилено"),
  "wd-pay": (el) => wdPayForm(el.dataset.id),
  "wd-method": (el) => {
    payMethod = el.dataset.val;
    document.querySelectorAll("[data-action='wd-method']").forEach((b) =>
      b.classList.toggle("on", b.dataset.val === payMethod));
    $("#wd-cash-hint")?.classList.toggle("hidden", payMethod !== "cash");
    toggleReceiptBlock(payMethod);
  },
  "wd-pay-do": (el) => payWithdrawal(el.dataset.id),
  "wd-filter": (el) => { state.wdStatus = el.dataset.id; render(); },
  "wd-child-pick": () => ui.optionSheet({
    title: "Виконавець",
    options: [{ value: "", label: "Усі виконавці" }].concat(
      state.children.map((c) => ({ value: c.id, label: c.display_name }))),
    current: state.wdChild,
    onPick: (v) => { state.wdChild = v; render(); },
  }),
  "wd-receipt": async (el) => {
    const w = state.withdrawals.find((x) => x.id === el.dataset.id);
    const rec = state.attachments.filter((a) => a.withdrawal_id === el.dataset.id && a.role === "receipt");
    if (!rec.length || !w) return;
    const urls = await Promise.all(rec.map((a) => api.attachmentUrl(a, false)));
    ui.lightbox(urls, Number(el.dataset.idx) || 0);
  },
  "child-detail": (el) => openChildDetail(el.dataset.id),
  "child-add": () => childCreateForm(),
  "child-save": () => saveChild(),
  "child-edit": (el) => childEditForm(el.dataset.id),
  "child-edit-save": (el) => saveChildEdit(el.dataset.id),
  "bonus-edit": (el) => bonusEditForm(el.dataset.id),
  "bonus-edit-save": (el) => saveBonusEdit(el.dataset.id),
  "bonus-delete": async (el) => {
    if (await confirmDlg("Видалити бонус? Сума зникне з балансу виконавця."))
      guard(() => api.deleteBonus(el.dataset.id), "Видалено");
  },
  "child-adjust": (el) => adjustForm(el.dataset.id),
  "adjust-save": (el) => saveAdjust(el.dataset.id),
  "bal-history": (el) => { state.ledgerChild = state.ledgerChild === el.dataset.id ? "" : el.dataset.id; render(); },
  "bal-history-clear": () => { state.ledgerChild = ""; render(); },
  "money-tab": (el) => { state.moneyTab = el.dataset.id; render(); },
  "child-payout": (el) => payoutForm(el.dataset.id),
  "payout-method": (el) => {
    payoutMethod = el.dataset.val;
    document.querySelectorAll("[data-action='payout-method']").forEach((b) =>
      b.classList.toggle("on", b.dataset.val === payoutMethod));
    $("#po-cash-hint")?.classList.toggle("hidden", payoutMethod !== "cash");
    toggleReceiptBlock(payoutMethod);
  },
  "payout-do": (el) => savePayout(el.dataset.id),
  "po-all": (el) => { const i = $("#po-amt"); if (i) i.value = String(childBalance(el.dataset.id)); },
  "child-password": (el) => passwordForm(el.dataset.id),
  "password-save": (el) => savePassword(el.dataset.id),
  "child-block": (el) => guard(async () => { await api.setChildBlocked(el.dataset.id, true); closeSheet(); }, "Заблоковано"),
  "child-unblock": (el) => guard(async () => { await api.setChildBlocked(el.dataset.id, false); closeSheet(); }, "Розблоковано"),
  "child-delete": async (el) => {
    if (await confirmDlg("Видалити виконавця разом з усіма даними?"))
      guard(async () => { await api.deleteChild(el.dataset.id); closeSheet(); }, "Видалено");
  },
};

document.addEventListener("click", (ev) => {
  // tap outside sheet card closes it
  if (ev.target.id === "sheet") return closeSheet();
  const el = ev.target.closest("[data-action]");
  if (!el) return;
  const fn = HANDLERS[el.dataset.action];
  if (fn) { haptic("impact"); fn(el); }
});

// The journal search updates only the feed so the input keeps focus.
document.addEventListener("input", (ev) => {
  if (ev.target.id === "j-search") {
    state.journalQuery = ev.target.value;
    const feed = $("#j-feed");
    if (feed) feed.innerHTML = journalFeedHtml();
  }
});

boot();
