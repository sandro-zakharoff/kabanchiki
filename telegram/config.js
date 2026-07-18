// Publishable Mini App bootstrap configuration.
//
// These are public client settings (the anon key is safe to ship — every table
// is protected by row-level security). Never place bot tokens, service-role
// keys, or other server secrets here.
//
// Fill these with your own Supabase project's values before publishing, or set
// the KABANCHIKI_SUPABASE_URL / KABANCHIKI_SUPABASE_ANON_KEY repository
// Variables and let the GitHub Pages workflow write this file at deploy time.
globalThis.__KABANCHIKI_CONFIG__ = {
  supabaseUrl: "",
  supabaseAnonKey: ""
};
