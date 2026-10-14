// Sends moderation alerts to Slack, Discord or any chat webhook.
//
// Triggered by Database Webhooks (Dashboard → Database → Webhooks), each with
// header `x-webhook-secret: <PUSH_WEBHOOK_SECRET>`, on INSERT into:
//   public.reports, public.verification_requests, public.app_errors
//
// Secrets: ALERT_WEBHOOK_URL (Slack "Incoming Webhook" or Discord webhook URL),
//          PUSH_WEBHOOK_SECRET (shared with the database webhooks),
//          ADMIN_PANEL_URL (optional, adds a link to the message).
// The admin panel also shows these live; this is for when nobody has it open.

type Payload = { type: string; table: string; record: Record<string, unknown> };

const lastErrorAlert = new Map<string, number>();

function describe(p: Payload, panel: string): string | null {
  const r = p.record;
  if (p.type !== "INSERT") return null;
  switch (p.table) {
    case "reports":
      return `🚩 New report: *${String(r.reason).replaceAll("_", " ")}*${r.details ? ` · "${String(r.details).slice(0, 200)}"` : ""}` +
        (panel ? `\n${panel}#/reports` : "");
    case "verification_requests":
      return `✅ New verification request waiting for review.` + (panel ? `\n${panel}#/verifications` : "");
    case "app_errors": {
      // Max one alert per error type every 30 minutes.
      const fp = String(r.fingerprint);
      const now = Date.now();
      if ((lastErrorAlert.get(fp) ?? 0) > now - 30 * 60_000) return null;
      lastErrorAlert.set(fp, now);
      return `🐞 App error (${r.platform ?? "?"} v${r.app_version ?? "?"}): ${String(r.message).slice(0, 300)}` +
        (panel ? `\n${panel}#/errors` : "");
    }
  }
  return null;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!secret || req.headers.get("x-webhook-secret") !== secret) return new Response("forbidden", { status: 403 });
  const hook = Deno.env.get("ALERT_WEBHOOK_URL");
  if (!hook) return new Response("ALERT_WEBHOOK_URL not set", { status: 503 });

  const text = describe((await req.json()) as Payload, Deno.env.get("ADMIN_PANEL_URL") ?? "");
  if (!text) return new Response("skipped");

  // Slack reads `text`, Discord reads `content`.
  const res = await fetch(hook, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text, content: text.replaceAll("*", "**") }),
  });
  return new Response(res.ok ? "sent" : `webhook failed ${res.status}`, { status: res.ok ? 200 : 502 });
});
