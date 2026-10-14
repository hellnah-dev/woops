// Sends push notifications through Firebase Cloud Messaging (HTTP v1).
// FCM delivers to Android directly and to iOS through APNs (upload your APNs
// key in Firebase → Project settings → Cloud Messaging).
//
// Triggered by Supabase Database Webhooks (Dashboard → Database → Webhooks) on:
//   INSERT public.messages  -> "New message"
//   INSERT public.matches   -> "It's a match!"
//   INSERT public.swipes    -> "Someone liked you" (likes only; never reveals who)
// Each webhook must send the header `x-webhook-secret: <PUSH_WEBHOOK_SECRET>`.
//
// Required secrets (supabase secrets set ...):
//   PUSH_WEBHOOK_SECRET        random string shared with the webhooks
//   FCM_SERVICE_ACCOUNT_JSON   Firebase service-account JSON (one line)
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

type WebhookPayload = {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  schema: string;
  record: Record<string, unknown>;
};

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

type Push = {
  userId: string;
  pref: "new_messages" | "new_matches" | "new_likes";
  title: string;
  body: string;
  data: Record<string, string>;
};

let cachedToken: { value: string; expiresAt: number } | null = null;

async function googleAccessToken(sa: ServiceAccount): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.value;
  const key = await importPKCS8(sa.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`google_token_failed ${res.status}: ${await res.text()}`);
  const json = await res.json();
  cachedToken = { value: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
  return cachedToken.value;
}

function truncate(text: string, max = 120): string {
  return text.length <= max ? text : `${text.slice(0, max - 1)}…`;
}

async function displayName(db: SupabaseClient, userId: string): Promise<string> {
  const { data } = await db.from("profiles").select("display_name").eq("id", userId).maybeSingle();
  return (data?.display_name as string | undefined) ?? "Someone";
}

async function buildPushes(db: SupabaseClient, payload: WebhookPayload): Promise<Push[]> {
  const r = payload.record;
  if (payload.type !== "INSERT") return [];

  if (payload.table === "messages") {
    if (r.kind === "system") return [];
    const senderId = r.sender_id as string;
    const { data: members } = await db
      .from("conversation_members")
      .select("user_id")
      .eq("conversation_id", r.conversation_id as string)
      .neq("user_id", senderId);
    const name = await displayName(db, senderId);
    const body = r.kind === "image" ? "Sent you a photo" : truncate(String(r.body ?? ""));
    return (members ?? []).map((m) => ({
      userId: m.user_id as string,
      pref: "new_messages" as const,
      title: name,
      body,
      data: { type: "message", conversation_id: String(r.conversation_id) },
    }));
  }

  if (payload.table === "matches") {
    const a = r.user_low as string;
    const b = r.user_high as string;
    const [nameA, nameB] = await Promise.all([displayName(db, a), displayName(db, b)]);
    const mk = (userId: string, other: string): Push => ({
      userId,
      pref: "new_matches",
      title: "It’s a match! 🎉",
      body: `You and ${other} liked each other. Say hi!`,
      data: { type: "match", match_id: String(r.id) },
    });
    return [mk(a, nameB), mk(b, nameA)];
  }

  if (payload.table === "swipes" && r.action === "like") {
    // If this like created a match, the match notification covers it.
    const { data: reverse } = await db
      .from("swipes")
      .select("action")
      .eq("swiper_id", r.swipee_id as string)
      .eq("swipee_id", r.swiper_id as string)
      .eq("action", "like")
      .maybeSingle();
    if (reverse) return [];
    return [{
      userId: r.swipee_id as string,
      pref: "new_likes",
      title: "Someone likes you 💘",
      body: "Open Amora to see who.",
      data: { type: "like" },
    }];
  }

  return [];
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!secret || req.headers.get("x-webhook-secret") !== secret) {
    return new Response("forbidden", { status: 403 });
  }
  const saJson = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!saJson) return new Response("FCM not configured", { status: 503 });
  const sa = JSON.parse(saJson) as ServiceAccount;

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const payload = (await req.json()) as WebhookPayload;
  const pushes = await buildPushes(db, payload);
  if (pushes.length === 0) return Response.json({ sent: 0 });

  const userIds = [...new Set(pushes.map((p) => p.userId))];
  const [{ data: prefs }, { data: tokens }] = await Promise.all([
    db.from("notification_preferences").select("*").in("user_id", userIds),
    db.from("device_tokens").select("token, user_id, platform").in("user_id", userIds),
  ]);
  const prefByUser = new Map((prefs ?? []).map((p) => [p.user_id as string, p]));

  const accessToken = await googleAccessToken(sa);
  let sent = 0;
  const staleTokens: string[] = [];

  for (const push of pushes) {
    const pref = prefByUser.get(push.userId);
    if (pref && pref[push.pref] === false) continue;

    for (const t of (tokens ?? []).filter((t) => t.user_id === push.userId)) {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: t.token,
            notification: { title: push.title, body: push.body },
            data: push.data,
            android: { priority: "high", notification: { sound: "default" } },
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
      });
      if (res.ok) {
        sent++;
      } else {
        const text = await res.text();
        // Token no longer valid (app uninstalled, etc.): clean it up.
        if (res.status === 404 || text.includes("UNREGISTERED") || text.includes("INVALID_ARGUMENT")) {
          staleTokens.push(t.token as string);
        } else {
          console.error("FCM send failed", res.status, text);
        }
      }
    }
  }

  if (staleTokens.length) await db.from("device_tokens").delete().in("token", staleTokens);
  return Response.json({ sent, removed: staleTokens.length });
});
