import { removeFiles, rpc, signedUrls } from '../api.js';
import { ask, esc, flag, fmtDate, toast } from '../ui.js';

const REJECT_REASONS = ['Face not clearly visible', 'Pose doesn’t match (✌️ next to your face)',
  'Doesn’t match the profile photos', 'Photo is blurry or too dark', 'Filters or sunglasses', 'Looks under 18'];

// Selfie verification. The selfie is deleted from storage right after a decision.
export async function render(view, _params, rerender) {
  const rows = await rpc('admin_list_verifications', { p_status: 'pending' });
  const selfies = await signedUrls('verification-selfies', rows.map((r) => r.selfie_path).filter(Boolean)).catch(() => ({}));
  const photos = await signedUrls('profile-photos', rows.flatMap((r) => r.photos)).catch(() => ({}));

  view.innerHTML = `
    <div class="page-head"><div><h1>Selfie checks</h1>
      <p class="muted">Approve only if the selfie clearly shows the same person as the profile photos, doing the ✌️ pose, and they look 18+.
      Click any photo to see it full screen. Selfies are deleted after you decide, and automatically after 7 days.</p></div></div>
    ${rows.length ? rows.map((r) => `
      <div class="card" style="margin-bottom:14px">
        <div class="toolbar" style="margin-bottom:10px">
          <strong><a href="#/users/${esc(r.user_id)}">${esc(r.display_name)}</a>, ${esc(r.age)}</strong>
          <span>${flag(r.country_code)}</span>
          <span class="muted small">requested ${esc(fmtDate(r.created_at))}</span>
          <span class="spacer" style="flex:1"></span>
          <button class="btn danger small" data-reject="${esc(r.id)}">Reject</button>
          <button class="btn ok small" data-approve="${esc(r.id)}" data-name="${esc(r.display_name)}">Approve</button>
        </div>
        <div class="compare">
          <div class="selfie"><div class="muted small">Selfie</div>
            ${r.selfie_path && selfies[r.selfie_path]
              ? `<img alt="Selfie" data-zoom="Selfie: ${esc(r.display_name)}" src="${esc(selfies[r.selfie_path])}">`
              : '<div class="missing-file">Selfie file no longer available. Reject and ask for a new one.</div>'}</div>
          <div><div class="muted small">Profile photos</div>
            <div class="strip">${r.photos.map((p, i) => `<img alt="" data-zoom="${esc(r.display_name)}: photo ${i + 1}" src="${esc(photos[p] ?? '')}">`).join('')}</div></div>
        </div>
      </div>`).join('') : '<div class="card empty">No pending verifications.</div>'}`;

  const decide = async (id, approve, reason) => {
    const path = await rpc('admin_review_verification', { p_request: id, p_approve: approve, p_reason: reason });
    if (path) {
      await removeFiles('verification-selfies', [path])
        .catch((e) => toast(`Saved, but the selfie could not be deleted now (${e.message}). It will be removed within 7 days.`, { type: 'warn' }));
    }
  };

  view.querySelectorAll('[data-approve]').forEach((b) => b.addEventListener('click', async () => {
    const ok = await ask({ title: `Approve ${b.dataset.name}?`, confirmLabel: 'Yes, approve',
      message: 'Only approve if the selfie clearly matches the profile photos. They get a blue verified badge and a notification. The selfie is then deleted.' });
    if (!ok) return;
    try { await decide(b.dataset.approve, true, null); toast('Approved · selfie deleted', { type: 'ok' }); rerender(); }
    catch (e) { toast(e.message, { type: 'error' }); }
  }));
  view.querySelectorAll('[data-reject]').forEach((b) => b.addEventListener('click', async () => {
    const reason = await ask({ title: 'Why isn’t it approved?', input: true, danger: true, confirmLabel: 'Reject', required: true,
      message: 'The reason is sent to the user. The selfie is then deleted.', choices: REJECT_REASONS,
      placeholder: 'Reason shown to the user' });
    if (reason === null) return;
    try { await decide(b.dataset.reject, false, reason); toast('Rejected · selfie deleted'); rerender(); }
    catch (e) { toast(e.message, { type: 'error' }); }
  }));
}
