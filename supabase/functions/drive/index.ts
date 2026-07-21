// Kabanchiki: Google Drive storage bridge.
//
// The family's files can live on the owner's Google Drive (scope drive.file —
// only files this app created). The owner connects Drive once from the desktop;
// the refresh token is stored in app_secrets (service_role only), exactly like
// the Telegram bot token. Children and the Mini App have no Google session, so
// their uploads go through this function:
//
//   upload  — any signed-in family member; children only for 'proof'/'avatar'.
//   delete  — parents only (best-effort cleanup of replaced/removed photos).
//   status  — parents: live connection check (Drive about.get).
//
// Files are uploaded into Kabanchiki/{tasks,proofs,avatars,receipts} and link-shared
// (reader, anyone-with-link): displays go straight to Google's CDN thumbnail
// endpoint without tokens, which caches well on every client. Privacy relies
// on unguessable file ids + EXIF/GPS being stripped client-side before upload
// — the same trust model as Supabase signed URLs.

import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------- secrets

type Secrets = {
  gdrive_client_id: string | null;
  gdrive_client_secret: string | null;
  gdrive_refresh_token: string | null;
  gdrive_folders: Record<string, string> | null;
};

async function getSecrets(): Promise<Secrets | null> {
  const { data } = await admin
    .from("app_secrets")
    .select("gdrive_client_id, gdrive_client_secret, gdrive_refresh_token, gdrive_folders")
    .eq("id", true)
    .maybeSingle();
  if (!data?.gdrive_client_id || !data?.gdrive_client_secret || !data?.gdrive_refresh_token) {
    return null;
  }
  return data as Secrets;
}

// Access token cache survives across warm invocations of the same isolate.
let cachedToken = "";
let cachedUntil = 0;

async function accessToken(s: Secrets): Promise<string> {
  if (cachedToken && Date.now() < cachedUntil - 60_000) return cachedToken;
  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: s.gdrive_client_id!,
      client_secret: s.gdrive_client_secret!,
      refresh_token: s.gdrive_refresh_token!,
      grant_type: "refresh_token",
    }),
  });
  const data = await resp.json().catch(() => ({}));
  if (!resp.ok || !data.access_token) {
    console.error("token refresh failed", resp.status, data);
    throw new DriveError(
      data.error === "invalid_grant" ? "drive_reauth_needed" : "drive_token_failed",
      502,
    );
  }
  cachedToken = data.access_token;
  cachedUntil = Date.now() + (data.expires_in ?? 3600) * 1000;
  return cachedToken;
}

class DriveError extends Error {
  status: number;
  constructor(code: string, status = 500) {
    super(code);
    this.status = status;
  }
}

// ---------------------------------------------------------------- folders

const KIND_FOLDER: Record<string, string> = {
  task: "tasks",
  proof: "proofs",
  avatar: "avatars",
  receipt: "receipts",
};

async function driveFetch(token: string, url: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(url, {
    ...init,
    headers: { Authorization: `Bearer ${token}`, ...(init.headers ?? {}) },
  });
}

async function createFolder(token: string, name: string, parent?: string): Promise<string> {
  const resp = await driveFetch(token, "https://www.googleapis.com/drive/v3/files", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      name,
      mimeType: "application/vnd.google-apps.folder",
      ...(parent ? { parents: [parent] } : {}),
    }),
  });
  const data = await resp.json().catch(() => ({}));
  if (!resp.ok || !data.id) {
    console.error("folder create failed", resp.status, data);
    throw new DriveError("drive_folder_failed", 502);
  }
  return data.id as string;
}

async function folderExists(token: string, id: string): Promise<boolean> {
  const resp = await driveFetch(
    token,
    `https://www.googleapis.com/drive/v3/files/${id}?fields=id,trashed`,
  );
  if (!resp.ok) return false;
  const data = await resp.json().catch(() => ({}));
  return !!data.id && !data.trashed;
}

// Kabanchiki/{tasks,proofs,avatars,receipts}; ids cached in app_secrets.gdrive_folders.
async function ensureFolders(token: string, s: Secrets): Promise<Record<string, string>> {
  let folders = s.gdrive_folders ?? {};
  const subs = Object.values(KIND_FOLDER);

  if (folders.root && await folderExists(token, folders.root)) {
    // A tree created by an older version lacks any folder added since, so fill
    // the gaps rather than only ever building the whole tree at once.
    const missing = subs.filter((sub) => !folders[sub]);
    if (missing.length === 0) return folders;
    folders = { ...folders };
    for (const sub of missing) folders[sub] = await createFolder(token, sub, folders.root);
  } else {
    const root = await createFolder(token, "Kabanchiki");
    folders = { root };
    for (const sub of subs) folders[sub] = await createFolder(token, sub, root);
  }
  await admin.from("app_secrets").update({ gdrive_folders: folders }).eq("id", true);
  return folders;
}

// ---------------------------------------------------------------- upload

const MAX_UPLOAD_BYTES = 8 * 1024 * 1024; // optimized photos are ~0.5 MB

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function uploadFile(
  token: string,
  folderId: string,
  filename: string,
  mime: string,
  bytes: Uint8Array,
): Promise<string> {
  const boundary = `kab${crypto.randomUUID()}`;
  const meta = JSON.stringify({ name: filename, parents: [folderId] });
  const head = new TextEncoder().encode(
    `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${meta}\r\n` +
      `--${boundary}\r\nContent-Type: ${mime}\r\n\r\n`,
  );
  const tail = new TextEncoder().encode(`\r\n--${boundary}--`);
  const body = new Uint8Array(head.length + bytes.length + tail.length);
  body.set(head, 0);
  body.set(bytes, head.length);
  body.set(tail, head.length + bytes.length);

  const resp = await driveFetch(
    token,
    "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id",
    {
      method: "POST",
      headers: { "Content-Type": `multipart/related; boundary=${boundary}` },
      body,
    },
  );
  const data = await resp.json().catch(() => ({}));
  if (!resp.ok || !data.id) {
    console.error("upload failed", resp.status, data);
    throw new DriveError("drive_upload_failed", 502);
  }

  // Link-share so clients can render via the CDN thumbnail endpoint.
  const perm = await driveFetch(
    token,
    `https://www.googleapis.com/drive/v3/files/${data.id}/permissions`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ role: "reader", type: "anyone" }),
    },
  );
  if (!perm.ok) {
    console.error("permission failed", perm.status, await perm.text());
    throw new DriveError("drive_share_failed", 502);
  }
  return data.id as string;
}

// ---------------------------------------------------------------- caller

type Caller = { id: string; isParent: boolean };

async function identify(req: Request): Promise<Caller | null> {
  const auth = req.headers.get("Authorization") ?? "";
  const jwt = auth.replace(/^Bearer\s+/i, "");
  if (!jwt) return null;
  const { data, error } = await admin.auth.getUser(jwt);
  if (error || !data.user) return null;
  const uid = data.user.id;
  const { data: parent } = await admin
    .from("parents").select("id, disabled").eq("id", uid).maybeSingle();
  if (parent && !parent.disabled) return { id: uid, isParent: true };
  const { data: child } = await admin
    .from("profiles").select("id, blocked").eq("id", uid).maybeSingle();
  if (child && !child.blocked) return { id: uid, isParent: false };
  return null;
}

// ---------------------------------------------------------------- handler

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "bad_json" }, 400);
  }

  const caller = await identify(req);
  if (!caller) return json({ error: "unauthorized" }, 401);

  try {
    const action = String(payload.action ?? "");

    if (action === "status") {
      if (!caller.isParent) return json({ error: "forbidden" }, 403);
      const s = await getSecrets();
      if (!s) return json({ connected: false, error: "drive_not_configured" });
      const token = await accessToken(s);
      const resp = await driveFetch(
        token,
        "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress),storageQuota(usage,limit)",
      );
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) return json({ connected: false, error: "drive_unreachable" });
      return json({
        connected: true,
        email: data.user?.emailAddress ?? "",
        usage: Number(data.storageQuota?.usage ?? 0),
        limit: Number(data.storageQuota?.limit ?? 0),
      });
    }

    if (action === "upload") {
      const kind = String(payload.kind ?? "");
      if (!KIND_FOLDER[kind]) return json({ error: "bad_kind" }, 400);
      // Children may only push completion proofs and their own avatar.
      if (!caller.isParent && (kind === "task" || kind === "receipt")) {
        return json({ error: "forbidden" }, 403);
      }

      const b64 = String(payload.data_base64 ?? "");
      if (!b64) return json({ error: "no_data" }, 400);
      if (b64.length > MAX_UPLOAD_BYTES * 1.4) return json({ error: "too_large" }, 413);
      const bytes = b64ToBytes(b64);
      if (bytes.length > MAX_UPLOAD_BYTES) return json({ error: "too_large" }, 413);

      const mime = String(payload.mime ?? "image/jpeg");
      // A receipt is often a bank PDF; everything else stays a picture.
      const mimeOk = kind === "receipt"
        ? /^(image\/(jpeg|png|webp)|application\/pdf)$/.test(mime)
        : /^image\/(jpeg|png|webp)$/.test(mime);
      if (!mimeOk) return json({ error: "bad_mime" }, 400);
      const filename = String(payload.filename ?? "photo.jpg").replace(/[^\w.\-]/g, "_");

      const s = await getSecrets();
      if (!s) return json({ error: "drive_not_configured" }, 409);
      const token = await accessToken(s);
      const folders = await ensureFolders(token, s);
      const id = await uploadFile(token, folders[KIND_FOLDER[kind]], filename, mime, bytes);
      return json({ id });
    }

    if (action === "delete") {
      if (!caller.isParent) return json({ error: "forbidden" }, 403);
      const fileId = String(payload.file_id ?? "");
      if (!fileId) return json({ error: "no_file_id" }, 400);
      const s = await getSecrets();
      if (!s) return json({ error: "drive_not_configured" }, 409);
      const token = await accessToken(s);
      const resp = await driveFetch(
        token,
        `https://www.googleapis.com/drive/v3/files/${fileId}`,
        { method: "DELETE" },
      );
      // 404 = already gone; both count as success for cleanup.
      if (!resp.ok && resp.status !== 404) {
        console.error("delete failed", resp.status, await resp.text());
        return json({ error: "drive_delete_failed" }, 502);
      }
      return json({ ok: true });
    }

    return json({ error: "unknown_action" }, 400);
  } catch (e) {
    if (e instanceof DriveError) return json({ error: e.message }, e.status);
    console.error("drive function error", e);
    return json({ error: "internal" }, 500);
  }
});
