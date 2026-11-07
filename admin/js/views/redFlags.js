import { rpc } from '../api.js';
import { esc, fmtDate, pill } from '../ui.js';

// People with 3 or more red flags from matches in the last 30 days. Flags are
// private feedback, not reports: use this list to decide who to look at.
export async function render(view) {
  const rows = await rpc('admin_list_red_flagged');
  view.innerHTML = `
    <div class="page-head"><div><h1>Red flags</h1>
      <p class="muted">People who received 3 or more red flags in the last 30 days from matches they chatted with.
      Flags aren't reports: open the profile, check their reports and photos, then decide.</p></div></div>
    <div class="card table-wrap"><table>
      <thead><tr><th>Person</th><th>Red flags (30 days)</th><th>Green flags</th><th>Last flag</th><th>Status</th></tr></thead>
      <tbody>${rows.map((r) => `
        <tr class="clickable" data-user="${esc(r.user_id)}">
          <td><strong>${esc(r.display_name)}</strong></td>
          <td>🚩 ${esc(r.red_flags)}</td>
          <td>💚 ${esc(r.green_flags)}</td>
          <td class="small">${esc(fmtDate(r.last_flag_at))}</td>
          <td>${pill(r.status)}</td>
        </tr>`).join('') || '<tr><td colspan="5" class="empty">Nobody has 3 or more red flags right now.</td></tr>'}</tbody>
    </table></div>`;
  view.querySelectorAll('tr[data-user]').forEach((tr) =>
    tr.addEventListener('click', () => { location.hash = `#/users/${tr.dataset.user}`; }));
}
