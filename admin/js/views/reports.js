import { rpc, signedUrls, thumbPath } from '../api.js';
import { ask, esc, fmtDate, pill, toast } from '../ui.js';

export async function render(view, _params, rerender) {
  const status = sessionStorage.getItem('reports-status') ?? 'open';
  const rows = await rpc('admin_list_reports', { p_status: status === 'all' ? null : status, p_limit: 200 });
  const photos = await signedUrls('profile-photos', rows.map((r) => r.reported_photo && thumbPath(r.reported_photo)).filter(Boolean))
    .catch(() => ({}));

  view.innerHTML = `
    <div class="page-head"><div><h1>Reports</h1><p class="muted">Reporter identities are never shown to the reported user.</p></div>
      <span class="spacer"></span>
      <select id="status">${['open', 'reviewing', 'actioned', 'dismissed', 'all'].map((s) =>
        `<option ${s === status ? 'selected' : ''}>${s}</option>`).join('')}</select></div>
    <div class="card table-wrap">${rows.length ? `
      <table><thead><tr><th></th><th>Reported user</th><th>Reason</th><th>Details</th><th>Reporter</th><th>When</th><th>Status</th><th>Actions</th></tr></thead>
      <tbody>${rows.map((r) => `
        <tr>
          <td><img class="thumb" alt="" src="${esc(photos[thumbPath(r.reported_photo)] ?? '')}"></td>
          <td><a href="#/users/${esc(r.reported_id)}">${esc(r.reported_name ?? '(deleted)')}</a><br>
              ${pill(r.reported_status ?? 'deleted')} <span class="muted small">${esc(r.open_reports_against)} open</span></td>
          <td>${pill(r.reason)}</td>
          <td>${esc(r.details ?? '')}${r.message_body ? `<div class="muted small">Message: “${esc(r.message_body)}”</div>` : ''}</td>
          <td>${r.reporter_id ? `<a href="#/users/${esc(r.reporter_id)}">${esc(r.reporter_name ?? '?')}</a>` : '<span class="muted">deleted</span>'}</td>
          <td class="small">${esc(fmtDate(r.created_at))}</td>
          <td>${pill(r.status)}</td>
          <td><div class="toolbar">
            <button class="btn small" data-act="dismissed" data-id="${esc(r.id)}">Dismiss</button>
            <button class="btn small warn" data-act="suspended" data-id="${esc(r.id)}">Suspend</button>
            <button class="btn small danger" data-act="banned" data-id="${esc(r.id)}">Ban</button>
          </div></td>
        </tr>`).join('')}</tbody></table>` : '<div class="empty">No reports here 🎉</div>'}
    </div>`;

  view.querySelector('#status').onchange = (e) => { sessionStorage.setItem('reports-status', e.target.value); rerender(); };
  view.querySelectorAll('[data-act]').forEach((btn) => btn.addEventListener('click', async () => {
    const act = btn.dataset.act;
    const note = act === 'dismissed'
      ? await ask({ title: 'Dismiss this report?', confirmLabel: 'Dismiss' })
      : await ask({ title: act === 'banned' ? 'Ban this user?' : 'Suspend this user?', danger: true, input: true,
                    message: act === 'banned' ? 'Banned users cannot sign up again with the same email or username.' : 'They will be hidden until reactivated.',
                    placeholder: 'Reason (saved in the audit log)', confirmLabel: act === 'banned' ? 'Ban' : 'Suspend' });
    if (note === null) return;
    try {
      await rpc('admin_resolve_report', {
        p_report: btn.dataset.id,
        p_status: act === 'dismissed' ? 'dismissed' : 'actioned',
        p_user_action: act === 'dismissed' ? null : act,
        p_note: typeof note === 'string' ? note : null,
      });
      toast('Report updated', { type: 'ok' });
      rerender();
    } catch (e) { toast(e.message, { type: 'error' }); }
  }));
}
