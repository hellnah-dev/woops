// Permanently deletes the calling user's account.
//
// 1. Verifies the caller's JWT.
// 2. Removes all of their files from the `profile-photos` and `moments` buckets.
// 3. Deletes the auth user, which cascades (ON DELETE CASCADE) to their
//    profile, photos rows, likes, matches, conversations and messages.
//    Reports keep their row with reporter/reported set to NULL.
//
// Needs the service-role key, which Supabase injects automatically into Edge
// Functions. It is never shipped in the app.
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "not_authenticated" }, 401);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user) return json({ error: "not_authenticated" }, 401);

  // Delete their profile photos and moment photos, in batches (storage list is paginated).
  for (const name of ["profile-photos", "moments"]) {
    const bucket = admin.storage.from(name);
    for (let i = 0; i < 50; i++) {
      const { data: files, error } = await bucket.list(user.id, { limit: 100 });
      if (error) return json({ error: "storage_list_failed", detail: error.message }, 500);
      if (!files || files.length === 0) break;
      const { error: removeError } = await bucket.remove(files.map((f) => `${user.id}/${f.name}`));
      if (removeError) return json({ error: "storage_remove_failed", detail: removeError.message }, 500);
    }
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) return json({ error: "delete_failed", detail: deleteError.message }, 500);

  return json({ deleted: true });
});
