// Deletes proof files (ID documents and verification selfies) older than 7
// days, and expires reviews that were still pending after 7 days.
//
// Run it on a schedule (once a day is plenty): see supabase/schedule_cleanup.sql.
// It is also safe to call by hand. The admin panel runs the same cleanup each
// time an admin signs in, so files are removed even without the schedule.
//
// Required secret: CLEANUP_SECRET (sent by the scheduler as `x-cleanup-secret`).
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const secret = Deno.env.get("CLEANUP_SECRET");
  if (!secret || req.headers.get("x-cleanup-secret") !== secret) {
    return new Response("forbidden", { status: 403 });
  }

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await db.rpc("service_claim_expired_proofs");
  if (error) {
    console.error("claim failed", error);
    return Response.json({ error: error.message }, { status: 500 });
  }

  const byBucket = new Map<string, string[]>();
  for (const row of (data ?? []) as { bucket: string; path: string }[]) {
    byBucket.set(row.bucket, [...(byBucket.get(row.bucket) ?? []), row.path]);
  }

  let deleted = 0;
  const failures: string[] = [];
  for (const [bucket, paths] of byBucket) {
    // Storage accepts up to 1000 paths per call; claim returns at most 1000.
    const { data: removed, error: rmError } = await db.storage.from(bucket).remove(paths);
    if (rmError) failures.push(`${bucket}: ${rmError.message}`);
    deleted += removed?.length ?? 0;
  }
  if (failures.length) console.error("delete failures", failures);
  // Failed files stay listed and are retried on the next run.
  return Response.json({ deleted, failures });
});
