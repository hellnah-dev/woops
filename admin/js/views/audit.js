import { supabase } from '../api.js';
import { esc, fmtDate } from '../ui.js';

export async function render(view) {
  const { data: rows, error } = await supabase().from('admin_actions').select('*').order('created_at', { ascending: false }).limit(300);
  if (error) throw error;
  view.innerHTML = `
    <div class="page-head"><div><h1>Audit log</h1><p class="muted">Every admin action, newest first.</p></div></div>
    <div class="card table-wrap"><table><thead><tr><th>When</th><th>Action</th><th>Target</th><th>Details</th><th>Admin</th></tr></thead>
      <tbody>${rows.map((a) => `<tr><td class="small">${esc(fmtDate(a.created_at))}</td><td><strong>${esc(a.action)}</strong></td>
        <td>${a.target_user ? `<a href="#/users/${esc(a.target_user)}">user</a>` : ''} <span class="muted small">${esc(a.target_id ?? '')}</span></td>
        <td class="small">${esc(JSON.stringify(a.details))}</td><td class="small"><code>${esc(a.admin_id?.slice(0, 8) ?? '')}</code></td></tr>`).join('') ||
        '<tr><td colspan="5" class="empty">Nothing yet.</td></tr>'}</tbody></table></div>`;
}
