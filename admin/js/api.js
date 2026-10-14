import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';

let client;

export function initClient(url, key) {
  client = createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true } });
  return client;
}

export const supabase = () => client;

/** Calls an RPC and throws on error. Every admin_* function re-checks admin rights on the server. */
export async function rpc(name, params = {}) {
  const { data, error } = await client.rpc(name, params);
  if (error) throw error;
  return data;
}

const urlCache = new Map();

/** Short-lived signed URLs for private images (storage RLS allows admins). */
export async function signedUrls(bucket, paths) {
  const missing = paths.filter((p) => p && !urlCache.has(`${bucket}/${p}`));
  if (missing.length) {
    const { data, error } = await client.storage.from(bucket).createSignedUrls(missing, 3600);
    if (error) throw error;
    for (const item of data ?? []) {
      if (item.signedUrl) urlCache.set(`${bucket}/${item.path}`, item.signedUrl);
    }
  }
  return Object.fromEntries(paths.map((p) => [p, urlCache.get(`${bucket}/${p}`) ?? '']));
}

/** Thumbnail path convention used by the app (falls back to the full photo). */
export const thumbPath = (path) => path?.replace(/(\.[a-z0-9]+)$/i, '_thumb$1');

export async function removeFiles(bucket, paths) {
  const { error } = await client.storage.from(bucket).remove(paths);
  if (error) throw error;
}
