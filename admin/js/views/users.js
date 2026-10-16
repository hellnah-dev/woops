import { removeFiles, rpc, signedUrls, thumbPath } from '../api.js';
import { ask, esc, flag, fmtDate, pill, timeAgo, toast } from '../ui.js';

export async function render(view, params, rerender) {
  if (params[0]) return renderUser(view, params[0], rerender);
  const q = sessionStorage.getItem('users-q') ?? '';
  const status = sessionStorage.getItem('users-status') ?? '';
  const rows = await rpc('admin_search_users', { p_query: q, p_status: status || null, p_limit: 100 });
  const photos = await signedUrls('profile-photos', rows.map((r) => r.photo && thumbPath(r.photo)).filter(Boolean)).catch(() => ({}));

  view.innerHTML = `
    <div class="page-head"><div><h1>Users</h1><p class="muted">Search by name, email or user id.</p></div></div>
    <form id="search" class="toolbar" style="margin-bottom:14px">
      <input id="q" placeholder="Search…" value="${esc(q)}" style="min-width:260px">
      <select id="st">${['', 'active', 'suspended', 'banned'].map((s) => `<option value="${s}" ${s === status ? 'selected' : ''}>${s || 'any status'}</option>`).join('')}</select>
      <button class="btn primary">Search</button>
    </form>
    <div class="card table-wrap">${rows.length ? `
      <table><thead><tr><th></th><th>Name</th><th>Email</th><th>Age</th><th>Country</th><th>Status</th><th>Reports</th><th>Joined</th><th>Active</th></tr></thead>
      <tbody>${rows.map((u) => `
        <tr class="clickable" data-id="${esc(u.id)}">
          <td><img class="thumb" alt="" src="${esc(photos[thumbPath(u.photo)] ?? '')}"></td>
          <td>${esc(u.display_name)} ${u.is_verified ? '✅' : ''}<div class="muted small">${u.username ? '@' + esc(u.username) : ''}</div></td>
          <td class="small">${esc(u.email)}</td>
          <td>${esc(u.age)}</td>
          <td>${flag(u.country_code)} ${esc(u.city ?? '')}</td>
          <td>${pill(u.status)}${u.onboarding_completed ? '' : ' <span class="muted small">onboarding</span>'}</td>
          <td>${u.reports_against > 0 ? `<strong style="color:var(--danger)">${esc(u.reports_against)}</strong>` : '0'}</td>
          <td class="small">${esc(fmtDate(u.created_at))}</td>
          <td class="small">${esc(timeAgo(u.last_active_at))}</td>
        </tr>`).join('')}</tbody></table>` : '<div class="empty">No users found.</div>'}
    </div>`;
  view.querySelector('#search').onsubmit = (e) => {
    e.preventDefault();
    sessionStorage.setItem('users-q', view.querySelector('#q').value.trim());
    sessionStorage.setItem('users-status', view.querySelector('#st').value);
    rerender();
  };
  view.querySelectorAll('tr[data-id]').forEach((tr) => tr.addEventListener('click', () => (location.hash = `#/users/${tr.dataset.id}`)));
}

async function renderUser(view, id, rerender) {
  const d = await rpc('admin_get_user', { p_user: id });
  if (!d) { view.innerHTML = '<div class="card empty">User not found (maybe deleted).</div>'; return; }
  const p = d.profile;
  const urls = await signedUrls('profile-photos', d.photos.map((ph) => ph.storage_path)).catch(() => ({}));
  const kv = (k, v) => `<dt>${esc(k)}</dt><dd>${v}</dd>`;

  view.innerHTML = `
    <div class="page-head">
      <div><a href="#/users" class="muted small">← Users</a>
        <h1>${esc(p.display_name)}, ${esc(p.age)} ${p.is_verified ? '✅' : ''} ${p.age_verified ? '🪪' : ''}</h1>
        <p class="muted">${p.username ? '@' + esc(p.username) + ' · ' : ''}${esc(p.email)} · ${pill(p.status)}</p></div>
      <span class="spacer"></span>
      <div class="toolbar">
        ${p.status !== 'active' ? '<button class="btn ok" data-status="active">Reactivate</button>' : ''}
        ${p.status !== 'suspended' ? '<button class="btn warn" data-status="suspended">Suspend</button>' : ''}
        ${p.status !== 'banned' ? '<button class="btn danger" data-status="banned">Ban</button>' : ''}
        <button class="btn" id="verify">${p.is_verified ? 'Remove verification' : 'Mark verified'}</button>
        ${p.age_verified ? '<button class="btn warn" id="reset-age">Reset age check</button>' : ''}
      </div>
    </div>
    <div class="grid two-col">
      <div class="card"><h2>Photos</h2>
        <div class="photo-grid">${d.photos.map((ph) => `
          <div class="photo-tile"><img alt="" data-zoom="Photo ${esc(ph.position + 1)}" src="${esc(urls[ph.storage_path] ?? '')}">
            <div class="meta">#${esc(ph.position + 1)}<button class="btn small danger" data-photo="${esc(ph.id)}">Remove</button></div></div>`).join('') ||
          '<p class="muted">No photos.</p>'}</div>
        <h2 style="margin-top:16px">Profile</h2>
        <dl class="kv">
          ${kv('Gender', esc(p.gender))}
          ${kv('Birthdate', esc(p.birthdate))}
          ${kv('Country / city', `${flag(p.country_code)} ${esc(p.country_code ?? '—')} ${esc(p.city ?? '')}`)}
          ${kv('Looking for', esc(p.intention))}
          ${kv('Job', esc(p.job_title ?? '—'))}
          ${kv('Bio', esc(p.bio || '—'))}
          ${kv('Interests', esc((d.interests ?? []).join(', ') || '—'))}
          ${kv('Prompts', (d.prompts ?? []).map((x) => `<div><strong>${esc(x.prompt)}</strong> ${esc(x.answer)}</div>`).join('') || '—')}
          ${kv('Joined', esc(fmtDate(p.created_at)))}
          ${kv('Last active', esc(fmtDate(p.last_active_at)))}
          ${kv('Last sign-in', esc(fmtDate(p.last_sign_in_at)))}
          ${kv('Onboarded', p.onboarding_completed ? 'yes' : 'no')}
          ${kv('User id', `<code>${esc(p.id)}</code>`)}
        </dl>
      </div>
      <div class="grid" style="align-content:start">
        ${readinessCard({ ...d.readiness, id_pending: (d.age_checks ?? []).some((v) => v.status === 'pending') }, p)}
        <div class="card"><h2>ID age checks</h2>
          ${(d.age_checks ?? []).map((v) => `<div style="margin-bottom:8px">${pill(v.status)} ${esc(v.document_type)}
            ${flag(v.country_code)} <span class="muted small">${esc(fmtDate(v.created_at))}</span>
            ${v.reject_reason ? `<div class="small">${esc(v.reject_reason)}</div>` : ''}</div>`).join('') ||
            '<p class="muted">No ID sent yet.</p>'}
          <p class="muted small">Documents are deleted after review; only the result is kept.</p></div>
        <div class="card"><h2>Activity</h2><dl class="kv">
          ${Object.entries(d.counts).map(([k, v]) => kv(k.replaceAll('_', ' '), esc(v))).join('')}
          ${kv('reports made', esc(d.reports_made))}</dl></div>
        <div class="card"><h2>Reports against (${esc(d.reports_against.length)})</h2>
          ${d.reports_against.map((r) => `<div style="margin-bottom:8px">${pill(r.reason)} ${pill(r.status)}
            <span class="muted small">${esc(fmtDate(r.created_at))}</span><div class="small">${esc(r.details ?? '')}</div></div>`).join('') || '<p class="muted">None.</p>'}</div>
        <div class="card"><h2>Admin history</h2>
          ${d.admin_actions.map((a) => `<div class="small"><strong>${esc(a.action)}</strong> · ${esc(fmtDate(a.created_at))}
            ${a.details?.reason ? `<span class="muted">(${esc(a.details.reason)})</span>` : ''}</div>`).join('') || '<p class="muted">None.</p>'}</div>
      </div>
    </div>`;

  view.querySelectorAll('[data-status]').forEach((b) => b.addEventListener('click', async () => {
    const status = b.dataset.status;
    const reason = await ask({ title: `${status === 'active' ? 'Reactivate' : status === 'banned' ? 'Ban' : 'Suspend'} ${p.display_name}?`,
      input: true, danger: status !== 'active', placeholder: 'Reason (saved in the audit log)', confirmLabel: 'Confirm' });
    if (reason === null) return;
    try { await rpc('admin_set_user_status', { p_user: id, p_status: status, p_reason: reason || null }); toast('Updated', { type: 'ok' }); rerender(); }
    catch (e) { toast(e.message, { type: 'error' }); }
  }));
  view.querySelector('#verify').onclick = async () => {
    const ok = await ask(p.is_verified
      ? { title: `Remove ${p.display_name}'s verified badge?`, danger: true, confirmLabel: 'Remove badge' }
      : { title: `Mark ${p.display_name} as verified?`, confirmLabel: 'Mark verified',
          message: 'Only do this after checking a selfie or other proof that the photos are really them.' });
    if (!ok) return;
    try { await rpc('admin_set_verified', { p_user: id, p_verified: !p.is_verified }); toast('Updated', { type: 'ok' }); rerender(); }
    catch (e) { toast(e.message, { type: 'error' }); }
  };
  view.querySelectorAll('[data-photo]').forEach((b) => b.addEventListener('click', () => removePhoto(b.dataset.photo, rerender)));
  const reset = view.querySelector('#reset-age');
  if (reset) reset.onclick = async () => {
    const reason = await ask({ title: `Reset ${p.display_name}'s age check?`, input: true, danger: true, confirmLabel: 'Reset',
      message: 'They will need to send an ID again before they can like or pass.', placeholder: 'Reason (saved in the audit log)' });
    if (reason === null) return;
    try { await rpc('admin_reset_age_check', { p_user: id, p_reason: reason || null }); toast('Age check reset', { type: 'ok' }); rerender(); }
    catch (e) { toast(e.message, { type: 'error' }); }
  };
}

// "Ready to date" checklist: the same rules the server enforces before swiping.
function readinessCard(r, p) {
  if (!r) return '';
  const row = (ok, label) => `<div class="small">${ok ? '✅' : '❌'} ${esc(label)}</div>`;
  return `<div class="card"><h2>Ready to match: ${r.ready ? 'yes' : 'no'}</h2>
    ${row(r.photos >= 2, `Photos: ${r.photos} (needs 2+)`)}
    ${row(r.has_bio, 'Bio written')}
    ${row(r.interests >= 3, `Interests: ${r.interests} (needs 3+)`)}
    ${row(p.age_verified || r.id_pending, p.age_verified ? 'Age confirmed by ID' : r.id_pending ? 'ID sent, waiting for review' : 'No ID sent')}
    <p class="muted small">Minimum age in ${esc(p.country_code ?? 'their country')}: ${esc(r.min_age)} · their age: ${esc(p.age)}</p></div>`;
}

export async function removePhoto(photoId, rerender) {
  const reason = await ask({ title: 'Remove this photo?', input: true, danger: true, confirmLabel: 'Remove', required: true,
    message: 'The reason is sent to the user so they know what to change.',
    placeholder: 'Reason shown to the user',
    choices: ['Nudity or sexual content', 'Not a photo of you', 'Face not visible', 'Contains contact details or ads',
      'Violence or hateful content', 'Photo of a child', 'Low quality or heavily filtered'] });
  if (reason === null) return;
  try {
    const path = await rpc('admin_delete_photo', { p_photo: photoId, p_reason: reason || null });
    await removeFiles('profile-photos', [path, thumbPath(path)]);
    toast('Photo removed', { type: 'ok' });
    rerender();
  } catch (e) { toast(e.message, { type: 'error' }); }
}
