// Data layer: Supabase client, Telegram sign-in, and every query/mutation the
// Mini App needs — mirroring the desktop's SupabaseService so behaviour matches.

// Pinned exact version: a floating @2 could silently change behaviour between
// releases; bump deliberately together with the ?v= cache stamps.
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.110.7/+esm";
import {
  SUPABASE_URL, SUPABASE_ANON_KEY, TG_AUTH_URL, ADMIN_URL, DRIVE_URL,
  TASK_PHOTOS_BUCKET, PROOF_PHOTOS_BUCKET, AVATARS_BUCKET,
} from "./config.js?v=218";
import { xhrUpload, blobToBase64 } from "./images.js?v=218";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
});

let serverOffsetMs = 0; // server_now ≈ Date.now() + serverOffsetMs
export function serverNow() { return new Date(Date.now() + serverOffsetMs); }

export class AuthNeeded extends Error {}   // opened outside Telegram
export class NotLinked extends Error {}    // Telegram account not bound to a parent
export class NetworkError extends Error {} // fetch failed: offline, DNS, CORS, timeout
export class AuthFailed extends Error {    // server answered, but sign-in is impossible
  constructor(code, status) { super(code); this.code = code; this.status = status; }
}

// POST JSON with a hard timeout; network-level failures become NetworkError.
async function postJson(url, headers, payload, timeoutMs = 15000) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  let resp;
  try {
    resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...headers },
      body: JSON.stringify(payload),
      signal: ctrl.signal,
    });
  } catch (e) {
    throw new NetworkError(e?.name === "AbortError" ? "timeout" : String(e?.message || e));
  } finally {
    clearTimeout(timer);
  }
  const data = await resp.json().catch(() => ({}));
  return { resp, data };
}

// ---- authentication -------------------------------------------------------

// Sign in using Telegram initData; on first run the deep-link code binds the
// account. Returns the parent row on success.
export async function signInWithTelegram(initData, startParam) {
  if (!initData) throw new AuthNeeded("no init data");
  const { resp, data } = await postJson(TG_AUTH_URL, {
    apikey: SUPABASE_ANON_KEY,
    Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
  }, { initData, start_param: startParam || "" });
  if (resp.status === 403 && data.error === "not_linked") throw new NotLinked();
  if (!resp.ok || !data.token_hash) {
    console.error("tg-auth failed", resp.status, data);
    throw new AuthFailed(data.error || `auth_failed_${resp.status}`, resp.status);
  }
  const { error } = await supabase.auth.verifyOtp({
    token_hash: data.token_hash, type: "magiclink",
  });
  if (error) throw new Error(error.message);
  return currentParent();
}

export async function currentParent() {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return null;
    const { data } = await supabase
      .from("parents").select("*").eq("id", user.id).maybeSingle();
    return data;
  } catch {
    return null; // stale/unreachable session -> fall back to Telegram sign-in
  }
}

export async function syncClock() {
  const { data } = await supabase.rpc("server_now");
  const server = new Date(data);
  if (!isNaN(server.getTime())) serverOffsetMs = server.getTime() - Date.now();
}

async function accessToken() {
  const { data: { session } } = await supabase.auth.getSession();
  return session?.access_token ?? "";
}

async function callAdmin(payload) {
  const { resp, data } = await postJson(ADMIN_URL, {
    apikey: SUPABASE_ANON_KEY,
    Authorization: `Bearer ${await accessToken()}`,
  }, payload);
  if (!resp.ok) throw new Error(data.error || `admin error ${resp.status}`);
  return data;
}

// ---- reads ----------------------------------------------------------------

export const listChildren = () =>
  supabase.from("profiles").select("*").order("created_at").then(r => r.data || []);

export const listDevices = () =>
  supabase.from("devices")
    .select("profile_id, updated_at, app_version, app_version_code")
    .then(r => r.data || []);

// Latest published Android build — drives the "update available" badge.
export const latestRelease = () =>
  supabase.from("app_releases").select("version_name, version_code")
    .eq("platform", "android")
    .order("version_code", { ascending: false }).limit(1).maybeSingle()
    .then(r => r.data || null);

export const listTasks = () =>
  supabase.from("tasks")
    .select("*, profiles(username, display_name, avatar_color, avatar_storage, avatar_path)")
    .order("created_at", { ascending: false }).then(r => r.data || []);

export const listAttachments = () =>
  supabase.from("attachments").select("*").order("created_at").then(r => r.data || []);

export const listJobs = () =>
  supabase.from("jobs").select("*").neq("status", "archived")
    .order("created_at", { ascending: false }).then(r => r.data || []);

export const listJobStats = () =>
  supabase.from("job_member_stats").select("*").then(r => r.data || []);

export const listWithdrawals = () =>
  supabase.from("withdrawals")
    .select("*, profiles(username, display_name, avatar_color, avatar_storage, avatar_path)")
    .order("requested_at", { ascending: false }).limit(300).then(r => r.data || []);

export const listLedger = () =>
  supabase.from("ledger_entries")
    .select("*, profiles(username, display_name, avatar_color)")
    .order("id", { ascending: false }).limit(1000).then(r => r.data || []);

export const listBonuses = () =>
  supabase.from("bonuses")
    .select("*, profiles(username, display_name, avatar_color)")
    .order("created_at", { ascending: false }).limit(300).then(r => r.data || []);

export const listEvents = () =>
  supabase.from("events").select("*").order("id", { ascending: false })
    .limit(300).then(r => r.data || []);

/**
 * The complete, ordered story of one entity — served by the server because the
 * feed above is capped and would truncate the history of anything older.
 */
export const entityTimeline = (entity, entityId) =>
  supabase.rpc("entity_timeline", { p_entity: entity, p_entity_id: entityId })
    .then((r) => { throwOnError(r); return r.data || []; });

export const listLocations = () =>
  supabase.from("locations").select("*").order("id", { ascending: false })
    .limit(200).then(r => r.data || []);

export const listParents = () =>
  supabase.from("parents").select("id, display_name, email").then(r => r.data || []);

// Save a place name we resolved for a point the phone left blank, so every
// client reads it from the DB and the lookup isn't repeated. Fills empties only.
export const setLocationPlace = (id, locality) =>
  supabase.rpc("set_location_place", { p_location_id: id, p_locality: locality }).then(throwOnError);

// ---- storage layer ---------------------------------------------------------
// Every attachment/avatar records where its file lives: 'supabase' (path =
// bucket object path) or 'drive' (path = Drive file id, link-shared). Writes
// follow app_config.storage_backend; when Drive misbehaves the upload falls
// back to Supabase so a photo never blocks the family.

let storageBackendValue = "supabase";
export const storageBackend = () => storageBackendValue;

export async function loadStorageConfig() {
  const { data } = await supabase.from("app_config")
    .select("storage_backend").limit(1).maybeSingle();
  storageBackendValue = data?.storage_backend === "drive" ? "drive" : "supabase";
  return storageBackendValue;
}

/** Money-related settings the owner UI needs (receipt rules, limits). */
export const loadAppConfig = () =>
  supabase.from("app_config")
    .select("min_withdrawal, withdrawals_enabled, auto_approve_below, require_receipt_for_card, currency")
    .limit(1).maybeSingle().then((r) => r.data || {});

const signedCache = new Map(); // `${bucket}/${path}` -> {url, until}

export async function signedUrl(bucket, path, expires = 3600) {
  if (!path) return "";
  const key = `${bucket}/${path}`;
  const hit = signedCache.get(key);
  if (hit && Date.now() < hit.until) return hit.url;
  const { data } = await supabase.storage.from(bucket).createSignedUrl(path, expires);
  const url = data?.signedUrl || "";
  if (url) signedCache.set(key, { url, until: Date.now() + (expires - 120) * 1000 });
  return url;
}

const BUCKET_BY_ROLE = { task: TASK_PHOTOS_BUCKET, proof: PROOF_PHOTOS_BUCKET };
const driveThumb = (id, w) => `https://drive.google.com/thumbnail?id=${id}&sz=w${w}`;

/** Display URL for an attachment row; thumb=true prefers the small rendition. */
export async function attachmentUrl(att, thumb = false) {
  if (!att?.path) return "";
  if (att.storage === "drive") {
    return driveThumb(thumb && att.thumb_path ? att.thumb_path : att.path, thumb ? 480 : 1920);
  }
  const bucket = BUCKET_BY_ROLE[att.role] || TASK_PHOTOS_BUCKET;
  const path = thumb && att.thumb_path ? att.thumb_path : att.path;
  return await signedUrl(bucket, path);
}

/** Avatar display URL ("" -> render initials). Synchronous: public URLs only. */
export function avatarUrl(profile, w = 160) {
  const path = profile?.avatar_path;
  if (!path) return "";
  if (profile.avatar_storage === "drive") return driveThumb(path, w);
  return `${SUPABASE_URL}/storage/v1/object/public/${AVATARS_BUCKET}/${path}`;
}

const rndName = (ext) => `${crypto.randomUUID()}.${ext}`;

async function uploadToBucket(bucket, path, blob, mime, onProgress) {
  await xhrUpload({
    url: `${SUPABASE_URL}/storage/v1/object/${bucket}/${path}`,
    headers: {
      Authorization: `Bearer ${await accessToken()}`,
      apikey: SUPABASE_ANON_KEY,
      "Content-Type": mime,
      "x-upsert": "false",
    },
    body: blob,
    onProgress,
  });
  return path;
}

async function uploadToDrive(kind, blob, mime, ext, onProgress) {
  const data = await xhrUpload({
    url: DRIVE_URL,
    headers: {
      Authorization: `Bearer ${await accessToken()}`,
      apikey: SUPABASE_ANON_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      action: "upload", kind, mime,
      filename: rndName(ext),
      data_base64: await blobToBase64(blob),
    }),
    onProgress,
  });
  if (!data.id) throw new Error(data.error || "drive upload failed");
  return data.id;
}

/**
 * Upload one optimized photo (full + thumb) for a task photo gallery.
 * kind 'task'; folder = child id (Supabase read policy is folder-scoped).
 * Returns {storage, path, thumb_path, mime, size_bytes}.
 */
export async function uploadTaskPhoto(childId, photo, onProgress) {
  const { blob, mime, ext } = photo.full;
  if (storageBackendValue === "drive") {
    try {
      const id = await uploadToDrive("task", blob, mime, ext, (p) => onProgress?.(p * 0.85));
      const thumbId = photo.thumb
        ? await uploadToDrive("task", photo.thumb.blob, photo.thumb.mime, photo.thumb.ext,
            (p) => onProgress?.(85 + p * 0.15))
        : null;
      return { storage: "drive", path: id, thumb_path: thumbId, mime, size_bytes: blob.size };
    } catch (e) {
      console.warn("drive upload failed, falling back to supabase", e);
    }
  }
  const base = `${childId}/${crypto.randomUUID()}`;
  const path = await uploadToBucket(TASK_PHOTOS_BUCKET, `${base}.${ext}`, blob, mime,
    (p) => onProgress?.(p * 0.85));
  const thumbPath = photo.thumb
    ? await uploadToBucket(TASK_PHOTOS_BUCKET, `${base}_t.${photo.thumb.ext}`,
        photo.thumb.blob, photo.thumb.mime, (p) => onProgress?.(85 + p * 0.15))
    : null;
  return { storage: "supabase", path, thumb_path: thumbPath, mime, size_bytes: blob.size };
}

export const insertAttachment = (taskId, role, info) =>
  supabase.from("attachments").insert({
    task_id: taskId, role, storage: info.storage, path: info.path,
    thumb_path: info.thumb_path ?? null, mime: info.mime ?? "image/jpeg",
    size_bytes: info.size_bytes ?? 0,
  }).then(throwOnError);

/** Removes the row; file cleanup is best-effort (orphans are harmless). */
export async function deleteAttachment(att) {
  await supabase.from("attachments").delete().eq("id", att.id).then(throwOnError);
  try {
    if (att.storage === "drive") {
      await postJson(DRIVE_URL, {
        apikey: SUPABASE_ANON_KEY,
        Authorization: `Bearer ${await accessToken()}`,
      }, { action: "delete", file_id: att.path });
    } else {
      const bucket = BUCKET_BY_ROLE[att.role] || TASK_PHOTOS_BUCKET;
      const paths = [att.path, att.thumb_path].filter(Boolean);
      await supabase.storage.from(bucket).remove(paths);
    }
  } catch (e) {
    console.warn("file cleanup failed", e);
  }
}

// ---- avatars ----------------------------------------------------------------

/** Upload a cropped avatar blob and point the profile at it. */
export async function setChildAvatar(childId, blob) {
  const ext = blob.type === "image/webp" ? "webp" : "jpg";
  let storage = "supabase";
  let path = "";
  if (storageBackendValue === "drive") {
    try {
      path = await uploadToDrive("avatar", blob, blob.type, ext);
      storage = "drive";
    } catch (e) {
      console.warn("drive avatar failed, falling back", e);
    }
  }
  if (!path) {
    path = await uploadToBucket(AVATARS_BUCKET, `${childId}/${rndName(ext)}`, blob, blob.type);
  }
  await supabase.from("profiles").update({
    avatar_storage: storage, avatar_path: path,
    avatar_updated_at: new Date().toISOString(),
  }).eq("id", childId).then(throwOnError);
}

export const clearChildAvatar = (childId) =>
  supabase.from("profiles").update({
    avatar_storage: null, avatar_path: null,
    avatar_updated_at: new Date().toISOString(),
  }).eq("id", childId).then(throwOnError);

// ---- tasks ----------------------------------------------------------------

/**
 * Create one task per child; photos: [{key, full, thumb}] are uploaded with
 * per-photo progress via onPhoto(key, pct). On Drive one upload serves every
 * child; on Supabase each child gets a copy in their read-scoped folder.
 */
export async function createTask(fields, childIds, photos = [], onPhoto = null) {
  const driveInfos = {};
  if (storageBackendValue === "drive") {
    for (const p of photos) {
      driveInfos[p.key] = await uploadTaskPhoto(childIds[0], p, (pct) => onPhoto?.(p.key, pct));
    }
  }
  for (let c = 0; c < childIds.length; c++) {
    const childId = childIds[c];
    const { data, error } = await supabase.from("tasks")
      .insert({ ...fields, child_id: childId }).select("id").single();
    if (error) throw new Error(error.message);
    for (const p of photos) {
      let info = driveInfos[p.key];
      if (!info || info.storage !== "drive") {
        info = await uploadTaskPhoto(childId, p, (pct) =>
          onPhoto?.(p.key, Math.round((c * 100 + pct) / childIds.length)));
      }
      await insertAttachment(data.id, "task", info);
    }
  }
}

export const updateTask = (taskId, fields) =>
  supabase.from("tasks").update(fields).eq("id", taskId).then(throwOnError);

/** Add photos to an existing task (edit flow). */
export async function addTaskPhotos(task, photos, onPhoto = null) {
  for (const p of photos) {
    const info = await uploadTaskPhoto(task.child_id, p, (pct) => onPhoto?.(p.key, pct));
    await insertAttachment(task.id, "task", info);
  }
}

export const reviewTask = (taskId, action, note) =>
  supabase.rpc("task_review", { p_task_id: taskId, p_action: action, p_note: note || null })
    .then(throwOnError);
export const deleteTask = (taskId) =>
  supabase.from("tasks").delete().eq("id", taskId).then(throwOnError);

export async function duplicateTask(taskId) {
  const { data: src } = await supabase.from("tasks").select("*").eq("id", taskId).single();
  if (!src) throw new Error("task not found");
  const { data: fresh, error } = await supabase.from("tasks").insert({
    child_id: src.child_id, title: src.title, description: src.description,
    photo_path: src.photo_path, reward_type: src.reward_type,
    reward_amount: src.reward_amount, difficulty: src.difficulty,
    requirements: src.requirements, proof_text: src.proof_text,
    proof_photo: src.proof_photo, completion_mode: src.completion_mode || "timer",
  }).select("id").single();
  if (error) throw new Error(error.message);
  // carry the reference photos over (same files, new rows)
  const { data: atts } = await supabase.from("attachments")
    .select("*").eq("task_id", taskId).eq("role", "task");
  for (const a of atts || []) {
    await insertAttachment(fresh.id, "task", a);
  }
}

// ---- jobs -----------------------------------------------------------------

export async function createJob(fields, childIds) {
  const { data, error } = await supabase.from("jobs").insert(fields).select("id").single();
  if (error) throw new Error(error.message);
  if (childIds.length) {
    await supabase.from("job_members")
      .insert(childIds.map(c => ({ job_id: data.id, child_id: c }))).then(throwOnError);
  }
}
export const jobStart = (id) => supabase.rpc("admin_job_start", { p_job_id: id }).then(throwOnError);
export const jobStop = (id) => supabase.rpc("admin_job_stop", { p_job_id: id }).then(throwOnError);
export const jobArchive = (id) => supabase.rpc("admin_job_archive", { p_job_id: id }).then(throwOnError);
export const jobDelete = (id) => supabase.from("jobs").delete().eq("id", id).then(throwOnError);

// Update fields and reconcile the member list (mirrors the desktop service).
export async function updateJob(jobId, fields, childIds) {
  await supabase.from("jobs").update(fields).eq("id", jobId).then(throwOnError);
  const { data: current } = await supabase.from("job_members")
    .select("child_id").eq("job_id", jobId);
  const have = new Set((current || []).map((m) => m.child_id));
  const want = new Set(childIds);
  const drop = [...have].filter((id) => !want.has(id));
  const add = [...want].filter((id) => !have.has(id));
  if (drop.length) {
    await supabase.from("job_members").delete()
      .eq("job_id", jobId).in("child_id", drop).then(throwOnError);
  }
  if (add.length) {
    await supabase.from("job_members")
      .insert(add.map((c) => ({ job_id: jobId, child_id: c }))).then(throwOnError);
  }
}

// ---- withdrawals (payouts) ------------------------------------------------

// Owner-initiated payout: create an approved withdrawal (reserved). null = all.
export async function createWithdrawal(childId, amount) {
  const { data, error } = await supabase.rpc("admin_create_withdrawal",
    { p_child: childId, p_amount: amount });
  if (error) throw new Error(error.message);
  return String(data).replace(/"/g, "");
}
export const withdrawalApprove = (id) =>
  supabase.rpc("admin_withdrawal_approve", { p_id: id }).then(throwOnError);
export const withdrawalReject = (id, reason) =>
  supabase.rpc("admin_withdrawal_reject", { p_id: id, p_reason: reason || null }).then(throwOnError);
export const withdrawalPay = (id, method, comment) =>
  supabase.rpc("admin_withdrawal_pay", { p_id: id, p_method: method, p_comment: comment || null })
    .then(throwOnError);
export const attachReceipt = (withdrawalId, info) =>
  supabase.from("attachments").insert({
    withdrawal_id: withdrawalId, role: "receipt", storage: info.storage, path: info.path,
    thumb_path: info.thumb_path || null, mime: info.mime || "image/jpeg",
    size_bytes: info.size_bytes || 0,
  }).then(throwOnError);

// ---- balance --------------------------------------------------------------

export const adjustBalance = (childId, amount, note) =>
  supabase.rpc("admin_adjust_balance", { p_child: childId, p_amount: amount, p_note: (note || "").trim() })
    .then(throwOnError);

// ---- bonuses (legacy edit/delete from the journal; still ledger-backed) ----

export const updateBonus = (id, amount, note) =>
  supabase.from("bonuses").update({ amount, note: (note || "").trim() }).eq("id", id).then(throwOnError);
export const deleteBonus = (id) =>
  supabase.from("bonuses").delete().eq("id", id).then(throwOnError);

// ---- children / accounts (admin edge function) ----------------------------

export const createChild = (username, displayName, password, color) =>
  callAdmin({ action: "create_child", username: username.trim().toLowerCase(),
    display_name: displayName.trim(), password, avatar_color: color });
export const setChildPassword = (childId, password) =>
  callAdmin({ action: "set_child_password", child_id: childId, password });
export const setChildBlocked = (childId, blocked) =>
  callAdmin({ action: "set_child_blocked", child_id: childId, blocked });
export const deleteChild = (childId) =>
  callAdmin({ action: "delete_child", child_id: childId });
export const updateChild = (childId, displayName, color) =>
  supabase.from("profiles").update({ display_name: displayName.trim(), avatar_color: color })
    .eq("id", childId).then(throwOnError);

function throwOnError(res) {
  if (res && res.error) throw new Error(res.error.message || String(res.error));
  return res;
}
