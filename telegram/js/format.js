// Formatting + domain constants, mirroring the desktop (models.py) so both
// clients show identical money, durations, statuses and colours.

export const DIFFICULTY_COLORS = {
  1: "#6FA287", 2: "#8598B5", 3: "#D99A5B", 4: "#CE8158", 5: "#C96A5F",
};

export const TASK_STATUS = {
  new:         { label: "Нове",          cls: "st-new" },
  in_progress: { label: "Виконується",   cls: "st-run" },
  paused:      { label: "Призупинено",   cls: "st-pause" },
  submitted:   { label: "На перевірці",  cls: "st-review" },
  done:        { label: "Виконано",      cls: "st-done" },
  declined:    { label: "Відхилено",     cls: "st-declined" },
};

export const WITHDRAWAL_STATUS = {
  requested: { label: "Запитано",     cls: "st-review" },
  approved:  { label: "Схвалено",     cls: "st-done" },
  paid:      { label: "Виплачено · очікує підтвердження", cls: "pay-await" },
  confirmed: { label: "Підтверджено", cls: "st-done" },
  rejected:  { label: "Відхилено",    cls: "st-declined" },
};

export function money(amount) {
  const n = Number(amount ?? 0);
  const sign = n < 0 ? "-" : "";
  const cents = Math.round(Math.abs(n) * 100);
  const whole = Math.floor(cents / 100);
  const frac = cents % 100;
  // Group thousands with a plain space (locale-independent, matches desktop).
  const grouped = String(whole).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return `${sign}${grouped}.${String(frac).padStart(2, "0")} ₴`;
}

export function duration(totalSeconds) {
  let s = Math.max(0, Math.floor(totalSeconds || 0));
  const h = Math.floor(s / 3600); s -= h * 3600;
  const m = Math.floor(s / 60); s -= m * 60;
  return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

export function parseTs(value) {
  if (!value) return null;
  const d = new Date(value);
  return isNaN(d.getTime()) ? null : d;
}

export function dateTimeLocal(value) {
  const d = parseTs(value);
  if (!d) return "";
  const p = (num) => String(num).padStart(2, "0");
  return `${p(d.getDate())}.${p(d.getMonth() + 1)}.${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

// Human deadline text + state ('none'|'normal'|'soon'|'overdue').
// Same thresholds/wording as desktop fmt_deadline and Android formatDeadline.
export const DEADLINE_SOON_HOURS = 24;
export function deadline(value) {
  const d = parseTs(value);
  if (!d) return { text: "", state: "none" };
  const now = Date.now();
  const secs = (d.getTime() - now) / 1000;
  const p = (n) => String(n).padStart(2, "0");
  const hhmm = `${p(d.getHours())}:${p(d.getMinutes())}`;

  let state = "normal";
  if (secs < 0) state = "overdue";
  else if (secs <= DEADLINE_SOON_HOURS * 3600) state = "soon";

  const startOfDay = (t) => { const x = new Date(t); x.setHours(0, 0, 0, 0); return x; };
  const dayDiff = Math.round((startOfDay(d) - startOfDay(now)) / 86400000);

  let text;
  if (state === "overdue") text = `прострочено · ${dateTimeLocal(value)}`;
  else if (dayDiff === 0) text = `сьогодні до ${hhmm}`;
  else if (dayDiff === 1) text = `завтра ${hhmm}`;
  else if (dayDiff >= 2 && dayDiff <= 6) text = `через ${dayDiff} дн${dayDiff < 5 ? "і" : "ів"}`;
  else text = dateTimeLocal(value);
  return { text, state };
}

export function initials(name) {
  const t = (name || "?").trim();
  return t ? t[0].toUpperCase() : "?";
}

export function escapeHtml(s) {
  return String(s ?? "").replace(/[&<>"']/g, (c) => (
    { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]
  ));
}
