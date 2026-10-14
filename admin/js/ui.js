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

/** Promise-based confirm/prompt dialog. Returns the text (prompt) or true, or null if cancelled. */
export function ask({ title, message = '', confirmLabel = 'Confirm', danger = false, input = false, placeholder = '' }) {
  return new Promise((resolve) => {
    const dialog = document.createElement('dialog');
    dialog.innerHTML = `
      <h2>${esc(title)}</h2>
      ${message ? `<p class="muted">${esc(message)}</p>` : ''}
      ${input ? `<textarea rows="3" style="width:100%" placeholder="${esc(placeholder)}"></textarea>` : ''}
      <div class="toolbar" style="justify-content:flex-end;margin-top:14px">
        <button class="btn" data-act="cancel">Cancel</button>
        <button class="btn ${danger ? 'danger' : 'primary'}" data-act="ok">${esc(confirmLabel)}</button>
      </div>`;
    document.body.append(dialog);
    const done = (value) => { dialog.close(); dialog.remove(); resolve(value); };
    dialog.querySelector('[data-act=cancel]').onclick = () => done(null);
    dialog.querySelector('[data-act=ok]').onclick = () =>
      done(input ? dialog.querySelector('textarea').value.trim() : true);
    dialog.addEventListener('cancel', () => done(null));
    dialog.showModal();
  });
}

export function loading(view, text = 'Loading…') {
  view.innerHTML = `<div class="empty">${esc(text)}</div>`;
}

export function showError(view, error) {
  view.innerHTML = `<div class="card error">Error: ${esc(error?.message ?? error)}</div>`;
}
