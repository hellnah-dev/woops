import { rpc, signedUrls } from '../api.js';
import { ask, esc, flag, fmtDate, toast } from '../ui.js';

export async function render(view, _params, rerender) {
  const rows = await rpc('admin_list_verifications', { p_status: 'pending' });
  const selfies = await signedUrls('verification-selfies', rows.map((r) => r.selfie_path)).catch(() => ({}));
  const photos = await signedUrls('profile-photos', rows.flatMap((r) => r.photos)).catch(() => ({}));

  view.innerHTML = `
    <div class="page-head"><div><h1>Verifications</h1>
      <p class="muted">Approve only if the selfie clearly shows the same person as the profile photos, doing the ✌️ pose, and they look 18+.</p></div></div>
    ${rows.length ? rows.map((r) => `
      <div class="card" style="margin-bottom:14px">
        <div class="toolbar" style="margin-bottom:10px">
          <strong><a href="#/users/${esc(r.user_id)}">${esc(r.display_name)}</a>, ${esc(r.age)}</strong>
          <span>${flag(r.country_code)}</span>
          <span class="muted small">requested ${esc(fmtDate(r.created_at))}</span>
          <span class="spacer" style="flex:1"></span>
          <button class="btn danger small" data-reject="${esc(r.id)}">Reject</button>
          <button class="btn ok small" data-approve="${esc(r.id)}">Approve</button>
        </div>
        <div class="compare">
          <div class="selfie"><div class="muted small">Selfie</div><img alt="Selfie" src="${esc(selfies[r.selfie_path] ?? '')}"></div>
          <div><div class="muted small">Profile photos</div>
            <div class="strip">${r.photos.map((p) => `<img alt="" src="${esc(photos[p] ?? '')}">`).join('')}</div></div>
        </div>
      </div>`).join('') : '<div class="card empty">No pending verifications.</div>'}`;

  view.querySelectorAll('[data-approve]').forEach((b) => b.addEventListener('click', async () => {
    try { await rpc('admin_review_verification', { p_request: b.dataset.approve, p_approve: true }); toast('Approved', { type: 'ok' }); rerender(); }
    catch (e) { toast(e.message, { type: 'error' }); }
  }));
  view.querySelectorAll('[data-reject]').forEach((b) => b.addEventListener('click', async () => {
    const reason = await ask({ title: 'Reject verification', input: true, danger: true, confirmLabel: 'Reject',
      placeholder: 'Reason shown to the user, e.g. "Face not clearly visible"' });
    if (reason === null) return;
    try { await rpc('admin_review_verification', { p_request: b.dataset.reject, p_approve: false, p_reason: reason || null }); toast('Rejected'); rerender(); }
    catch (e) { toast(e.message, { type: 'error' }); }
  }));
}
