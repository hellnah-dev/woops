import { rpc } from '../api.js';
import { esc, flag } from '../ui.js';

export async function render(view) {
  const s = await rpc('admin_stats');
  const stat = (label, value, alert = false) =>
    `<div class="card stat ${alert && value > 0 ? 'alert' : ''}"><div class="value">${esc(value)}</div><div class="label">${esc(label)}</div></div>`;
  const days = s.signups_by_day ?? [];
  const max = Math.max(1, ...days.map((d) => d.count));
  view.innerHTML = `
    <div class="page-head"><div><h1>Dashboard</h1><p class="muted">Live overview of Woops. Chats are stored on phones; the server only counts messages and holds undelivered ones.</p></div></div>
    <div class="grid stats">
      ${stat('Users', s.users_total)}
      ${stat('New (24h)', s.users_new_24h)}
      ${stat('Active (24h)', s.users_active_24h)}
      ${stat('Verified', s.users_verified)}
      ${stat('Age confirmed', s.users_age_confirmed ?? 0)}
      ${stat('Ready to match', s.users_ready ?? 0)}
      ${stat('Likes (24h)', s.likes_24h)}
      ${stat('Matches (24h)', s.matches_24h)}
      ${stat('Messages sent (24h)', s.messages_24h)}
      ${stat('Waiting for delivery', s.messages_waiting ?? 0)}
      ${stat('Open reports', s.reports_open, true)}
      ${stat('Pending verifications', s.verifications_pending, true)}
      ${stat('Pending ID checks', s.age_checks_pending ?? 0, true)}
      ${stat('Unresolved errors', s.errors_unresolved, true)}
      ${stat('Suspended', s.users_suspended)}
      ${stat('Banned', s.users_banned)}
    </div>
    <div class="grid two-col" style="margin-top:14px">
      <div class="card"><h2>Sign-ups, last 14 days</h2>
        ${days.length ? `<div class="bars">${days.map((d) =>
          `<div class="bar" title="${esc(d.day)}: ${esc(d.count)}" style="height:${(d.count / max) * 100}%"><span>${esc(d.count)}</span></div>`).join('')}</div>`
          : '<p class="muted">No sign-ups yet.</p>'}
      </div>
      <div class="card"><h2>Top countries</h2>
        <table><tbody>${(s.users_by_country ?? []).map((c) =>
          `<tr><td>${flag(c.country)} ${esc(c.country)}</td><td style="text-align:right">${esc(c.count)}</td></tr>`).join('') ||
          '<tr><td class="muted">No users yet.</td></tr>'}</tbody></table>
      </div>
    </div>`;
}
