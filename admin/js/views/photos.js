import { rpc, signedUrls, thumbPath } from '../api.js';
import { esc, pill, timeAgo } from '../ui.js';
import { removePhoto } from './users.js';

export async function render(view, _params, rerender) {
  const rows = await rpc('admin_recent_photos', { p_limit: 120 });
  const urls = await signedUrls('profile-photos', rows.map((r) => thumbPath(r.storage_path))).catch(() => ({}));
  const full = await signedUrls('profile-photos', rows.map((r) => r.storage_path)).catch(() => ({}));
  view.innerHTML = `
    <div class="page-head"><div><h1>Photo review</h1><p class="muted">Newest uploads first. Remove anything that breaks the Community Guidelines.</p></div></div>
    <div class="photo-grid">${rows.map((r) => `
      <div class="photo-tile">
        <img alt="" loading="lazy" data-zoom="${esc(r.display_name)}" src="${esc(urls[thumbPath(r.storage_path)] || full[r.storage_path] || '')}"
             data-full="${esc(full[r.storage_path] ?? '')}">
        <div class="meta"><a href="#/users/${esc(r.user_id)}" style="color:#fff">${esc(r.display_name)}</a>
          <span>${esc(timeAgo(r.created_at))}</span>
          <button class="btn small danger" data-photo="${esc(r.id)}">Remove</button></div>
        ${r.status !== 'active' ? `<div style="position:absolute;top:6px;left:6px">${pill(r.status)}</div>` : ''}
      </div>`).join('') || '<div class="card empty">No photos yet.</div>'}</div>`;
  // Older photos may have no thumbnail: fall back to the full image.
  view.querySelectorAll('img[data-full]').forEach((img) =>
    img.addEventListener('error', () => { if (img.src !== img.dataset.full) img.src = img.dataset.full; }, { once: true }));
  view.querySelectorAll('[data-photo]').forEach((b) => b.addEventListener('click', () => removePhoto(b.dataset.photo, rerender)));
}
