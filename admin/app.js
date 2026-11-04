/* VITRAX admin website.
 * Talks to Supabase with the public anon key only. What an account can
 * read or change is enforced by row-level security in supabase/018_admin.sql
 * (profiles.is_admin), never by this file. */
(() => {
  'use strict';

  const CFG = window.VITRAX_CONFIG;
  if (!CFG || !CFG.url || !CFG.anonKey || CFG.url.includes('YOUR_')) {
    document.body.innerHTML = '<p style="padding:24px;font-family:sans-serif;color:#fff">Missing <b>config.js</b>. Copy <b>config.example.js</b> to <b>config.js</b> and fill in your Supabase URL and anon key.</p>';
    return;
  }
  const sb = supabase.createClient(CFG.url, CFG.anonKey);
  const $ = (s, el = document) => el.querySelector(s);
  const PAGE_SIZE = 25;

  // ------------------------------------------------------------ helpers
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const safeUrl = (u) => (/^https?:\/\//i.test(u || '') ? u : '');
  const fmt = (iso) => (iso ? new Date(iso).toLocaleString('en-PH', { timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'short' }) : '—');
  const dayKey = (iso) => new Date(iso).toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' });
  const dur = (s) => { s = Math.round(s || 0); const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60); return h ? `${h}h ${m}m` : `${m}m ${s % 60}s`; };
  const short = (id) => String(id || '').slice(0, 8);
  const badge = (text, kind = '') => `<span class="badge ${kind}">${esc(text)}</span>`;

  let toastTimer;
  function toast(msg, isErr = false) {
    const t = $('#toast');
    t.textContent = msg; t.className = 'toast' + (isErr ? ' err' : ''); t.hidden = false;
    clearTimeout(toastTimer); toastTimer = setTimeout(() => (t.hidden = true), 3500);
  }
  // Styled confirmation dialog (replaces the browser's confirm/prompt boxes).
  // opts: { title, okText, danger, typed: 'DELETE' }  ->  Promise<boolean>
  function ask(message, opts = {}) {
    return new Promise((resolve) => {
      const wrap = document.createElement('div');
      wrap.className = 'modal dialog';
      wrap.innerHTML = `<div class="modal-card dialog-card" role="dialog" aria-modal="true">
          <div class="dialog-icon ${opts.danger ? 'danger' : ''}">${opts.danger ? '⚠️' : '❓'}</div>
          <h3>${esc(opts.title || 'Please confirm')}</h3>
          <p class="dialog-msg">${esc(message)}</p>
          ${opts.typed ? `<label>Type <b>${esc(opts.typed)}</b> to confirm<input id="dlg-typed" autocomplete="off" spellcheck="false"></label>` : ''}
          <div class="dialog-actions"><button class="btn ghost" data-r="0">Cancel</button>
            <button class="btn ${opts.danger ? 'danger' : 'primary'}" data-r="1" ${opts.typed ? 'disabled' : ''}>${esc(opts.okText || 'Confirm')}</button></div></div>`;
      document.body.appendChild(wrap);
      const ok = wrap.querySelector('[data-r="1"]'), input = wrap.querySelector('#dlg-typed');
      const done = (v) => { document.removeEventListener('keydown', onKey, true); wrap.remove(); resolve(v); };
      const onKey = (e) => {
        if (e.key === 'Escape') { e.stopPropagation(); done(false); }
        else if (e.key === 'Enter' && !ok.disabled) { e.preventDefault(); done(true); }
      };
      document.addEventListener('keydown', onKey, true);
      wrap.addEventListener('click', (e) => { if (e.target === wrap) done(false); const r = e.target.closest('[data-r]'); if (r && !r.disabled) done(r.dataset.r === '1'); });
      if (input) input.addEventListener('input', () => { ok.disabled = input.value.trim() !== opts.typed; });
      (input || ok).focus();
    });
  }
  const fail = (e, what) => { console.error(what, e); toast(`${what}: ${e?.message || e}`, true); };

  // ----------------------------------------------------- people lookup
  const people = new Map(); // id -> profile row
  async function loadPeople(ids) {
    const missing = [...new Set(ids.filter(Boolean))].filter((id) => !people.has(id));
    for (let i = 0; i < missing.length; i += 100) {
      const chunk = missing.slice(i, i + 100);
      const { data, error } = await sb.from('profiles').select('id, first_name, last_name, email, avatar_url, primary_activity, is_admin, is_suspended, warning_count').in('id', chunk);
      if (error) { fail(error, 'Loading names'); break; }
      (data || []).forEach((p) => people.set(p.id, p));
    }
  }
  const nameOf = (id) => { const p = people.get(id); const n = p ? `${p.first_name || ''} ${p.last_name || ''}`.trim() : ''; return n || (p?.email) || `User ${short(id)}`; };
  function avatar(p, fallback) {
    const url = safeUrl(p?.avatar_url);
    const initials = (fallback || '?').trim().split(/\s+/).map((w) => w[0]).slice(0, 2).join('').toUpperCase();
    return `<span class="avatar">${url ? `<img src="${esc(url)}" alt="" loading="lazy">` : esc(initials)}</span>`;
  }
  function who(id) {
    if (!id) return '<span class="muted">—</span>';
    const p = people.get(id);
    return `<a class="who" href="#" data-act="view-user" data-id="${esc(id)}">${avatar(p, nameOf(id))}<span>${esc(nameOf(id))}${p?.is_suspended ? ' ' + badge('suspended', 'red') : ''}</span></a>`;
  }

  // ----------------------------------------------- generic table + paging
  function table(cols, rows, emptyText = 'Nothing here yet.') {
    if (!rows.length) return `<div class="tablewrap"><div class="empty">${esc(emptyText)}</div></div>`;
    return `<div class="tablewrap"><table><thead><tr>${cols.map((c) => `<th>${c.ico || ''}${esc(c.h)}</th>`).join('')}</tr></thead><tbody>${
      rows.map((r) => `<tr>${cols.map((c) => `<td class="${c.cls || ''}">${c.f(r)}</td>`).join('')}</tr>`).join('')
    }</tbody></table></div>`;
  }
  function pager(total, page) {
    const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
    return `<div class="pager"><span>${total} total · page ${page + 1} of ${pages}</span>
      <button class="btn small-btn" data-act="page" data-dir="-1" aria-label="Previous page" ${page <= 0 ? 'disabled' : ''}>${I('<path d="m15 18-6-6 6-6"/>')}</button>
      <button class="btn small-btn" data-act="page" data-dir="1" aria-label="Next page" ${page + 1 >= pages ? 'disabled' : ''}>${I('<path d="m9 18 6-6-6-6"/>')}</button></div>`;
  }

  /** Server-side paged fetch; falls back to no ordering if the column does not exist. */
  async function fetchPage(tbl, { order, asc = false, page = 0, filter } = {}) {
    const run = async (useOrder) => {
      let q = sb.from(tbl).select('*', { count: 'exact' });
      if (filter) q = filter(q);
      if (useOrder && order) q = q.order(order, { ascending: asc });
      return q.range(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1);
    };
    let res = await run(true);
    if (res.error && order) res = await run(false);
    if (res.error) throw res.error;
    return { rows: res.data || [], count: res.count ?? (res.data || []).length };
  }

  // ------------------------------------------------------------ modal
  function openModal(html) { $('#modal-body').innerHTML = html; $('#modal').hidden = false; }
  function closeModal() { $('#modal').hidden = true; $('#modal-body').innerHTML = ''; }

  // ------------------------------------------------------------- state
  let me = null;           // signed-in admin profile
  let view = { name: 'dashboard', page: 0, filters: {} };
  let usersAll = [];       // merged auth + profile rows (Users page)

  const I = (d) => `<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  const ICONS = {
    dashboard: I('<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h14V9.5"/><path d="M10 21v-6h4v6"/>'),
    users: I('<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6"/><circle cx="17.5" cy="9" r="2.5"/><path d="M17 14.2c2.7.2 4.5 2.1 4.5 5.3"/>'),
    activities: I('<path d="M2 12h4l3-8 5 16 3-8h5"/>'),
    feed: I('<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/>'),
    comments: I('<path d="M21 12a8 8 0 0 1-11.6 7.1L3 21l1.9-5.4A8 8 0 1 1 21 12Z"/><path d="M8 11h.01M12 11h.01M16 11h.01"/>'),
    hazards: I('<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z"/><path d="M12 9v4M12 17h.01"/>'),
    challenges: I('<path d="M8 21h8M12 17v4"/><path d="M7 4h10v5a5 5 0 0 1-10 0V4Z"/><path d="M7 6H4v1a3 3 0 0 0 3 3M17 6h3v1a3 3 0 0 1-3 3"/>'),
    reports: I('<path d="M5 21V4"/><path d="M5 4h13l-2.5 4L18 12H5"/>'),
    flagged: I('<path d="M12 3 4 6v6c0 4.6 3.2 8 8 9 4.8-1 8-4.4 8-9V6l-8-3Z"/><path d="m9 12 2 2 4-4"/>'),
    audit: I('<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5Z"/><path d="M14 3v5h5M9 13h6M9 17h6"/>'),
    suspended: I('<circle cx="12" cy="12" r="9"/><path d="m5.6 5.6 12.8 12.8"/>'),
    shared: I('<circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="m8.2 10.8 7.6-3.6M8.2 13.2l7.6 3.6"/>'),
  };
  const PAGES = {
    dashboard: { title: 'Dashboard', icon: ICONS.dashboard },
    users: { title: 'Users', icon: ICONS.users },
    activities: { title: 'Activities', icon: ICONS.activities },
    feed: { title: 'Feed posts', icon: ICONS.feed },
    comments: { title: 'Comments', icon: ICONS.comments },
    hazards: { title: 'Hazards', icon: ICONS.hazards },
    challenges: { title: 'Challenges', icon: ICONS.challenges },
    reports: { title: 'Reports', icon: ICONS.reports },
    flagged: { title: 'Flagged users', icon: ICONS.flagged },
    prizes: { title: 'Prize disputes', icon: ICONS.challenges },
    audit: { title: 'Audit log', icon: ICONS.audit },
  };

  function renderNav() {
    $('#nav').innerHTML = Object.entries(PAGES).map(([k, p]) =>
      `<a href="#/${k}" class="${view.name === k ? 'active' : ''}">${p.icon}<span>${esc(p.title)}</span></a>`).join('');
  }

  async function go() {
    const name = (location.hash.replace(/^#\//, '') || 'dashboard').split('?')[0];
    view = { name: PAGES[name] ? name : 'dashboard', page: 0, filters: {} };
    await render();
  }
  async function render() {
    renderNav();
    $('#page-title').textContent = PAGES[view.name].title;
    $('#page-ico').innerHTML = PAGES[view.name].icon || ''; $('#page-sub').textContent = '';
    const page = $('#page');
    page.innerHTML = '<p class="muted">Loading…</p>';
    try { await renderers[view.name](page); } catch (e) { page.innerHTML = `<div class="error">Could not load this page: ${esc(e.message || e)}</div>`; console.error(e); }
  }

  // ====================================================== PAGE: dashboard
  async function renderDashboard(page) {
    const count = async (t, f) => {
      let q = sb.from(t).select('*', { count: 'exact', head: true });
      if (f) q = f(q);
      const { count: c, error } = await q;
      return error ? '—' : c;
    };
    const [users, acts, shared, posts, comments, hazards, challenges, reports, banned] = await Promise.all([
      count('profiles'), count('activities'), count('activities', (q) => q.eq('shared', true)), count('community_posts'),
      count('feed_comments'), count('hazards'), count('challenges'), count('chat_reports'), count('profiles', (q) => q.eq('is_suspended', true)),
    ]);
    const statIcon = { 'Users': ICONS.users, 'Suspended': ICONS.suspended, 'Activities': ICONS.activities, 'Shared activities': ICONS.shared, 'Feed posts': ICONS.feed, 'Comments': ICONS.comments, 'Hazard reports': ICONS.hazards, 'Challenges': ICONS.challenges, 'User reports': ICONS.reports };
    const stat = (label, v, href) => `<a class="stat" href="${href}"><span class="stat-ico">${statIcon[label] || ''}</span><span class="stat-txt"><span>${label}</span><b>${v}</b></span></a>`;

    // signups per day, last 14 days
    let bars = '<p class="muted">Sign-up chart unavailable (run 018_admin.sql).</p>';
    const { data: accounts, error: aerr } = await sb.rpc('admin_list_users');
    if (!aerr) {
      const days = [];
      for (let i = 13; i >= 0; i--) days.push(dayKey(new Date(Date.now() - i * 864e5).toISOString()));
      const per = Object.fromEntries(days.map((d) => [d, 0]));
      (accounts || []).forEach((a) => { const k = dayKey(a.created_at); if (k in per) per[k]++; });
      const max = Math.max(1, ...Object.values(per));
      bars = `<div class="bars">${days.map((d) => `<div class="bar" title="${d}: ${per[d]}"><u>${per[d] || ''}</u><i style="height:${(per[d] / max) * 100}%"></i><em>${d.slice(8)}</em></div>`).join('')}</div>`;
    }

    // latest reports
    let recent = '<p class="muted">No reports.</p>';
    try {
      const { rows } = await fetchPage('chat_reports', { order: 'created_at', page: 0 });
      await loadPeople(rows.flatMap((r) => [r.reporter_id, r.reported_user_id]));
      if (rows.length) recent = table([
        { h: 'Reported', f: (r) => who(r.reported_user_id) },
        { h: 'Reason', cls: 'wrap', f: (r) => esc(r.reason) },
      ], rows.slice(0, 5));
    } catch (_) { /* table optional */ }

    page.innerHTML = `
      <div class="cards">
        ${stat('Users', users, '#/users')}${stat('Suspended', banned, '#/users')}${stat('Activities', acts, '#/activities')}${stat('Shared activities', shared, '#/activities')}
        ${stat('Feed posts', posts, '#/feed')}${stat('Comments', comments, '#/comments')}${stat('Hazard reports', hazards, '#/hazards')}
        ${stat('Challenges', challenges, '#/challenges')}${stat('User reports', reports, '#/reports')}
      </div>
      <div class="row2">
        <div class="panel"><h2>New sign-ups · last 14 days</h2>${bars}</div>
        <div class="panel"><h2>Latest user reports</h2>${recent}</div>
      </div>`;
  }

  // ========================================================= PAGE: users
  async function loadUsers() {
    const [{ data: accounts, error: e1 }, { data: profs, error: e2 }] = await Promise.all([
      sb.rpc('admin_list_users'),
      sb.from('profiles').select('id, first_name, last_name, email, avatar_url, primary_activity, is_admin, is_suspended, warning_count').limit(5000),
    ]);
    if (e2) throw e2;
    const acc = new Map((accounts || []).map((a) => [a.id, a]));
    (profs || []).forEach((p) => people.set(p.id, p));
    usersAll = (profs || []).map((p) => ({ ...p, created_at: acc.get(p.id)?.created_at, last_sign_in_at: acc.get(p.id)?.last_sign_in_at, authEmail: acc.get(p.id)?.email }))
      .sort((a, b) => String(b.created_at || '').localeCompare(String(a.created_at || '')));
    if (e1) toast('Run 018_admin.sql to see sign-up dates (admin_list_users missing).', true);
  }
  function filteredUsers() {
    const q = (view.filters.q || '').toLowerCase(), f = view.filters.role || 'all';
    return usersAll.filter((u) => {
      const hay = `${u.first_name || ''} ${u.last_name || ''} ${u.email || ''} ${u.authEmail || ''}`.toLowerCase();
      if (q && !hay.includes(q)) return false;
      if (f === 'admin') return u.is_admin;
      if (f === 'suspended') return u.is_suspended;
      if (f === 'Cyclist' || f === 'Runner') return String(u.primary_activity || '').split(',').map((x) => x.trim()).includes(f);
      return true;
    });
  }
  function drawUsers() {
    const rows = filteredUsers();
    const slice = rows.slice(view.page * PAGE_SIZE, view.page * PAGE_SIZE + PAGE_SIZE);
    const self = (u) => u.id === me.id;
    $('#users-table').innerHTML = table([
      { h: 'User', f: (u) => `<a class="who" href="#" data-act="view-user" data-id="${esc(u.id)}">${avatar(u, nameOf(u.id))}<span>${esc(nameOf(u.id))}<br><span class="muted small">${esc(u.email || u.authEmail || '')}</span></span></a>` },
      { h: 'Type', f: (u) => esc(u.primary_activity || '—') },
      { h: 'Joined', f: (u) => fmt(u.created_at) },
      { h: 'Last sign-in', f: (u) => fmt(u.last_sign_in_at) },
      { h: 'Status', f: (u) => [u.is_admin ? badge('admin', 'blue') : '', u.is_suspended ? badge('suspended', 'red') : badge('active', 'green')].join(' ') },
      { h: '', cls: 'actions', f: (u) => self(u) ? '<span class="muted small">you</span>' : `
          <button class="btn small-btn ${u.is_suspended ? 'ok' : 'danger'}" data-act="toggle-suspend" data-id="${esc(u.id)}">${u.is_suspended ? 'Unsuspend' : 'Suspend'}</button>
          <button class="btn small-btn" data-act="toggle-admin" data-id="${esc(u.id)}">${u.is_admin ? 'Remove admin' : 'Make admin'}</button>
          <button class="btn small-btn danger" data-act="delete-user" data-id="${esc(u.id)}">Delete</button>` },
    ], slice, 'No users match.') + pager(rows.length, view.page);
  }
  async function renderUsers(page) {
    await loadUsers();
    page.innerHTML = `<div class="toolbar">
        <input id="u-q" type="search" placeholder="Search name or email…" value="${esc(view.filters.q || '')}">
        <select id="u-role"><option value="all">All users</option><option value="admin">Admins</option><option value="suspended">Suspended</option><option>Cyclist</option><option>Runner</option></select>
      </div><div id="users-table"></div>`;
    $('#u-role').value = view.filters.role || 'all';
    $('#u-q').oninput = (e) => { view.filters.q = e.target.value; view.page = 0; drawUsers(); };
    $('#u-role').onchange = (e) => { view.filters.role = e.target.value; view.page = 0; drawUsers(); };
    drawUsers();
  }

  async function showUser(id) {
    await loadPeople([id]);
    const p = people.get(id);
    if (!p) return toast('User not found', true);
    const head = async (t) => { const { count } = await sb.from(t).select('*', { count: 'exact', head: true }).eq('user_id', id); return count ?? '—'; };
    const [acts, posts, comments, haz] = await Promise.all([head('activities'), head('community_posts'), head('feed_comments'), head('hazards')]);
    const { count: reportsAgainst } = await sb.from('chat_reports').select('*', { count: 'exact', head: true }).eq('reported_user_id', id);
    const { data: bdg } = await sb.from('user_badges').select('badge_key, tier').eq('user_id', id);
    const BN = { first_steps: 'First Steps', distance: 'Distance Club', challenger: 'Challenger', streak: 'On a Roll', route_pioneer: 'Route Pioneer', safety_warden: 'Safety Warden', early_bird: 'Early Bird', endurance: 'Endurance', hazard_spotter: 'Hazard Spotter', trail_sharer: 'Trail Sharer', community_voice: 'Community Voice', route_likes: 'Crowd Favorite' };
    const order = ['bronze', 'silver', 'gold', 'platinum', 'diamond', 'elite'], top = {};
    (bdg || []).forEach((b) => { if (!top[b.badge_key] || order.indexOf(b.tier) > order.indexOf(top[b.badge_key])) top[b.badge_key] = b.tier; });
    const badgeHtml = Object.entries(top).map(([k, t]) => badge(`${BN[k] || k} · ${t}`, t === 'elite' ? 'red' : (t === 'diamond' || t === 'platinum' || t === 'gold') ? 'amber' : 'blue')).join(' ') || '<span class="muted">None yet</span>';
    const { data: last } = await sb.from('activities').select('type, distance_km, duration_seconds, started_at, shared').eq('user_id', id).order('started_at', { ascending: false }).limit(5);
    openModal(`
      <div class="who" style="gap:14px">${avatar(p, nameOf(id))}<div><h2 style="margin:0">${esc(nameOf(id))}</h2><span class="muted">${esc(p.email || '')}</span></div></div>
      <dl class="kv">
        <dt>User ID</dt><dd><code>${esc(id)}</code></dd>
        <dt>Primary activity</dt><dd>${esc(p.primary_activity || '—')}</dd>
        <dt>Status</dt><dd>${p.is_admin ? badge('admin', 'blue') + ' ' : ''}${p.is_suspended ? badge('suspended', 'red') : badge('active', 'green')}</dd>
        <dt>Activities</dt><dd>${acts}</dd><dt>Feed posts</dt><dd>${posts}</dd><dt>Comments</dt><dd>${comments}</dd><dt>Hazard reports</dt><dd>${haz}</dd>
        <dt>Badges</dt><dd>${badgeHtml}</dd><dt>Reports against</dt><dd>${reportsAgainst ?? 0}</dd><dt>Warnings</dt><dd>${people.get(id)?.warning_count || 0}</dd>
      </dl>
      <h3>Latest activities</h3>
      ${table([
        { h: 'Type', f: (a) => esc(a.type) }, { h: 'Distance', f: (a) => `${Number(a.distance_km).toFixed(2)} km` },
        { h: 'Time', f: (a) => dur(a.duration_seconds) }, { h: 'Started', f: (a) => fmt(a.started_at) }, { h: 'Shared', f: (a) => (a.shared ? 'Yes' : 'No') },
      ], last || [], 'No activities yet.')}`);
  }

  // ===================================================== PAGE: activities
  async function renderActivities(page) {
    page.innerHTML = `<div class="toolbar"><select id="a-f"><option value="all">All activities</option><option value="shared">Shared to feed</option><option value="private">Private</option></select></div><div id="list"></div>`;
    $('#a-f').value = view.filters.s || 'all';
    $('#a-f').onchange = (e) => { view.filters.s = e.target.value; view.page = 0; drawActivities(); };
    await drawActivities();
  }
  async function drawActivities() {
    const s = view.filters.s || 'all';
    const { rows, count } = await fetchPage('activities', { order: 'started_at', page: view.page, filter: (q) => (s === 'shared' ? q.eq('shared', true) : s === 'private' ? q.eq('shared', false) : q) });
    await loadPeople(rows.map((r) => r.user_id));
    $('#list').innerHTML = table([
      { h: 'User', f: (r) => who(r.user_id) }, { h: 'Type', f: (r) => esc([r.type, r.subtype].filter(Boolean).join(' · ')) },
      { h: 'Distance', f: (r) => `${Number(r.distance_km).toFixed(2)} km` }, { h: 'Time', f: (r) => dur(r.duration_seconds) },
      { h: 'Started', f: (r) => fmt(r.started_at) }, { h: 'Location', f: (r) => esc(r.location || '—') },
      { h: 'Shared', f: (r) => (r.shared ? badge('shared', 'blue') : badge('private')) },
      { h: 'Caption', cls: 'wrap', f: (r) => esc(r.caption || '') },
      { h: '', cls: 'actions', f: (r) => `<button class="btn small-btn danger" data-act="delete-row" data-table="activities" data-id="${esc(r.id)}">Delete</button>` },
    ], rows, 'No activities.') + pager(count, view.page);
  }

  // ========================================================== PAGE: feed
  async function renderFeed(page) { page.innerHTML = '<div id="list"></div>'; await drawFeed(); }
  async function drawFeed() {
    const { rows, count } = await fetchPage('community_posts', { order: 'created_at', page: view.page });
    await loadPeople(rows.flatMap((r) => [r.user_id, r.original_user_id]));
    $('#list').innerHTML = table([
      { h: 'Media', f: (r) => { const u = safeUrl(r.media_url); if (!u) return '<span class="muted">—</span>'; return r.media_type === 'video' ? `<a href="${esc(u)}" target="_blank" rel="noopener">${badge('video', 'blue')}</a>` : `<a href="${esc(u)}" target="_blank" rel="noopener"><img class="thumb" src="${esc(u)}" alt="" loading="lazy"></a>`; } },
      { h: 'Posted by', f: (r) => who(r.user_id) },
      { h: 'Caption', cls: 'wrap', f: (r) => esc(r.caption || '') + (r.original_user_id ? `<div class="muted small">Reshare of ${esc(nameOf(r.original_user_id))}${r.original_caption ? ': “' + esc(r.original_caption) + '”' : ''}</div>` : '') },
      { h: 'Posted', f: (r) => fmt(r.created_at) },
      { h: '', cls: 'actions', f: (r) => `<button class="btn small-btn danger" data-act="delete-row" data-table="community_posts" data-id="${esc(r.id)}">Delete</button>` },
    ], rows, 'No posts yet.') + pager(count, view.page);
  }

  // ======================================================= PAGE: comments
  async function renderComments(page) { page.innerHTML = '<div id="list"></div>'; await drawComments(); }
  async function drawComments() {
    const { rows, count } = await fetchPage('feed_comments', { order: 'created_at', page: view.page });
    await loadPeople(rows.map((r) => r.user_id));
    $('#list').innerHTML = table([
      { h: 'User', f: (r) => who(r.user_id) }, { h: 'Comment', cls: 'wrap', f: (r) => esc(r.body) },
      { h: 'On', f: (r) => `${esc(r.post_kind === 'activity' ? 'activity' : 'post')} <span class="muted small">${esc(short(r.post_id))}</span>${r.parent_id ? ' ' + badge('reply') : ''}` },
      { h: 'Posted', f: (r) => fmt(r.created_at) },
      { h: '', cls: 'actions', f: (r) => `<button class="btn small-btn danger" data-act="delete-row" data-table="feed_comments" data-id="${esc(r.id)}">Delete</button>` },
    ], rows, 'No comments yet.') + pager(count, view.page);
  }

  // ======================================================== PAGE: hazards
  let map, mapLayer;
  async function renderHazards(page) {
    const { data, error } = await sb.from('hazards').select('*').order('reported_at', { ascending: false }).limit(500);
    if (error) throw error;
    const rows = data || [];
    await loadPeople(rows.map((r) => r.user_id));
    const tally = async (tbl) => {
      const m = new Map();
      const { data: d } = await sb.from(tbl).select('hazard_id').limit(5000);
      (d || []).forEach((x) => m.set(x.hazard_id, (m.get(x.hazard_id) || 0) + 1));
      return m;
    };
    const [verif, clears, photos] = await Promise.all([tally('hazard_verifications'), tally('hazard_clear_confirmations'), tally('hazard_photos')]);
    const types = [...new Set(rows.map((r) => r.type))].sort();
    page.innerHTML = `<div class="toolbar"><select id="h-t"><option value="">All types (${rows.length})</option>${types.map((t) => `<option>${esc(t)}</option>`).join('')}</select>
        <button class="btn small-btn" data-act="expire-stale">Hide stale hazards (unverified &gt; 72h)</button>
        <span class="muted small">Latest 500. Red = visible to the community, amber = hidden/private.</span></div>
      <div id="map"></div><div id="list"></div>`;
    const draw = () => {
      const t = $('#h-t').value, list = rows.filter((r) => !t || r.type === t);
      if (map) { map.remove(); map = null; }
      map = L.map('map').setView([9.65, 123.85], 10);
      L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { attribution: '© OpenStreetMap contributors', maxZoom: 19 }).addTo(map);
      mapLayer = L.layerGroup().addTo(map);
      const pts = [];
      list.forEach((r) => {
        if (typeof r.lat !== 'number' || typeof r.lng !== 'number') return;
        pts.push([r.lat, r.lng]);
        L.circleMarker([r.lat, r.lng], { radius: 7, color: '#fff', weight: 1.5, fillColor: r.shared ? '#ef4444' : '#f5a524', fillOpacity: .9 })
          .bindPopup(`<b>${esc(r.type)}</b><br>${esc(nameOf(r.user_id))}<br>${esc(fmt(r.reported_at))}`).addTo(mapLayer);
      });
      if (pts.length) map.fitBounds(pts, { padding: [30, 30], maxZoom: 15 });
      $('#list').innerHTML = table([
        { h: 'Type', f: (r) => badge(r.type, 'amber') }, { h: 'Reported by', f: (r) => who(r.user_id) },
        { h: 'Location', f: (r) => `<a href="https://www.openstreetmap.org/?mlat=${r.lat}&mlon=${r.lng}#map=17/${r.lat}/${r.lng}" target="_blank" rel="noopener">${Number(r.lat).toFixed(5)}, ${Number(r.lng).toFixed(5)}</a>` },
        { h: 'Reported', f: (r) => fmt(r.reported_at) },
        { h: 'Confirmed', f: (r) => `${verif.get(r.id) || 0} verified · ${clears.get(r.id) || 0} clear votes` },
        { h: 'Status', f: (r) => (r.status === 'expired' ? badge('expired', 'amber') : r.shared ? badge('visible', 'blue') : badge('hidden')) },
        { h: 'Photos', f: (r) => (photos.get(r.id) ? `<button class="btn small-btn" data-act="hazard-photos" data-id="${esc(r.id)}">View ${photos.get(r.id)}</button>` : '—') },
        { h: '', cls: 'actions', f: (r) => `<button class="btn small-btn" data-act="${r.shared ? 'hide-hazard' : 'show-hazard'}" data-id="${esc(r.id)}">${r.shared ? 'Hide' : 'Restore'}</button>
          <button class="btn small-btn danger" data-act="delete-row" data-table="hazards" data-id="${esc(r.id)}">Delete</button>` },
      ], list, 'No hazard reports.');
    };
    $('#h-t').onchange = draw; draw();
  }

  // ===================================================== PAGE: challenges
  async function renderChallenges(page) {
    page.innerHTML = '<div class="toolbar"><button class="btn primary" data-act="new-challenge">+ New challenge</button><span class="muted small">Official challenges are announced to every user. Prizes are paid by the organizer (you) by GCash.</span></div><div id="list"></div>';
    await drawChallenges();
  }
  async function drawChallenges() {
    const { rows, count } = await fetchPage('challenges', { order: 'start_date', page: view.page });
    await loadPeople(rows.map((r) => r.creator_id));
    const ids = rows.map((r) => r.id), counts = {};
    if (ids.length) {
      const { data } = await sb.from('challenge_participants').select('challenge_id').in('challenge_id', ids);
      (data || []).forEach((p) => (counts[p.challenge_id] = (counts[p.challenge_id] || 0) + 1));
    }
    const now = Date.now();
    const day = (iso) => (iso ? new Date(iso).toLocaleDateString('en-PH', { timeZone: 'Asia/Manila', month: 'short', day: 'numeric' }) : '—');
    const status = (c) => (now < new Date(c.start_date) ? badge('upcoming', 'amber') : now > new Date(c.end_date) ? badge('ended') : badge('active', 'green'));
    $('#list').innerHTML = table([
      { h: 'Challenge', cls: 'wrap', f: (c) => `<b>${esc(c.title)}</b> ${c.is_official ? badge('official', 'blue') : ''}<div class="muted small">${esc(c.description || '')}</div>` },
      { h: 'Creator', f: (c) => who(c.creator_id) }, { h: 'Type', f: (c) => esc(c.type) },
      { h: 'Target', f: (c) => esc(c.type === 'route' ? 'route' : c.target_value) },
      { h: 'Dates', f: (c) => `${day(c.start_date)} → ${day(c.end_date)}` },
      { h: 'Prize', f: (c) => (c.prize_amount ? `₱${Number(c.prize_amount).toLocaleString()}` : '—') },
      { h: 'Joined', f: (c) => counts[c.id] || 0 }, { h: 'Status', f: status },
      { h: '', cls: 'actions', f: (c) => `<button class="btn small-btn" data-act="participants" data-id="${esc(c.id)}">Participants</button>
          <button class="btn small-btn danger" data-act="delete-row" data-table="challenges" data-id="${esc(c.id)}">Delete</button>` },
    ], rows, 'No challenges.') + pager(count, view.page);
  }
  async function showParticipants(id) {
    const [{ data: parts, error }, { data: pays }, { data: ch }] = await Promise.all([
      sb.from('challenge_participants').select('*').eq('challenge_id', id),
      sb.from('challenge_prize_payments').select('*').eq('challenge_id', id),
      sb.from('challenges').select('title, prize_amount').eq('id', id).maybeSingle(),
    ]);
    if (error) return fail(error, 'Loading participants');
    await loadPeople((parts || []).map((p) => p.user_id));
    const paid = new Set((pays || []).map((p) => p.winner_user_id));
    const prize = ch?.prize_amount > 0;
    openModal(`<h2 style="margin-top:0">${esc(ch?.title || 'Challenge')}</h2>
      <p class="muted">${(parts || []).length} participant(s)${prize ? ` · prize ₱${Number(ch.prize_amount).toLocaleString()}` : ''}. The winner is decided in the app from shared activities. The challenge creator sends the prize by GCash and marks it paid in the app. Use “Mark paid” here only as an admin override, after you have verified the payment.</p>
      ${table([
        { h: 'Participant', f: (p) => who(p.user_id) },
        { h: 'Finished', f: (p) => (p.completed_at ? fmt(p.completed_at) : '—') },
        { h: 'Best time', f: (p) => (p.duration_seconds ? dur(p.duration_seconds) : '—') },
        ...(prize ? [{ h: 'Prize', cls: 'actions', f: (p) => (paid.has(p.user_id) ? badge('paid', 'green') : `<button class="btn small-btn ok" data-act="mark-paid" data-id="${esc(id)}" data-user="${esc(p.user_id)}">Mark paid</button>`) }] : []),
      ], parts || [], 'Nobody has joined.')}`);
  }

  // ======================================================= PAGE: reports
  async function renderReports(page) { page.innerHTML = '<div id="list"></div>'; await drawReports(); }
  async function drawReports() {
    const { rows, count } = await fetchPage('chat_reports', { order: 'created_at', page: view.page });
    await loadPeople(rows.flatMap((r) => [r.reporter_id, r.reported_user_id]));
    $('#list').innerHTML = table([
      { h: 'Reported user', f: (r) => who(r.reported_user_id) }, { h: 'Reason', cls: 'wrap', f: (r) => esc(r.reason) },
      { h: 'Reported by', f: (r) => who(r.reporter_id) }, { h: 'Date', f: (r) => fmt(r.created_at) },
      { h: 'From', f: (r) => (r.conversation_id ? badge('chat', 'blue') : badge('feed')) },
      { h: '', cls: 'actions', f: (r) => `
          <button class="btn small-btn danger" data-act="toggle-suspend" data-id="${esc(r.reported_user_id)}">${people.get(r.reported_user_id)?.is_suspended ? 'Unsuspend' : 'Suspend'} user</button>
          <button class="btn small-btn" data-act="delete-row" data-table="chat_reports" data-id="${esc(r.id)}" data-label="Dismiss this report?">Dismiss</button>` },
    ], rows, 'No reports. 🎉') + pager(count, view.page);
  }

  // ================================================== PAGE: flagged users
  async function renderFlagged(page) {
    const { data, error } = await sb.rpc('admin_flagged_users');
    if (error) throw error;
    const rows = data || [];
    await loadPeople(rows.map((r) => r.user_id));
    page.innerHTML = `<p class="muted small">Auto-flagged: 3+ user reports, 15+ hazards in 7 days, or 2+ hazards you removed. Warn first; suspend if it continues.</p><div id="list"></div>`;
    $('#list').innerHTML = table([
      { h: 'User', f: (r) => who(r.user_id) },
      { h: 'Why flagged', cls: 'wrap', f: (r) => esc(r.reasons) },
      { h: 'Reports', f: (r) => r.reports_against }, { h: 'Hazards 7d', f: (r) => r.hazards_7d }, { h: 'Hazards removed', f: (r) => r.hazards_removed },
      { h: 'Warnings', f: (r) => people.get(r.user_id)?.warning_count || 0 },
      { h: '', cls: 'actions', f: (r) => `<button class="btn small-btn" data-act="warn-user" data-id="${esc(r.user_id)}">Warn</button>
          <button class="btn small-btn danger" data-act="toggle-suspend" data-id="${esc(r.user_id)}">${people.get(r.user_id)?.is_suspended ? 'Unsuspend' : 'Suspend'}</button>` },
    ], rows, 'No flagged users. 🎉');
  }

  // ================================================ PAGE: prize disputes
  async function renderPrizes(page) {
    page.innerHTML = `<p class="muted small">A winner pressed “Not received” after the creator marked the prize as paid. Check the receipt, then rule: <b>Not paid</b> removes the paid mark so the creator must send it again (and blocks new prize challenges until then); <b>Was paid</b> closes the case as paid.</p><div id="list"></div>`;
    await drawPrizes();
  }
  async function drawPrizes() {
    const { rows, count } = await fetchPage('prize_disputes', { order: 'created_at', page: view.page });
    await loadPeople(rows.flatMap((r) => [r.winner_user_id, r.creator_id]));
    const ids = [...new Set(rows.map((r) => r.challenge_id))], titles = {};
    if (ids.length) {
      const { data } = await sb.from('challenges').select('id, title, prize_amount').in('id', ids);
      (data || []).forEach((c) => (titles[c.id] = c));
    }
    const st = (r) => (r.status === 'open' ? badge('open', 'amber') : r.status === 'upheld' ? badge('not paid', 'red') : badge('was paid', 'green'));
    $('#list').innerHTML = table([
      { h: 'Challenge', cls: 'wrap', f: (r) => `<b>${esc(titles[r.challenge_id]?.title || '—')}</b><div class="muted small">${titles[r.challenge_id]?.prize_amount ? '₱' + Number(titles[r.challenge_id].prize_amount).toLocaleString() : ''}</div>` },
      { h: 'Winner', f: (r) => who(r.winner_user_id) }, { h: 'Creator', f: (r) => who(r.creator_id) },
      { h: 'Winner’s note', cls: 'wrap', f: (r) => esc(r.note || '—') },
      { h: 'Date', f: (r) => fmt(r.created_at) }, { h: 'Status', f: st },
      { h: '', cls: 'actions', f: (r) => `<button class="btn small-btn" data-act="view-proof" data-id="${esc(r.challenge_id)}" data-user="${esc(r.winner_user_id)}">Receipt</button>` +
          (r.status === 'open' ? ` <button class="btn small-btn danger" data-act="dispute-upheld" data-id="${esc(r.id)}">Not paid</button>
          <button class="btn small-btn ok" data-act="dispute-rejected" data-id="${esc(r.id)}">Was paid</button>` : '') },
    ], rows, 'No prize disputes. 🎉') + pager(count, view.page);
  }

  // ===================================================== PAGE: audit log
  const ago = (iso) => { if (!iso) return ''; const s = Math.max(0, (Date.now() - new Date(iso)) / 1000); if (s < 60) return 'just now'; const u = [[60, 'minute'], [3600, 'hour'], [86400, 'day'], [2592000, 'month'], [31536000, 'year']]; let k = 0; while (k + 1 < u.length && s >= u[k + 1][0]) k++; const n = Math.floor(s / u[k][0]); return `${n} ${u[k][1]}${n > 1 ? 's' : ''} ago`; };
  const TARGET_LABEL = { 'auth.users': 'User ID', profiles: 'User ID', activities: 'Activity ID', community_posts: 'Post ID', comments: 'Comment ID', hazards: 'Hazard ID', challenges: 'Challenge ID', reports: 'Report ID' };
  async function renderAudit(page) {
    $('#page-sub').textContent = 'Every admin action is recorded here and cannot be edited or deleted from the website.';
    page.innerHTML = '<div id="list"></div>'; await drawAudit();
  }
  async function drawAudit() {
    const { rows, count } = await fetchPage('admin_audit_log', { order: 'created_at', page: view.page });
    await loadPeople(rows.map((r) => r.admin_id));
    const ic = (d) => I(d);
    $('#list').innerHTML = table([
      { h: 'When', ico: ic('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'), cls: 'au-when', f: (r) => `<span class="au-ico">${ic('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>')}</span><div><div class="au-main">${esc(fmt(r.created_at))}</div><div class="au-sub">${esc(ago(r.created_at))}</div></div>` },
      { h: 'Admin', ico: ic('<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>'), cls: 'au-admin', f: (r) => { const em = r.admin_email || short(r.admin_id); return `${avatar(people.get(r.admin_id), r.admin_id ? nameOf(r.admin_id) : em)}<div><div class="au-main">${esc(em)}</div><div class="au-sub">Admin</div></div>`; } },
      { h: 'Action', ico: ic('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z"/>'),
        f: (r) => { const bad = /delete|suspend|revoke/.test(r.action || ''); const a = String(r.action || '').replace(/_/g, ' '); return `<span class="au-pill ${bad ? 'red' : 'blue'}">${bad ? ic('<path d="M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14"/>') : ''}${esc(a)}</span>`; } },
      { h: 'Target', ico: ic('<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>'), cls: 'wrap', f: (r) => `<div class="au-main">${esc(r.target_table || '—')}${r.target_id ? ' &bull; ' + esc(short(r.target_id)) : ''}</div><div class="au-sub">${esc(TARGET_LABEL[r.target_table] || 'ID')}</div>` },
      { h: 'Details', ico: ic('<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5Z"/><path d="M14 3v5h5M9 13h6M9 17h6"/>'), cls: 'wrap', f: (r) => { const t = JSON.stringify(r.details || {}); return `<div class="au-details"><code>${esc(t.length > 160 ? t.slice(0, 160) + '…' : t)}</code><button class="au-copy" data-act="copy" data-text="${esc(t)}" aria-label="Copy details">${ic('<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/>')}</button></div>`; } },
    ], rows, 'No admin actions yet.') + pager(count, view.page);
  }

  const renderers = {
    dashboard: renderDashboard, users: renderUsers, activities: renderActivities, feed: renderFeed,
    comments: renderComments, hazards: renderHazards, challenges: renderChallenges, reports: renderReports, flagged: renderFlagged, prizes: renderPrizes, audit: renderAudit,
  };

  // ------------------------------------------------------------ actions
  async function setProfileFlag(id, patch, okMsg) {
    const { error } = await sb.from('profiles').update(patch).eq('id', id);
    if (error) return fail(error, 'Update failed');
    people.set(id, { ...(people.get(id) || { id }), ...patch });
    const u = usersAll.find((x) => x.id === id); if (u) Object.assign(u, patch);
    toast(okMsg);
    if (view.name === 'users') drawUsers(); else await render();
  }

  const actions = {
    'view-user': (id) => showUser(id),
    copy: async (_, el) => { try { await navigator.clipboard.writeText(el.dataset.text || ''); toast('Copied.'); } catch (e) { toast('Could not copy.', true); } },
    page: async (_, btn) => { view.page += Number(btn.dataset.dir); if (view.name === 'users') drawUsers(); else await refreshList(); },
    'toggle-suspend': async (id) => {
      await loadPeople([id]);
      const p = people.get(id), next = !p?.is_suspended;
      if (id === me.id) return toast('You cannot suspend yourself.', true);
      if (next && !(await ask(`${nameOf(id)} will be signed out of the app and unable to sign in until you unsuspend them.`, { title: 'Suspend this user?', okText: 'Suspend', danger: true }))) return;
      await setProfileFlag(id, { is_suspended: next }, next ? 'User suspended.' : 'User unsuspended.');
    },
    'toggle-admin': async (id) => {
      await loadPeople([id]);
      const next = !people.get(id)?.is_admin;
      if (!(await ask(next ? `${nameOf(id)} will be able to see and manage everything on this site.` : `${nameOf(id)} will no longer be able to use this site.`, { title: next ? 'Give admin access?' : 'Remove admin access?', okText: next ? 'Make admin' : 'Remove admin', danger: !next }))) return;
      await setProfileFlag(id, { is_admin: next }, next ? 'Admin rights granted.' : 'Admin rights removed.');
    },
    'delete-user': async (id) => {
      await loadPeople([id]);
      if (!(await ask(`This permanently deletes ${nameOf(id)}'s account and all of their data. This cannot be undone.`, { title: 'Delete account?', okText: 'Delete forever', danger: true, typed: 'DELETE' }))) return;
      const { error } = await sb.rpc('admin_delete_user', { target: id });
      if (error) return fail(error, 'Delete failed');
      people.delete(id); toast('Account deleted.'); await render();
    },
    'delete-row': async (id, btn) => {
      const { table: t, label } = btn.dataset;
      if (!(await ask(label || 'This will be permanently removed.', { title: label ? 'Please confirm' : 'Delete this item?', okText: label ? 'Confirm' : 'Delete', danger: !label }))) return;
      const { error } = await sb.from(t).delete().eq('id', id);
      if (error) return fail(error, 'Delete failed');
      toast('Done.'); await render();
    },
    'warn-user': async (id) => {
      await loadPeople([id]);
      const n = (people.get(id)?.warning_count || 0) + 1;
      if (!(await ask(`This records warning #${n} against ${nameOf(id)}.`, { title: 'Warn this user?', okText: 'Record warning' }))) return;
      await setProfileFlag(id, { warning_count: n }, 'Warning recorded.');
    },
    'hide-hazard': async (id) => {
      if (!(await ask('It will disappear from the app map. You can restore it later.', { title: 'Hide this hazard?', okText: 'Hide', danger: true }))) return;
      const { error } = await sb.from('hazards').update({ shared: false, status: 'removed' }).eq('id', id);
      if (error) return fail(error, 'Update failed'); toast('Hazard hidden.'); await render();
    },
    'show-hazard': async (id) => {
      const { error } = await sb.from('hazards').update({ shared: true, status: 'active' }).eq('id', id);
      if (error) return fail(error, 'Update failed'); toast('Hazard restored.'); await render();
    },
    'expire-stale': async () => {
      if (!(await ask('Every shared hazard older than 72 hours that nobody has verified will be hidden from the app.', { title: 'Hide stale hazards?', okText: 'Hide them' }))) return;
      const { data, error } = await sb.rpc('admin_expire_stale_hazards', { p_hours: 72 });
      if (error) return fail(error, 'Failed');
      toast(`${data ?? 0} stale hazard(s) hidden.`); await render();
    },
    'hazard-photos': async (id) => {
      const { data, error } = await sb.from('hazard_photos').select('id, path').eq('hazard_id', id).order('created_at');
      if (error) return fail(error, 'Loading photos');
      const imgs = [];
      for (const p of data || []) {
        const { data: signed } = await sb.storage.from('hazard-photos').createSignedUrl(p.path, 600);
        if (signed?.signedUrl) imgs.push(`<a href="${esc(signed.signedUrl)}" target="_blank" rel="noopener"><img src="${esc(signed.signedUrl)}" alt="Hazard photo" style="width:180px;height:180px;object-fit:cover;border-radius:10px;margin:4px"></a>`);
      }
      openModal(`<h2 style="margin-top:0">Hazard photos</h2><div>${imgs.join('') || '<p class="muted">No photos.</p>'}</div>`);
    },
    'view-proof': async (id, btn) => {
      const { data, error } = await sb.from('challenge_prize_payments').select('proof_url').eq('challenge_id', id).eq('winner_user_id', btn.dataset.user).maybeSingle();
      if (error) return fail(error, 'Loading receipt');
      if (!data?.proof_url) return toast('No receipt on file (the paid mark was removed or has no image).');
      const { data: signed, error: e2 } = await sb.storage.from('prize-proofs').createSignedUrl(data.proof_url, 600);
      if (e2) return fail(e2, 'Loading receipt');
      window.open(signed.signedUrl, '_blank', 'noopener');
    },
    'dispute-upheld': async (id) => {
      if (!(await ask('The paid mark is removed, the creator must send the prize again, and cannot create new prize challenges until they do.', { title: 'Rule: prize NOT paid?', okText: 'Not paid', danger: true }))) return;
      const { error } = await sb.rpc('resolve_prize_dispute', { p_dispute: id, p_upheld: true });
      if (error) return fail(error, 'Could not rule'); toast('Ruled: not paid.'); await render();
    },
    'dispute-rejected': async (id) => {
      if (!(await ask('The payment is treated as real and confirmed. The winner is notified.', { title: 'Rule: prize WAS paid?', okText: 'Was paid' }))) return;
      const { error } = await sb.rpc('resolve_prize_dispute', { p_dispute: id, p_upheld: false });
      if (error) return fail(error, 'Could not rule'); toast('Ruled: paid.'); await render();
    },
    participants: (id) => showParticipants(id),
    'new-challenge': () => {
      const pad = (n) => String(n).padStart(2, '0');
      const local = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
      const start = new Date(Date.now() + 3600e3), end = new Date(Date.now() + 8 * 86400e3);
      openModal(`<h2 style="margin-top:0">New official challenge</h2>
        <form id="nc-form" style="display:grid;gap:10px">
          <label>Title<input id="nc-title" maxlength="80" required placeholder="e.g. Summer 100 km Challenge"></label>
          <label>Description<textarea id="nc-desc" rows="3" maxlength="400" placeholder="Tell users why they should join"></textarea></label>
          <label>Goal type<select id="nc-type"><option value="distance">Distance (km)</option><option value="activity_count">Number of activities</option><option value="duration">Duration (minutes)</option></select></label>
          <label>Target<input id="nc-target" type="number" min="1" step="any" required placeholder="e.g. 100"></label>
          <label>Counts which activities<select id="nc-filter"><option value="any">Any</option><option value="run">Running only</option><option value="ride">Cycling only</option></select></label>
          <label>Starts<input id="nc-start" type="datetime-local" required value="${local(start)}"></label>
          <label>Ends<input id="nc-end" type="datetime-local" required value="${local(end)}"></label>
          <label>Prize in ₱ (optional)<input id="nc-prize" type="number" min="0" step="1" placeholder="0 = no prize"></label>
          <button class="btn primary" type="submit">Publish challenge</button>
        </form>`);
      $('#nc-form').onsubmit = async (ev) => {
        ev.preventDefault();
        const title = $('#nc-title').value.trim(), target = Number($('#nc-target').value);
        const s = new Date($('#nc-start').value), e = new Date($('#nc-end').value);
        const prize = Number($('#nc-prize').value) || 0;
        if (!title || !(target > 0)) return toast('Enter a title and a target above 0.', true);
        if (!(e > s)) return toast('The end must be after the start.', true);
        if (!(await ask(`Publish "${title}"${prize ? ` with a ₱${prize.toLocaleString()} prize` : ''}? Every user will be notified.${prize ? ' You will pay the winner by GCash.' : ''}`, { title: 'Publish challenge?', okText: 'Publish' }))) return;
        const { error } = await sb.from('challenges').insert({
          creator_id: me.id, title, description: $('#nc-desc').value.trim() || null,
          type: $('#nc-type').value, target_value: target, activity_filter: $('#nc-filter').value,
          start_date: s.toISOString(), end_date: e.toISOString(), prize_amount: prize || null, is_official: true,
        });
        if (error) return fail(error, 'Could not create challenge');
        closeModal(); toast('Challenge published.'); await render();
      };
    },
    'mark-paid': async (id, btn) => {
      const user = btn.dataset.user;
      if (!(await ask(`Admin override: record that the creator already paid the prize to ${nameOf(user)}. Only do this after you have verified the payment.`, { title: 'Mark prize as paid?', okText: 'Mark paid' }))) return;
      const { error } = await sb.from('challenge_prize_payments').insert({ challenge_id: id, winner_user_id: user, marked_paid_by: me.id });
      if (error) return fail(error, 'Could not mark paid');
      toast('Marked as paid.'); showParticipants(id);
    },
  };
  async function refreshList() {
    const fn = { activities: drawActivities, feed: drawFeed, comments: drawComments, challenges: drawChallenges, reports: drawReports, prizes: drawPrizes, audit: drawAudit }[view.name];
    if (fn) { try { await fn(); } catch (e) { fail(e, 'Loading'); } }
  }

  document.addEventListener('click', async (e) => {
    const el = e.target.closest('[data-act]');
    if (!el || !actions[el.dataset.act]) return;
    e.preventDefault();
    el.disabled = true;
    try { await actions[el.dataset.act](el.dataset.id, el); } catch (err) { fail(err, 'Action failed'); } finally { el.disabled = false; }
  });
  $('#modal-close').onclick = closeModal;
  $('#modal').addEventListener('click', (e) => { if (e.target.id === 'modal') closeModal(); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeModal(); });
  $('#refresh').onclick = () => { people.clear(); render(); };
  window.addEventListener('hashchange', go);

  // ---------------------------------------------------------- auth flow
  function showLogin(msg) {
    $('#app-view').hidden = true; $('#login-view').hidden = false;
    const el = $('#login-error'); el.hidden = !msg; el.textContent = msg || '';
  }
  async function enter() {
    const { data: { user } } = await sb.auth.getUser();
    if (!user) return showLogin();
    const { data: prof, error } = await sb.from('profiles').select('id, first_name, last_name, email, is_admin').eq('id', user.id).maybeSingle();
    if (error || !prof?.is_admin) {
      await sb.auth.signOut();
      return showLogin(error && /is_admin/.test(error.message) ? 'Admin setup is not finished: run supabase/018_admin.sql.' : 'This account is not an administrator.');
    }
    me = prof; people.set(prof.id, prof);
    $('#me').textContent = `${prof.first_name || ''} ${prof.last_name || ''}`.trim() || prof.email || 'Admin';
    $('#login-view').hidden = true; $('#app-view').hidden = false;
    await go();
  }
  $('#login-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = e.target.querySelector('button'); btn.disabled = true;
    const { error } = await sb.auth.signInWithPassword({ email: $('#login-email').value.trim(), password: $('#login-password').value });
    btn.disabled = false;
    if (error) return showLogin(error.message);
    $('#login-password').value = '';
    await enter();
  });
  $('#logout').onclick = async () => { await sb.auth.signOut(); me = null; showLogin(); };
  sb.auth.onAuthStateChange((ev) => { if (ev === 'SIGNED_OUT') showLogin(); });

  enter();
})();
