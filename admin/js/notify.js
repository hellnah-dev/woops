import { removeFiles, rpc, supabase } from './api.js';
import { $, toast } from './ui.js';

// Live alerts: new reports, verification requests and app errors arrive over
// Supabase Realtime (RLS limits these streams to admins). Each shows a toast,
// updates the sidebar badges and, if allowed, a browser notification.

export async function refreshBadges() {
  try {
    const s = await rpc('admin_stats');
    $('#badge-reports').textContent = s.reports_open || '';
    $('#badge-verifications').textContent = s.verifications_pending || '';
    $('#badge-errors').textContent = s.errors_unresolved || '';
  } catch { /* ignore */ }
}

function desktop(title, body) {
  if ('Notification' in window && Notification.permission === 'granted' && document.hidden) {
    new Notification(title, { body });
  }
}

export function enableDesktopAlerts() {
  if (!('Notification' in window)) return toast('This browser does not support notifications.', { type: 'warn' });
  Notification.requestPermission().then((p) =>
    toast(p === 'granted' ? 'Desktop alerts enabled.' : 'Desktop alerts were not allowed.', { type: p === 'granted' ? 'ok' : 'warn' }));
}

export function startRealtime() {
  const on = (table, handler) => ({ event: 'INSERT', schema: 'public', table, handler });
  const subs = [
    on('reports', (row) => {
      const msg = `New report: ${row.reason.replaceAll('_', ' ')}`;
      toast(msg, { type: row.reason === 'underage' ? 'error' : 'warn', onClick: () => (location.hash = '#/reports') });
      desktop('Woops: new report', msg);
    }),
    on('verification_requests', () => {
      toast('New verification request', { onClick: () => (location.hash = '#/verifications') });
      desktop('Woops', 'New verification request');
    }),
    on('age_verifications', (row) => {
      toast(`New ID to review (${row.document_type})`, { onClick: () => (location.hash = '#/age-checks') });
      desktop('Woops', 'New ID document to review');
    }),
    on('app_errors', (row) => {
      const msg = `App error: ${String(row.message).slice(0, 120)}`;
      toast(msg, { type: 'error', onClick: () => (location.hash = '#/errors') });
      desktop('Woops: app error', msg);
    }),
  ];
  let channel = supabase().channel('admin-alerts');
  for (const s of subs) {
    channel = channel.on('postgres_changes', { event: s.event, schema: s.schema, table: s.table }, (p) => {
      s.handler(p.new);
      refreshBadges();
    });
  }
  channel.subscribe();
  refreshBadges();
  setInterval(refreshBadges, 60_000);
  cleanupExpiredProofs();
  setInterval(cleanupExpiredProofs, 6 * 60 * 60 * 1000);
}

/**
 * Deletes ID documents and selfies older than 7 days (and expires reviews that
 * waited that long). The scheduled cleanup-proofs Edge Function does the same;
 * running it here too means files are removed even without the schedule.
 * Never interrupts the admin: failures are only logged and retried later.
 */
export async function cleanupExpiredProofs() {
  try {
    const rows = await rpc('admin_claim_expired_proofs');
    if (!rows?.length) return;
    const byBucket = {};
    for (const r of rows) (byBucket[r.bucket] ??= []).push(r.path);
    let removed = 0;
    for (const [bucket, paths] of Object.entries(byBucket)) {
      try { await removeFiles(bucket, paths); removed += paths.length; }
      catch (e) { console.warn('Proof cleanup failed for', bucket, e); }
    }
    if (removed) toast(`Deleted ${removed} proof file(s) older than 7 days.`, { type: 'ok', timeout: 4000 });
    refreshBadges();
  } catch (e) {
    // Older database without the cleanup function, or offline: try again later.
    console.warn('Proof cleanup skipped:', e?.message ?? e);
  }
}
