// Kabanchiki Mini App — custom UI controls.
//
// Nothing here looks native: selects become option sheets, date/time become a
// calendar + snap wheels, photos get a grid uploader with per-file progress.
// Stacked layers (option sheet over a form sheet, lightbox…) register a closer
// in `layers`, so the Telegram BackButton and overlay taps always close the
// top-most layer first.

const tg = window.Telegram?.WebApp;

export const svg = {
  x: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M5 5l14 14M19 5L5 19"/></svg>`,
  check: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="m4.5 12.5 5 5 10-11"/></svg>`,
  chevD: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>`,
  chevL: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg>`,
  chevR: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m9 5 7 7-7 7"/></svg>`,
  plus: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>`,
  camera: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8.5A2.5 2.5 0 0 1 6.5 6h1l1.4-2h6.2L16.5 6h1A2.5 2.5 0 0 1 20 8.5v8A2.5 2.5 0 0 1 17.5 19h-11A2.5 2.5 0 0 1 4 16.5z"/><circle cx="12" cy="12.5" r="3.2"/></svg>`,
  zoomOut: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5M8 11h6"/></svg>`,
  zoomIn: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5M8 11h6M11 8v6"/></svg>`,
  clock: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 7.5v5l3.2 2"/></svg>`,
};

export function haptic(type = "impact") {
  try {
    if (type === "impact") tg?.HapticFeedback?.impactOccurred("light");
    else if (type === "select") tg?.HapticFeedback?.selectionChanged();
    else tg?.HapticFeedback?.notificationOccurred(type);
  } catch { /* ignore */ }
}

export const escapeHtml = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => (
  { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

// ---------------------------------------------------------------- layers

const layers = []; // [{ close }]

export function pushLayer(close) { layers.push({ close }); }
export function removeLayer(close) {
  const i = layers.findIndex((l) => l.close === close);
  if (i >= 0) layers.splice(i, 1);
}
// Returns true if a stacked layer consumed the back action.
export function closeTopLayer() {
  const top = layers.pop();
  if (!top) return false;
  top.close(true);
  return true;
}
export const hasLayers = () => layers.length > 0;

// ---------------------------------------------------------------- option sheet

// A custom <select>: slides over everything, shows a check on the current row.
export function optionSheet({ title = "", options, current, onPick }) {
  const el = document.createElement("div");
  el.className = "pick-overlay";
  el.innerHTML = `<div class="pick-card">
    ${title ? `<div class="pick-title">${escapeHtml(title)}</div>` : ""}
    ${options.map((o) => `
      <button class="pick-opt ${String(o.value) === String(current) ? "on" : ""}" data-v="${escapeHtml(String(o.value))}">
        ${o.icon ?? ""}<span>${escapeHtml(o.label)}</span>
        <span class="po-check">${svg.check}</span>
      </button>`).join("")}
  </div>`;
  document.body.appendChild(el);
  requestAnimationFrame(() => el.classList.add("show"));

  const close = (fromStack = false) => {
    if (!fromStack) removeLayer(close);
    el.classList.remove("show");
    setTimeout(() => el.remove(), 220);
  };
  pushLayer(close);

  el.addEventListener("click", (ev) => {
    const opt = ev.target.closest(".pick-opt");
    if (opt) {
      haptic("select");
      close();
      onPick(opt.dataset.v);
      return;
    }
    if (ev.target === el) close();
  });
  return close;
}

// Markup for the trigger field (app code owns the click via data-action).
// NB: the placeholder class is pf-empty — a bare "empty" would collide with
// the page-level empty-state class (60px paddings on a tiny span).
export function pickField({ action, id = "", value, placeholder = "", compact = false, extra = "" }) {
  const has = value !== undefined && value !== null && String(value).length > 0;
  return `<button type="button" class="pickfield ${compact ? "compact" : ""}"
      data-action="${action}" ${id ? `data-id="${id}"` : ""} ${extra}>
    <span class="pf-v ${has ? "" : "pf-empty"}">${escapeHtml(has ? value : placeholder)}</span>
    <span class="pf-i">${svg.chevD}</span>
  </button>`;
}

// ---------------------------------------------------------------- segmented

// options: [{value, label}] — a radio group drawn as an iOS segment.
export function segmented(name, options, current) {
  return `<div class="fseg" data-fseg="${name}">${options.map((o) => `
    <button type="button" class="seg ${String(o.value) === String(current) ? "on" : ""}"
      data-v="${escapeHtml(String(o.value))}">${escapeHtml(o.label)}</button>`).join("")}
  </div>`;
}
export function segValue(root, name) {
  return root.querySelector(`[data-fseg="${name}"] .seg.on`)?.dataset.v ?? "";
}
// One delegated listener handles every segment on the page.
export function wireSegments(root, onChange) {
  root.addEventListener("click", (ev) => {
    const seg = ev.target.closest("[data-fseg] .seg");
    if (!seg) return;
    const group = seg.closest("[data-fseg]");
    if (seg.classList.contains("on")) return;
    haptic("select");
    [...group.querySelectorAll(".seg")].forEach((b) => b.classList.toggle("on", b === seg));
    onChange?.(group.dataset.fseg, seg.dataset.v);
  });
}

// ---------------------------------------------------------------- difficulty

export const DIFF_COLORS = ["#6FA287", "#8598B5", "#D99A5B", "#CE8158", "#C96A5F"];
export const DIFF_LABELS = ["Дуже легко", "Легко", "Середнє", "Складно", "Дуже складно"];

export function difficultyPicker(current = 2) {
  const cells = DIFF_COLORS.map((c, i) => {
    const bars = Array.from({ length: 5 }, (_, b) =>
      `<b style="height:${6 + b * 3}px; ${b <= i ? "" : "opacity:0.25"}"></b>`).join("");
    return `<button type="button" class="diffcell ${i + 1 === current ? "on" : ""}"
      style="--dc:${c}" data-v="${i + 1}"><span class="bars">${bars}</span></button>`;
  }).join("");
  return `<div class="diffpick" data-diff>${cells}</div>
    <div class="diffhint" data-diffhint style="color:${DIFF_COLORS[current - 1]}">${DIFF_LABELS[current - 1]}</div>`;
}
export function wireDifficulty(root) {
  root.addEventListener("click", (ev) => {
    const cell = ev.target.closest("[data-diff] .diffcell");
    if (!cell) return;
    haptic("select");
    const group = cell.closest("[data-diff]");
    [...group.querySelectorAll(".diffcell")].forEach((b) => b.classList.toggle("on", b === cell));
    const hint = group.parentElement.querySelector("[data-diffhint]");
    const v = Number(cell.dataset.v);
    if (hint) {
      hint.textContent = DIFF_LABELS[v - 1];
      hint.style.color = DIFF_COLORS[v - 1];
    }
  });
}
export function difficultyValue(root) {
  return Number(root.querySelector("[data-diff] .diffcell.on")?.dataset.v || 2);
}

// ---------------------------------------------------------------- deadline sheet

const MONTHS = ["січень", "лютий", "березень", "квітень", "травень", "червень",
  "липень", "серпень", "вересень", "жовтень", "листопад", "грудень"];
const DOW = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"];
const two = (n) => String(n).padStart(2, "0");

const WHEEL_ITEM = 44;   // must match .wheel .w-item height in styles.css

/**
 * Make a snap wheel advance by exactly one value per mouse-wheel notch.
 *
 * A native wheel notch scrolls ~100px — over two 44px items — so with
 * `scroll-snap-type: mandatory` the wheel lands two or three values away and
 * the wanted one is hard to hit. We take the gesture over: accumulate the delta
 * (trackpads emit many tiny ones), step a single item once it passes a
 * threshold, and hold a short lock so the smooth scroll is not re-triggered by
 * its own momentum. Touch scrolling is untouched.
 */
function bindWheelStep(el) {
  let acc = 0;
  let locked = false;
  el.addEventListener("wheel", (e) => {
    e.preventDefault();                       // we drive the scroll ourselves
    if (locked) return;
    // Normalise: line-mode deltas count as one item, page-mode as three.
    const unit = e.deltaMode === 1 ? WHEEL_ITEM : e.deltaMode === 2 ? WHEEL_ITEM * 3 : 1;
    acc += e.deltaY * unit;
    if (Math.abs(acc) < WHEEL_ITEM * 0.5) return;

    const dir = Math.sign(acc);
    acc = 0;
    const max = el.scrollHeight - el.clientHeight;
    const next = Math.min(max, Math.max(0,
      (Math.round(el.scrollTop / WHEEL_ITEM) + dir) * WHEEL_ITEM));
    if (next === el.scrollTop) return;
    locked = true;
    el.scrollTo({ top: next, behavior: "smooth" });
    setTimeout(() => { locked = false; }, 130);
  }, { passive: false });
}

// Custom date+time picker: month calendar, hour/minute snap wheels, presets.
// onDone(dateOrNull) — null means "no deadline".
export function deadlineSheet({ value = null, onDone }) {
  const now = new Date();
  const init = value ? new Date(value) : null;
  let selDate = init
    ? new Date(init.getFullYear(), init.getMonth(), init.getDate())
    : null;
  let viewYear = (init ?? now).getFullYear();
  let viewMonth = (init ?? now).getMonth();
  const initH = init ? init.getHours() : 18;
  const initM = init ? Math.round(init.getMinutes() / 5) * 5 % 60 : 0;

  const el = document.createElement("div");
  el.className = "pick-overlay";
  el.innerHTML = `<div class="pick-card" style="padding: 8px 16px calc(16px + var(--safe-bottom))">
    <div class="pick-title">Дедлайн</div>
    <div class="cal-head">
      <div class="cal-title" data-cal-title></div>
      <div class="cal-nav">
        <button type="button" data-cal="-1">${svg.chevL}</button>
        <button type="button" data-cal="1">${svg.chevR}</button>
      </div>
    </div>
    <div class="cal-grid" data-cal-grid></div>
    <div class="timewheels">
      <div class="wheel" data-wheel="h"><div class="w-pad"></div>${
        Array.from({ length: 24 }, (_, h) => `<div class="w-item">${two(h)}</div>`).join("")
      }<div class="w-pad"></div></div>
      <span class="wheel-colon">:</span>
      <div class="wheel" data-wheel="m"><div class="w-pad"></div>${
        Array.from({ length: 12 }, (_, i) => `<div class="w-item">${two(i * 5)}</div>`).join("")
      }<div class="w-pad"></div></div>
    </div>
    <div class="dl-presets">
      <button type="button" class="btn ghost sm" data-preset="today18">Сьогодні 18:00</button>
      <button type="button" class="btn ghost sm" data-preset="tomorrow">Завтра 18:00</button>
      <button type="button" class="btn ghost sm" data-preset="week">За тиждень</button>
    </div>
    <div class="actions">
      <button type="button" class="btn ghost danger" data-dl="clear">Без дедлайну</button>
      <button type="button" class="btn" data-dl="done">Готово</button>
    </div>
  </div>`;
  document.body.appendChild(el);
  requestAnimationFrame(() => el.classList.add("show"));

  const close = (fromStack = false) => {
    if (!fromStack) removeLayer(close);
    el.classList.remove("show");
    setTimeout(() => el.remove(), 220);
  };
  pushLayer(close);

  const grid = el.querySelector("[data-cal-grid]");
  const title = el.querySelector("[data-cal-title]");
  const todayFloor = new Date(now.getFullYear(), now.getMonth(), now.getDate());

  function renderCal() {
    title.textContent = `${MONTHS[viewMonth]} ${viewYear}`;
    const first = new Date(viewYear, viewMonth, 1);
    const startDow = (first.getDay() + 6) % 7; // Monday-first
    const days = new Date(viewYear, viewMonth + 1, 0).getDate();
    let html = DOW.map((d) => `<div class="cal-dow">${d}</div>`).join("");
    for (let i = 0; i < startDow; i++) html += `<div></div>`;
    for (let d = 1; d <= days; d++) {
      const date = new Date(viewYear, viewMonth, d);
      const cls = [
        date.getTime() === todayFloor.getTime() ? "today" : "",
        date < todayFloor ? "past" : "",
        selDate && date.getTime() === selDate.getTime() ? "sel" : "",
      ].join(" ");
      html += `<button type="button" class="cal-day ${cls}" data-day="${d}">${d}</button>`;
    }
    grid.innerHTML = html;
  }
  renderCal();

  const wheelH = el.querySelector('[data-wheel="h"]');
  const wheelM = el.querySelector('[data-wheel="m"]');
  // Direct assignment: the card is in the DOM, layout is available now.
  wheelH.scrollTop = initH * 44;
  wheelM.scrollTop = (initM / 5) * 44;
  const wheelVal = (w, step = 1) => Math.round(w.scrollTop / 44) * step;
  let lastTickH = -1, lastTickM = -1;
  wheelH.addEventListener("scroll", () => {
    const v = wheelVal(wheelH);
    if (v !== lastTickH) { lastTickH = v; haptic("select"); }
  }, { passive: true });
  wheelM.addEventListener("scroll", () => {
    const v = wheelVal(wheelM);
    if (v !== lastTickM) { lastTickM = v; haptic("select"); }
  }, { passive: true });
  bindWheelStep(wheelH);
  bindWheelStep(wheelM);

  function finish(date) {
    haptic("impact");
    close();
    onDone(date);
  }

  el.addEventListener("click", (ev) => {
    const nav = ev.target.closest("[data-cal]");
    if (nav) {
      viewMonth += Number(nav.dataset.cal);
      if (viewMonth < 0) { viewMonth = 11; viewYear--; }
      if (viewMonth > 11) { viewMonth = 0; viewYear++; }
      haptic("select");
      renderCal();
      return;
    }
    const day = ev.target.closest("[data-day]");
    if (day) {
      selDate = new Date(viewYear, viewMonth, Number(day.dataset.day));
      haptic("select");
      renderCal();
      return;
    }
    const preset = ev.target.closest("[data-preset]");
    if (preset) {
      const d = new Date();
      d.setHours(18, 0, 0, 0);
      if (preset.dataset.preset === "tomorrow") d.setDate(d.getDate() + 1);
      if (preset.dataset.preset === "week") d.setDate(d.getDate() + 7);
      finish(d);
      return;
    }
    const act = ev.target.closest("[data-dl]");
    if (act) {
      if (act.dataset.dl === "clear") return finish(null);
      const base = selDate ?? todayFloor;
      const d = new Date(base);
      d.setHours(Math.min(23, wheelVal(wheelH)), Math.min(55, wheelVal(wheelM, 5)), 0, 0);
      finish(d);
      return;
    }
    if (ev.target === el) close();
  });
}

// ---------------------------------------------------------------- lightbox

// Fullscreen swipeable gallery (scroll-snap) with a counter.
export function lightbox(urls, start = 0) {
  if (!urls.length) return;
  const el = document.createElement("div");
  el.id = "lightbox";
  el.className = "hidden";
  el.innerHTML = `
    <div class="lb-top">
      <span class="lb-count">${start + 1} / ${urls.length}</span>
      <button type="button" class="lb-close">${svg.x}</button>
    </div>
    <div class="lb-strip">${urls.map((u) =>
      `<div class="lb-item"><img src="${u}" alt="" loading="lazy"></div>`).join("")}
    </div>`;
  document.body.appendChild(el);
  el.classList.remove("hidden");
  requestAnimationFrame(() => el.classList.add("show"));

  const strip = el.querySelector(".lb-strip");
  const count = el.querySelector(".lb-count");
  requestAnimationFrame(() => { strip.scrollLeft = strip.clientWidth * start; });
  strip.addEventListener("scroll", () => {
    const i = Math.round(strip.scrollLeft / strip.clientWidth);
    count.textContent = `${Math.min(urls.length, i + 1)} / ${urls.length}`;
  }, { passive: true });

  const close = (fromStack = false) => {
    if (!fromStack) removeLayer(close);
    el.classList.remove("show");
    setTimeout(() => el.remove(), 220);
  };
  pushLayer(close);
  el.addEventListener("click", (ev) => {
    if (ev.target.closest(".lb-close") || ev.target.classList.contains("lb-item")) close();
  });
}

// ---------------------------------------------------------------- photo uploader

let phSeq = 0;

/**
 * Multi-photo picker with per-file progress. Holds:
 *  - existing: attachments already on the server (removable),
 *  - added: local optimized photos waiting for submit.
 * render() returns the grid markup; call wire(root) once after each render.
 */
export class PhotoUploader {
  constructor({ optimize, max = 10, maxSourceMb = 10, onChange, allowPdf = false }) {
    this.optimize = optimize;
    this.max = max;
    this.maxSourceMb = maxSourceMb;
    this.onChange = onChange;
    // Receipts are often bank PDFs; task photos stay pictures only.
    this.allowPdf = allowPdf;
    this.existing = []; // [{id, url, att}]
    this.added = [];    // [{key, blob, thumbBlob, mime, previewUrl, progress, error}]
    this.removedExisting = [];
    this.uid = `ph${++phSeq}`;
  }

  get count() { return this.existing.length + this.added.length; }

  render() {
    const cells = [
      ...this.existing.map((e) => `
        <div class="phcell" data-ph-ex="${e.id}">
          <img src="${e.url}" alt="">
          <button type="button" class="ph-x" data-ph-rm-ex="${e.id}">${svg.x}</button>
        </div>`),
      ...this.added.map((a) => `
        <div class="phcell ${a.error ? "err" : ""}" data-ph-add="${a.key}">
          ${a.isPdf
            ? `<div class="phdoc"><span>📄</span><b>PDF</b></div>`
            : `<img src="${a.previewUrl}" alt="">`}
          ${a.error
            ? `<div class="ph-err">${escapeHtml(a.error)}</div>`
            : a.progress != null
              ? `<div class="ph-prog"><div class="ph-bar"><b style="width:${a.progress}%"></b></div><span>${a.progress}%</span></div>`
              : ""}
          <button type="button" class="ph-x" data-ph-rm-add="${a.key}">${svg.x}</button>
        </div>`),
      this.count < this.max
        ? `<button type="button" class="phadd" data-ph-pick>${svg.camera}<span>Додати</span></button>`
        : "",
    ].join("");
    return `<div class="phgrid" data-ph="${this.uid}">${cells}</div>
      <div class="phhint">${this.allowPdf
          ? `Фото або PDF, ≤ ${this.maxSourceMb} МБ — фото стискаються автоматично`
          : `До ${this.max} фото, ≤ ${this.maxSourceMb} МБ кожне — стискаються автоматично`}</div>
      <input type="file" accept="${this.allowPdf ? "image/*,application/pdf" : "image/*"}"
             multiple hidden data-ph-input="${this.uid}">`;
  }

  wire(root) {
    this.root = root;
    const grid = root.querySelector(`[data-ph="${this.uid}"]`);
    const input = root.querySelector(`[data-ph-input="${this.uid}"]`);
    if (!grid || grid.dataset.wired) return;
    grid.dataset.wired = "1";

    grid.addEventListener("click", (ev) => {
      const rmEx = ev.target.closest("[data-ph-rm-ex]");
      if (rmEx) {
        haptic("impact");
        const id = rmEx.dataset.phRmEx;
        const e = this.existing.find((x) => x.id === id);
        if (e) this.removedExisting.push(e.att);
        this.existing = this.existing.filter((x) => x.id !== id);
        this.refresh();
        return;
      }
      const rmAdd = ev.target.closest("[data-ph-rm-add]");
      if (rmAdd) {
        haptic("impact");
        const a = this.added.find((x) => x.key === rmAdd.dataset.phRmAdd);
        if (a?.previewUrl) URL.revokeObjectURL(a.previewUrl);
        this.added = this.added.filter((x) => x !== a);
        this.refresh();
        return;
      }
      if (ev.target.closest("[data-ph-pick]")) {
        haptic("impact");
        input.click();
      }
    });

    // The hidden input survives refresh(); guard against double-wiring it.
    if (input.dataset.wired) return;
    input.dataset.wired = "1";
    input.addEventListener("change", async () => {
      const files = [...input.files];
      input.value = "";
      for (const f of files) {
        if (this.count >= this.max) break;
        const isPdf = f.type === "application/pdf";
        if (!/^image\//.test(f.type) && !(this.allowPdf && isPdf)) continue;
        const entry = { key: `k${++phSeq}`, previewUrl: URL.createObjectURL(f),
                        progress: null, isPdf };
        if (f.size > this.maxSourceMb * 1024 * 1024) {
          entry.error = `Занадто велике (>${this.maxSourceMb} МБ)`;
          this.added.push(entry);
          continue;
        }
        this.added.push(entry);
        this.refresh();
        if (isPdf) {
          // Upload the document exactly as picked: no re-encoding, no thumbnail.
          entry.blob = f;
          entry.mime = f.type;
          entry.thumbBlob = null;
          continue;
        }
        try {
          const opt = await this.optimize(f);
          entry.blob = opt.full.blob;
          entry.mime = opt.full.mime;
          entry.thumbBlob = opt.thumb.blob;
          URL.revokeObjectURL(entry.previewUrl);
          entry.previewUrl = URL.createObjectURL(opt.full.blob);
        } catch (e) {
          console.error("optimize failed", e);
          entry.error = "Не вдалося обробити";
        }
      }
      this.refresh();
      this.onChange?.();
    });
  }

  refresh() {
    const grid = this.root?.querySelector(`[data-ph="${this.uid}"]`);
    if (!grid) return;
    // Only the grid is rebuilt; the hidden input (and its listener) survives.
    const tmp = document.createElement("div");
    tmp.innerHTML = this.render();
    grid.replaceWith(tmp.querySelector(".phgrid"));
    this.wire(this.root);
    this.onChange?.();
  }

  setProgress(key, pct) {
    const a = this.added.find((x) => x.key === key);
    if (!a) return;
    a.progress = pct;
    const cell = this.root?.querySelector(`[data-ph-add="${key}"]`);
    if (!cell) return;
    let prog = cell.querySelector(".ph-prog");
    if (!prog) {
      cell.insertAdjacentHTML("beforeend",
        `<div class="ph-prog"><div class="ph-bar"><b></b></div><span></span></div>`);
      prog = cell.querySelector(".ph-prog");
    }
    prog.querySelector("b").style.width = `${pct}%`;
    prog.querySelector("span").textContent = `${pct}%`;
  }

  setError(key, msg) {
    const a = this.added.find((x) => x.key === key);
    if (a) { a.error = msg; a.progress = null; }
    this.refresh();
  }

  pending() { return this.added.filter((a) => a.blob && !a.error); }
}

// ---------------------------------------------------------------- avatar crop

// Pan + zoom circular crop, exports a 512px square blob.
export function cropSheet(file, onDone) {
  const el = document.createElement("div");
  el.className = "pick-overlay";
  el.innerHTML = `<div class="pick-card" style="padding: 8px 16px calc(16px + var(--safe-bottom))">
    <div class="pick-title">Кадрування фото</div>
    <div class="crop-wrap">
      <div class="crop-frame"><canvas width="520" height="520"></canvas></div>
      <div class="crop-zoom">${svg.zoomOut}
        <input type="range" min="100" max="300" value="100">
      ${svg.zoomIn}</div>
    </div>
    <div class="actions">
      <button type="button" class="btn ghost" data-crop="cancel">Скасувати</button>
      <button type="button" class="btn" data-crop="done">Готово</button>
    </div>
  </div>`;
  document.body.appendChild(el);
  requestAnimationFrame(() => el.classList.add("show"));

  const close = (fromStack = false) => {
    if (!fromStack) removeLayer(close);
    el.classList.remove("show");
    setTimeout(() => el.remove(), 220);
  };
  pushLayer(close);

  const canvas = el.querySelector("canvas");
  const ctx = canvas.getContext("2d");
  const range = el.querySelector('input[type="range"]');
  let bmp = null;
  let zoom = 1, offX = 0, offY = 0; // offsets in canvas px

  function draw() {
    if (!bmp) return;
    ctx.clearRect(0, 0, 520, 520);
    // cover-fit base scale, then user zoom
    const base = Math.max(520 / bmp.width, 520 / bmp.height) * zoom;
    const w = bmp.width * base, h = bmp.height * base;
    const maxX = Math.max(0, (w - 520) / 2), maxY = Math.max(0, (h - 520) / 2);
    offX = Math.max(-maxX, Math.min(maxX, offX));
    offY = Math.max(-maxY, Math.min(maxY, offY));
    ctx.drawImage(bmp, (520 - w) / 2 + offX, (520 - h) / 2 + offY, w, h);
  }

  (async () => {
    try {
      bmp = await createImageBitmap(file, { imageOrientation: "from-image" });
    } catch {
      try { bmp = await createImageBitmap(file); }
      catch { close(); return; }
    }
    draw();
  })();

  range.addEventListener("input", () => { zoom = Number(range.value) / 100; draw(); });

  let dragging = false, lastX = 0, lastY = 0;
  const frame = el.querySelector(".crop-frame");
  const scaleK = () => 520 / frame.getBoundingClientRect().width;
  frame.addEventListener("pointerdown", (ev) => {
    dragging = true; lastX = ev.clientX; lastY = ev.clientY;
    frame.setPointerCapture(ev.pointerId);
  });
  frame.addEventListener("pointermove", (ev) => {
    if (!dragging) return;
    offX += (ev.clientX - lastX) * scaleK();
    offY += (ev.clientY - lastY) * scaleK();
    lastX = ev.clientX; lastY = ev.clientY;
    draw();
  });
  frame.addEventListener("pointerup", () => { dragging = false; });
  frame.addEventListener("pointercancel", () => { dragging = false; });

  el.addEventListener("click", (ev) => {
    const act = ev.target.closest("[data-crop]");
    if (act?.dataset.crop === "cancel") { close(); return; }
    if (act?.dataset.crop === "done") {
      const out = document.createElement("canvas");
      out.width = 512; out.height = 512;
      out.getContext("2d").drawImage(canvas, 0, 0, 520, 520, 0, 0, 512, 512);
      out.toBlob((webp) => {
        if (webp && webp.type === "image/webp") { close(); onDone(webp); return; }
        out.toBlob((jpg) => { close(); onDone(jpg); }, "image/jpeg", 0.88);
      }, "image/webp", 0.85);
      return;
    }
    if (ev.target === el) close();
  });
}
