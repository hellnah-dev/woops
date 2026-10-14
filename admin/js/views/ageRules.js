import { rpc, supabase } from '../api.js';
import { ask, esc, flag, fmtDate, toast } from '../ui.js';

export async function render(view, _params, rerender) {
  const { data: rows, error } = await supabase().from('country_age_rules').select('*').order('country_code');
  if (error) throw error;
  view.innerHTML = `
    <div class="page-head"><div><h1>Age rules</h1>
      <p class="muted">Minimum age per country. Countries not listed use <strong>18</strong>. The minimum can never be set below 18.
      Confirm local law with legal counsel.</p></div></div>
    <form id="add" class="card toolbar" style="margin-bottom:14px">
      <input id="cc" placeholder="Country code (e.g. KR)" maxlength="2" required style="width:180px;text-transform:uppercase">
      <input id="age" type="number" min="18" max="25" value="19" required style="width:90px">
      <input id="note" placeholder="Note (optional)" style="flex:1;min-width:200px">
      <button class="btn primary">Save rule</button>
    </form>
    <div class="card table-wrap"><table><thead><tr><th>Country</th><th>Minimum age</th><th>Note</th><th>Updated</th><th></th></tr></thead>
      <tbody>${rows.map((r) => `<tr><td>${flag(r.country_code)} ${esc(r.country_code)}</td><td><strong>${esc(r.min_age)}</strong></td>
        <td>${esc(r.note ?? '')}</td><td class="small">${esc(fmtDate(r.updated_at))}</td>
        <td><button class="btn small" data-del="${esc(r.country_code)}">Remove</button></td></tr>`).join('')}</tbody></table></div>`;
  view.querySelector('#add').onsubmit = async (e) => {
    e.preventDefault();
    try {
      await rpc('admin_upsert_age_rule', {
        p_country: view.querySelector('#cc').value.trim().toUpperCase(),
        p_min_age: Number(view.querySelector('#age').value),
        p_note: view.querySelector('#note').value.trim() || null,
      });
      toast('Rule saved', { type: 'ok' });
      rerender();
    } catch (err) { toast(err.message, { type: 'error' }); }
  };
  view.querySelectorAll('[data-del]').forEach((b) => b.addEventListener('click', async () => {
    if (!(await ask({ title: `Remove rule for ${b.dataset.del}?`, message: 'The country will use the default minimum age of 18.', danger: true, confirmLabel: 'Remove' }))) return;
    try { await rpc('admin_delete_age_rule', { p_country: b.dataset.del }); rerender(); }
    catch (err) { toast(err.message, { type: 'error' }); }
  }));
}
