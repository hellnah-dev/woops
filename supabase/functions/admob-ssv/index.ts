// AdMob rewarded-ad Server-Side Verification (SSV) callback.
//
// Google calls this URL (GET) after a user finishes a rewarded ad:
//   https://<project-ref>.supabase.co/functions/v1/admob-ssv?...&signature=...&key_id=...
// We verify Google's ECDSA (P-256, SHA-256) signature with Google's published
// keys, then grant the reward in the database. The app itself can never grant
// a reward, so rewards can't be faked.
//
// Set the callback URL in AdMob → Apps → Ad units → (rewarded unit) →
// Server-side verification. Deploy with: supabase functions deploy admob-ssv --no-verify-jwt
//
// Optional secret: REWARD_LIKES (default 10) = extra likes per completed ad.
import { createClient } from "npm:@supabase/supabase-js@2";

const KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";
let cachedKeys: { fetchedAt: number; keys: Map<string, CryptoKey> } | null = null;

function base64UrlToBytes(input: string): Uint8Array {
  const b64 = input.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(input.length / 4) * 4, "=");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

/** Google signs with DER-encoded ECDSA; WebCrypto expects raw r||s (64 bytes). */
export function derToRaw(der: Uint8Array): Uint8Array {
  if (der[0] !== 0x30) throw new Error("bad_der");
  let offset = 2;
  if (der[1] & 0x80) offset = 2 + (der[1] & 0x7f);
  const readInt = () => {
    if (der[offset] !== 0x02) throw new Error("bad_der_int");
    const len = der[offset + 1];
    let value = der.slice(offset + 2, offset + 2 + len);
    offset += 2 + len;
    while (value.length > 32 && value[0] === 0) value = value.slice(1); // strip sign padding
    const out = new Uint8Array(32);
    out.set(value, 32 - value.length);
    return out;
  };
  const r = readInt();
  const s = readInt();
  const raw = new Uint8Array(64);
  raw.set(r, 0);
  raw.set(s, 32);
  return raw;
}

async function verifierKeys(): Promise<Map<string, CryptoKey>> {
  if (cachedKeys && Date.now() - cachedKeys.fetchedAt < 24 * 3600 * 1000) return cachedKeys.keys;
  const res = await fetch(KEYS_URL);
  if (!res.ok) throw new Error(`keys_fetch_failed ${res.status}`);
  const json = (await res.json()) as { keys: { keyId: number; base64: string }[] };
  const keys = new Map<string, CryptoKey>();
  for (const k of json.keys) {
    const spki = Uint8Array.from(atob(k.base64), (c) => c.charCodeAt(0));
    keys.set(
      String(k.keyId),
      await crypto.subtle.importKey("spki", spki, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]),
    );
  }
  cachedKeys = { fetchedAt: Date.now(), keys };
  return keys;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const query = url.search.slice(1);
  const sigIndex = query.indexOf("&signature=");
  if (sigIndex < 0) return new Response("missing signature", { status: 400 });

  // Signed content = every parameter before "&signature=", exactly as sent.
  const message = new TextEncoder().encode(query.slice(0, sigIndex));
  const params = url.searchParams;
  const signature = params.get("signature");
  const keyId = params.get("key_id");
  if (!signature || !keyId) return new Response("missing signature", { status: 400 });

  let valid = false;
  try {
    const key = (await verifierKeys()).get(keyId);
    if (key) {
      valid = await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        derToRaw(base64UrlToBytes(signature)),
        message,
      );
    }
  } catch (e) {
    console.error("verification error", e);
  }
  if (!valid) return new Response("invalid signature", { status: 403 });

  const userId = params.get("user_id") ?? "";
  const transactionId = params.get("transaction_id") ?? "";
  // AdMob's "Verify" test button sends no user id: acknowledge without granting.
  if (!UUID.test(userId) || !transactionId) return new Response("ok (test callback)", { status: 200 });
  if (params.get("custom_data") !== "likes") return new Response("ok (ignored)", { status: 200 });

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const rewardLikes = Math.min(Math.max(Number(Deno.env.get("REWARD_LIKES") ?? "10"), 1), 50);
  const { data, error } = await db.rpc("grant_ad_reward", {
    p_transaction_id: transactionId,
    p_user: userId,
    p_reward_likes: rewardLikes,
    p_ad_unit: params.get("ad_unit"),
  });
  if (error) {
    console.error("grant failed", error);
    return new Response("error", { status: 500 }); // Google retries on non-200
  }
  return new Response(`ok (${data})`, { status: 200 });
});
