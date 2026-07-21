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

// The acorn is indivisible: whole numbers only, everywhere. The mark itself is
// an image placed beside the number (acornsHtml) rather than a character glued
// into the string — an <img> cannot be aligned from inside a text node.
export function acorns(amount) {
  const n = Math.round(Number(amount ?? 0));
  const sign = n < 0 ? "-" : "";
  // Group thousands with a plain space (locale-independent, matches desktop).
  const grouped = String(Math.abs(n)).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return `${sign}${grouped}`;
}

// 1 жолудь / 2-4 жолуді / 5-20 жолудів, and the teens all take the last form.
const ACORN_FORMS = ["жолудь", "жолуді", "жолудів"];
export function acornUnit(count) {
  const n = Math.abs(Math.round(Number(count) || 0));
  if (Math.floor(n % 100 / 10) === 1) return ACORN_FORMS[2];
  const last = n % 10;
  if (last === 1) return ACORN_FORMS[0];
  if (last >= 2 && last <= 4) return ACORN_FORMS[1];
  return ACORN_FORMS[2];
}

/** "5 жолудів" — for sentences and labels, where an image cannot sit inline. */
export function acornWords(amount) {
  const n = Math.round(Number(amount ?? 0));
  return `${acorns(n)} ${acornUnit(n)}`;
}

/**
 * The number followed by the acorn mark, as HTML.
 *
 * `mono` tints the mark to the surrounding text colour, for dark fills where
 * the brown would disappear; everywhere else the coloured mark is the right
 * one — its two-tone cap is what keeps it readable as an acorn at label sizes.
 */
export function acornsHtml(amount, { signed = false, mono = false } = {}) {
  const n = Math.round(Number(amount ?? 0));
  const sign = signed && n >= 0 ? "+" : "";
  return `<span class="acn">${sign}${acorns(n)}` +
    `<img class="acn-m${mono ? " mono" : ""}" src="./assets/acorn.svg?v=220" alt="" aria-hidden="true"></span>`;
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
