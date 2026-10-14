import { initClient, rpc } from './api.js';
import { enableDesktopAlerts, startRealtime } from './notify.js';
import { $, $$, esc, loading, showError } from './ui.js';
import * as ageRules from './views/ageRules.js';
import * as audit from './views/audit.js';
import * as dashboard from './views/dashboard.js';
import * as errors from './views/errors.js';
import * as photos from './views/photos.js';
import * as reports from './views/reports.js';
import * as users from './views/users.js';
import * as verifications from './views/verifications.js';

const routes = { dashboard, reports, verifications, users, photos, errors, 'age-rules': ageRules, audit };

let config;
try {
  config = await import('./config.js');
} catch {
  document.body.innerHTML = `<div class="login"><div class="card login-card"><h2>Setup needed</h2>
    <p>Copy <code>admin/js/config.example.js</code> to <code>admin/js/config.js</code> and add your Supabase URL and publishable key.</p></div></div>`;
  throw new Error('missing config.js');
}
const supabase = initClient(config.SUPABASE_URL, config.SUPABASE_PUBLISHABLE_KEY);

async function route() {
  const [name = 'dashboard', ...params] = location.hash.replace(/^#\/?/, '').split('/');
  const view = $('#view');
  const mod = routes[name] ?? dashboard;
  $$('#nav a').forEach((a) => a.classList.toggle('active', a.dataset.route === name));
  loading(view);
  try {
    await mod.render(view, params, route);
  } catch (e) {
    showError(view, e);
  }
}

async function showApp(session) {
  let isAdmin = false;
  try { isAdmin = await rpc('is_admin'); } catch { /* not allowed */ }
  if (!isAdmin) {
    await supabase.auth.signOut();
    showLogin('This account is not an admin.');
    return;
  }
  $('#login').classList.add('hidden');
  $('#app').classList.remove('hidden');
  $('#whoami').innerHTML = esc(session.user.email);
  startRealtime();
  window.addEventListener('hashchange', route);
  route();
}

function showLogin(message = '') {
  $('#app').classList.add('hidden');
  $('#login').classList.remove('hidden');
  $('#login-error').textContent = message;
}

$('#login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('#login-error').textContent = '';
  const { data, error } = await supabase.auth.signInWithPassword({
    email: $('#login-email').value.trim(),
    password: $('#login-password').value,
  });
  if (error) { $('#login-error').textContent = error.message; return; }
  showApp(data.session);
});
$('#logout').onclick = async () => { await supabase.auth.signOut(); location.reload(); };
$('#enable-notifications').onclick = enableDesktopAlerts;

const { data: { session } } = await supabase.auth.getSession();
if (session) showApp(session); else showLogin();
