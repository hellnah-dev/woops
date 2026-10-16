// Small DOM helpers. Everything user-provided goes through esc() so profile
// text, report details or error messages can never inject HTML/JS.
export function esc(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#39;');
}

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

export function fmtDate(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
}

export function timeAgo(iso) {
  if (!iso) return '—';
  const s = Math.round((Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}

export function flag(code) {
  if (!code || !/^[A-Z]{2}$/.test(code)) return '🌍';
  return String.fromCodePoint(...[...code].map((c) => 0x1f1e6 + c.charCodeAt(0) - 65));
}

export const pill = (value) => `<span class="pill ${esc(value)}">${esc(value)}</span>`;

export function toast(message, { type = 'info', onClick, timeout = 6000 } = {}) {
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.textContent = message;
  if (onClick) el.addEventListener('click', () => { onClick(); el.remove(); });
  $('#toasts').append(el);
  setTimeout(() => el.remove(), timeout);
}

/**
 * Promise-based confirm/prompt dialog. Returns the text (prompt) or true, or
 * null if cancelled. With `required`, an empty text can't be submitted.
 * `choices` adds one-tap reasons that fill the text box.
 */
export function ask({ title, message = '', confirmLabel = 'Confirm', danger = false, input = false, placeholder = '',
  required = false, choices = [] }) {
  return new Promise((resolve) => {
    const dialog = document.createElement('dialog');
    dialog.innerHTML = `
      <h2>${esc(title)}</h2>
      ${message ? `<p class="muted">${esc(message)}</p>` : ''}
      ${choices.length ? `<div class="chips">${choices.map((c) => `<button type="button" class="chip">${esc(c)}</button>`).join('')}</div>` : ''}
      ${input ? `<textarea rows="3" style="width:100%" placeholder="${esc(placeholder)}"></textarea>` : ''}
      ${required ? '<p class="error small" data-err hidden>Please give a reason. It is shown to the user.</p>' : ''}
      <div class="toolbar" style="justify-content:flex-end;margin-top:14px">
        <button class="btn" data-act="cancel">Cancel</button>
        <button class="btn ${danger ? 'danger' : 'primary'}" data-act="ok">${esc(confirmLabel)}</button>
      </div>`;
    document.body.append(dialog);
    const text = dialog.querySelector('textarea');
    const done = (value) => { dialog.close(); dialog.remove(); resolve(value); };
    dialog.querySelectorAll('.chip').forEach((c) => c.addEventListener('click', () => {
      text.value = c.textContent; text.focus();
    }));
    dialog.querySelector('[data-act=cancel]').onclick = () => done(null);
    dialog.querySelector('[data-act=ok]').onclick = () => {
      if (!input) return done(true);
      const value = text.value.trim();
      if (required && !value) { dialog.querySelector('[data-err]').hidden = false; text.focus(); return; }
      done(value);
    };
    dialog.addEventListener('cancel', () => done(null));
    dialog.showModal();
  });
}

/**
 * Full-screen image viewer with a close button. Click the image to zoom,
 * Esc / ✕ / click outside to close. Works for every image marked `data-zoom`.
 */
export function openViewer(src, caption = '') {
  const el = document.createElement('div');
  el.className = 'viewer';
  el.setAttribute('role', 'dialog');
  el.setAttribute('aria-modal', 'true');
  el.innerHTML = `
    <button class="viewer-close" aria-label="Close">✕</button>
    <img alt="${esc(caption)}" src="${esc(src)}">
    ${caption ? `<div class="viewer-caption">${esc(caption)}</div>` : ''}`;
  const img = el.querySelector('img');
  const close = () => { el.remove(); document.removeEventListener('keydown', onKey); };
  const onKey = (e) => { if (e.key === 'Escape') close(); };
  el.querySelector('.viewer-close').onclick = close;
  el.addEventListener('click', (e) => { if (e.target === el) close(); });
  img.addEventListener('click', () => img.classList.toggle('zoomed'));
  document.addEventListener('keydown', onKey);
  document.body.append(el);
  el.querySelector('.viewer-close').focus();
}

// One listener for the whole panel: any <img data-zoom> opens full screen.
document.addEventListener('click', (e) => {
  const img = e.target.closest?.('img[data-zoom]');
  if (img && img.src && !img.closest('.viewer')) openViewer(img.dataset.full || img.src, img.dataset.zoom);
});

export function loading(view, text = 'Loading…') {
  view.innerHTML = `<div class="empty">${esc(text)}</div>`;
}

export function showError(view, error) {
  const msg = String(error?.message ?? error);
  // PostgREST: function/column/table not found → the database is behind the panel.
  const outdated = error?.code === 'PGRST202' || error?.code === '42883' || error?.code === '42703' ||
    /could not find the function|does not exist/i.test(msg);
  view.innerHTML = outdated
    ? `<div class="card error"><h2>Database update needed</h2>
        <p>This page needs a newer database than your Supabase project has. In Supabase → SQL Editor, run the
        migrations in <code>supabase/migrations/</code> you haven't applied yet (012 to 019: chats on phones,
        the map, ID document review, encrypted chat photos and these admin pages), then reload.</p>
        <p class="muted small">${esc(msg)}</p></div>`
    : `<div class="card error">Error: ${esc(msg)}</div>`;
}
