import { removeFiles, rpc, signedUrls } from '../api.js';
import { ask, esc, flag, fmtDate, toast } from '../ui.js';

// ID-document age checks. The document is deleted from storage right after a
// decision, so only the result is kept.
export async function render(view, _params, rerender) {
  const rows = await rpc('admin_list_age_verifications', { p_status: 'pending' });
  const docs = await signedUrls('id-documents', rows.map((r) => r.document_path).filter(Boolean)).catch(() => ({}));
  const photos = await signedUrls('profile-photos', rows.map((r) => r.photo).filter(Boolean)).catch(() => ({}));

  view.innerHTML = `
    <div class="page-head"><div><h1>ID document review</h1>
      <p class="muted">Approve only if the document looks genuine, its photo matches the profile, and the date of birth
      matches the profile and meets the country's minimum age. Click a photo to see it full screen. The file is deleted after you decide, and automatically after 7 days.</p></div></div>
    ${rows.length ? rows.map((r) => `
      <div class="card" style="margin-bottom:14px">
        <div class="toolbar" style="margin-bottom:10px">
          <strong><a href="#/users/${esc(r.user_id)}">${esc(r.display_name)}</a></strong>
          <span>${flag(r.country_code)}</span>
          <span>${esc(r.document_type)}</span>
          <span class="muted small">Profile DOB ${esc(r.birthdate)} · age ${esc(r.age)} · minimum ${esc(r.min_age)}</span>
          ${r.age < r.min_age ? '<span class="badge" style="background:#d33">UNDER MINIMUM</span>' : ''}
          <span class="muted small">sent ${esc(fmtDate(r.created_at))}</span>
          <span class="spacer" style="flex:1"></span>
          <button class="btn danger small" data-reject="${esc(r.id)}">Reject</button>
          <button class="btn ok small" data-approve="${esc(r.id)}" data-name="${esc(r.display_name)}">Approve</button>
        </div>
        <div class="compare">
          <div class="selfie"><div class="muted small">ID document</div>
            ${r.document_path && docs[r.document_path]
              ? `<img alt="ID document" data-zoom="${esc(r.document_type)}: ${esc(r.display_name)}" src="${esc(docs[r.document_path])}">`
              : '<div class="missing-file">ID file no longer available. Reject and ask for a new one.</div>'}</div>
          <div><div class="muted small">Profile photo</div>
            <div class="strip">${r.photo ? `<img alt="" data-zoom="${esc(r.display_name)}" src="${esc(photos[r.photo] ?? '')}">` : ''}</div></div>
        </div>
      </div>`).join('') : '<div class="card empty">No pending age checks.</div>'}`;

  const decide = async (id, approve, reason) => {
    const path = await rpc('admin_review_age_verification', { p_request: id, p_approve: approve, p_reason: reason });
    if (path) await removeFiles('id-documents', [path]).catch((e) => toast(`Saved, but the ID could not be deleted now (${e.message}). It will be removed within 7 days.`, { type: 'warn' }));
  };

  view.querySelectorAll('[data-approve]').forEach((b) => b.addEventListener('click', async () => {
    const ok = await ask({ title: `Approve ${b.dataset.name}'s ID?`, confirmLabel: 'Yes, approve',
      message: 'Confirm the date of birth matches the profile and meets the minimum age for this country. They get a notification and the ID is deleted.' });
    if (!ok) return;
    try { await decide(b.dataset.approve, true, null); toast('Approved · ID deleted', { type: 'ok' }); rerender(); }
    catch (e) { toast(e.message, { type: 'error' }); }
  }));
  view.querySelectorAll('[data-reject]').forEach((b) => b.addEventListener('click', async () => {
    const reason = await ask({ title: 'Why isn’t it approved?', input: true, danger: true, confirmLabel: 'Reject', required: true,
      message: 'The reason is sent to the user. The ID is then deleted.', placeholder: 'Reason shown to the user',
      choices: ['Date of birth not readable', 'Photo is blurry or has glare', 'Corners of the document cut off',
        'Document not accepted in your country', 'Doesn’t match your profile', 'Under the minimum age', 'Document looks altered'] });
    if (reason === null) return;
    try { await decide(b.dataset.reject, false, reason); toast('Rejected · ID deleted'); rerender(); }
    catch (e) { toast(e.message, { type: 'error' }); }
  }));
}
