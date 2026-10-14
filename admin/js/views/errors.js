import { rpc } from '../api.js';
import { esc, fmtDate, toast } from '../ui.js';

export async function render(view, _params, rerender) {
  const showResolved = sessionStorage.getItem('errors-resolved') === '1';
  const rows = await rpc('admin_list_errors', { p_include_resolved: showResolved });
  view.innerHTML = `
    <div class="page-head"><div><h1>App errors</h1><p class="muted">Crashes and errors reported by the app, grouped by type.</p></div>
      <span class="spacer"></span>
      <label style="flex-direction:row;align-items:center;gap:6px"><input type="checkbox" id="resolved" ${showResolved ? 'checked' : ''}> Show resolved</label></div>
    ${rows.map((e) => `
      <div class="card" style="margin-bottom:12px">
        <div class="toolbar">
          <strong style="flex:1;word-break:break-word">${esc(e.message)}</strong>
          ${e.resolved ? '<span class="pill approved">resolved</span>' : `<button class="btn small ok" data-fp="${esc(e.fingerprint)}">Mark resolved</button>`}
        </div>
        <div class="muted small">${esc(e.occurrences)} times · ${esc(e.users)} users · ${esc(e.platform ?? '?')} · v${esc(e.app_version ?? '?')}
          · first ${esc(fmtDate(e.first_seen))} · last ${esc(fmtDate(e.last_seen))}</div>
        ${e.stack ? `<details><summary class="small">Stack trace</summary><pre class="stack">${esc(e.stack)}</pre></details>` : ''}
      </div>`).join('') || '<div class="card empty">No errors 🎉</div>'}`;
  view.querySelector('#resolved').onchange = (ev) => { sessionStorage.setItem('errors-resolved', ev.target.checked ? '1' : '0'); rerender(); };
  view.querySelectorAll('[data-fp]').forEach((b) => b.addEventListener('click', async () => {
    try { await rpc('admin_resolve_error', { p_fingerprint: b.dataset.fp }); toast('Marked resolved', { type: 'ok' }); rerender(); }
    catch (e) { toast(e.message, { type: 'error' }); }
  }));
}
