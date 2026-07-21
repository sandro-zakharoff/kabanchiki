// Runtime configuration is loaded by telegram/config.js before the module.
// Both values are publishable client settings; authorization remains server-side.
const runtimeConfig = globalThis.__KABANCHIKI_CONFIG__ ?? {};

export const SUPABASE_URL = runtimeConfig.supabaseUrl ?? "";
export const SUPABASE_ANON_KEY = runtimeConfig.supabaseAnonKey ?? "";

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  throw new Error("Mini App public configuration is missing");
}

export const TG_AUTH_URL = `${SUPABASE_URL}/functions/v1/tg-auth`;
export const ADMIN_URL = `${SUPABASE_URL}/functions/v1/admin`;
export const DRIVE_URL = `${SUPABASE_URL}/functions/v1/drive`;

export const TASK_PHOTOS_BUCKET = "task-photos";
export const PROOF_PHOTOS_BUCKET = "proof-photos";
export const RECEIPTS_BUCKET = "receipts";
export const AVATARS_BUCKET = "avatars";

// Presence: a child seen within this window is treated as live-online.
export const ONLINE_WINDOW_MS = 50_000;
