/* =========================================================================
 * app.js — Show-back security dashboard.
 * Data sources: bundled sample data, uploaded Entra/M365 exports, or a live
 * Azure Log Analytics workspace (KQL).
 * ========================================================================= */
(function () {
  'use strict';

  const state = {
    signins: [], riskySignins: [], riskyUsers: [], audit: [], defender: [], privRoles: [],
    source: 'sample', view: 'overview', loadedAt: null, laRange: '30d',
    dateRange: { preset: '30d', startMs: 0, endMs: 0 },
  };
  const DAYMS = 86400000;

  const $ = (sel, el = document) => el.querySelector(sel);
  const el = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const fmtNum = (n) => n.toLocaleString();
  const RISK = Charts.RISK;
  const sevColor = (s) => RISK[s] || RISK.none;
  const dt = (d) => (d instanceof Date ? d : new Date(d));
  const fmtDate = (d) => { const x = dt(d); return isNaN(x) ? '—' : x.toISOString().replace('T', ' ').slice(0, 16) + 'Z'; };
  const ago = (d) => {
    const s = (Date.now() - dt(d)) / 1000;
    if (s < 3600) return Math.round(s / 60) + 'm ago';
    if (s < 86400) return Math.round(s / 3600) + 'h ago';
    return Math.round(s / 86400) + 'd ago';
  };
  const pill = (level, text) => `<span class="pill pill-${esc(level)}">${esc(text || level)}</span>`;

  /* ---------------------------------------------------------------------- */
  /* Data loading                                                            */
  /* ---------------------------------------------------------------------- */
  async function loadSample() {
    setStatus('Loading bundled sample data…');
    const j = (f) => fetch(`data/${f}`).then((r) => { if (!r.ok) throw new Error(`${f}: ${r.status}`); return r.json(); });
    const [si, au, ru, rs, pr, df] = await Promise.all([
      j('signin-logs.json'), j('audit-logs.json'), j('risky-users.json'), j('risky-signins.json'),
      j('privileged-roles.json'), j('defender-events.json'),
    ]);
    state.signins = Parsers.normalizeSignIns(si);
    state.audit = Parsers.normalizeAudit(au);
    state.riskyUsers = Parsers.normalizeRiskyUsers(ru);
    state.riskySignins = Parsers.normalizeRiskySignIns(rs);
    state.privRoles = Parsers.normalizePrivilegedRoles(pr);
    state.defender = Parsers.normalizeDefender(df);
    state.source = 'sample';
    finishLoad();
  }

  async function loadFromLogAnalytics(cfg) {
    setStatus('Querying Log Analytics workspace…');
    const data = await LogAnalytics.loadAll(cfg);
    Object.assign(state, data);
    state.source = 'loganalytics';
    state.laRange = cfg.range;
    finishLoad();
  }

  function ingestUpload(text, filename) {
    let raw;
    try { raw = JSON.parse(text); }
    catch (_) { raw = text; } // CSV
    // Log Analytics raw API response?
    if (raw && (raw.tables || raw.Tables)) {
      const kind = Parsers.detectType({ value: Parsers.fromLogAnalytics(raw, 'signins') }, filename);
      raw = { value: Parsers.fromLogAnalytics(raw, kind) };
    }
    const kind = Parsers.detectType(raw, filename);
    switch (kind) {
      case 'audit': state.audit = Parsers.normalizeAudit(raw); break;
      case 'riskyUsers': state.riskyUsers = Parsers.normalizeRiskyUsers(raw); break;
      case 'riskySignins': state.riskySignins = Parsers.normalizeRiskySignIns(raw); break;
      case 'privRoles': state.privRoles = Parsers.normalizePrivilegedRoles(raw); break;
      case 'defender': state.defender = Parsers.normalizeDefender(raw); break;
      default: state.signins = Parsers.normalizeSignIns(raw);
    }
    state.source = 'upload';
    return kind;
  }

  function finishLoad() {
    state.loadedAt = new Date();
    // Derive risky sign-ins from sign-ins if not separately provided.
    if (!state.riskySignins.length && state.signins.length) {
      state.riskySignins = state.signins
        .filter((s) => s.riskLevel !== 'none' || s.riskState === 'atRisk')
        .map((s) => ({ ...s, isRisky: true }));
    }
    // Reset per-widget filters & cached analytics for the freshly loaded data.
    signinFilters = SIGNIN_FILTER_DEFAULTS();
    delete sigCache.unusual;
    // Default to last 30 days; widen to "all" if the data is older than that.
    setDatePreset('30d', false);
    if (!state.signins.some((s) => inRange(s.dateTime)) && !state.audit.some((a) => inRange(a.dateTime))) {
      setDatePreset('all', false);
    }
    render();
    setStatus('');
  }

  /* ---------------------------------------------------------------------- */
  /* Global date range — filters every data view in real time                */
  /* ---------------------------------------------------------------------- */
  const PRESET_DAYS = { '24h': 1, '7d': 7, '30d': 30, '90d': 90 };
  function setDatePreset(preset, doRender = true) {
    const now = Date.now();
    state.dateRange.preset = preset;
    if (preset === 'all') { state.dateRange.startMs = 0; state.dateRange.endMs = now + DAYMS; }
    else { state.dateRange.startMs = now - PRESET_DAYS[preset] * DAYMS; state.dateRange.endMs = now + DAYMS; }
    if (doRender) render();
  }
  function setCustomRange(fromStr, toStr) {
    const r = state.dateRange;
    if (fromStr) r.startMs = new Date(fromStr + 'T00:00:00Z').getTime();
    if (toStr) r.endMs = new Date(toStr + 'T23:59:59Z').getTime();
    if (r.startMs > r.endMs) { const t = r.startMs; r.startMs = r.endMs; r.endMs = t; }
    r.preset = 'custom';
    render();
  }
  const inRange = (d) => { const t = +(d instanceof Date ? d : new Date(d)); return t >= state.dateRange.startMs && t <= state.dateRange.endMs; };
  const ymd = (ms) => new Date(ms).toISOString().slice(0, 10);

  /* Ranged datasets (recomputed once per render) */
  function recomputeRanged() {
    sigCache.signins = state.signins.filter((s) => inRange(s.dateTime));
    sigCache.riskySignins = state.riskySignins.filter((s) => inRange(s.dateTime));
    sigCache.riskyUsers = state.riskyUsers.filter((u) => isNaN(u.lastUpdated) || inRange(u.lastUpdated));
    sigCache.audit = state.audit.filter((a) => inRange(a.dateTime));
    sigCache.defender = state.defender.filter((d) => inRange(d.dateTime));
    sigCache.unusual = null; // computed lazily by the sign-in widget
  }
  const rangeDays = () => Math.max(1, Math.round((Math.min(state.dateRange.endMs, Date.now()) - state.dateRange.startMs) / DAYMS));

  function renderTopbar() {
    const bar = el('topbar');
    if (!bar) return;
    if (state.view === 'source') { bar.innerHTML = ''; bar.style.display = 'none'; return; }
    bar.style.display = '';
    const r = state.dateRange;
    const presets = [['24h', '24h'], ['7d', '7d'], ['30d', '30d'], ['90d', '90d'], ['all', 'All']];
    bar.innerHTML = `
      <div class="dr-left">
        <span class="dr-label">Date range</span>
        <div class="dr-presets">
          ${presets.map(([v, l]) => `<button class="dr-preset ${r.preset === v ? 'active' : ''}" data-preset="${v}">${l}</button>`).join('')}
        </div>
        <div class="dr-custom">
          <input type="date" id="dr-from" value="${esc(r.startMs ? ymd(r.startMs) : '')}" max="${esc(ymd(Date.now()))}"/>
          <span>→</span>
          <input type="date" id="dr-to" value="${esc(ymd(Math.min(r.endMs, Date.now())))}" max="${esc(ymd(Date.now()))}"/>
        </div>
      </div>
      <div class="dr-right">
        <span class="dr-live"><i></i>Live</span>
        <span class="muted">${esc(rangeSummary())}</span>
      </div>`;
    el('dr-from').addEventListener('change', (e) => setCustomRange(e.target.value, el('dr-to').value));
    el('dr-to').addEventListener('change', (e) => setCustomRange(el('dr-from').value, e.target.value));
    bar.querySelectorAll('[data-preset]').forEach((b) => b.addEventListener('click', () => setDatePreset(b.dataset.preset)));
  }
  function rangeSummary() {
    const r = state.dateRange;
    if (r.preset === 'all') return 'All available data';
    const from = ymd(r.startMs), to = ymd(Math.min(r.endMs, Date.now()));
    return from === to ? from : `${from} → ${to}`;
  }

  /* ---------------------------------------------------------------------- */
  /* Shell                                                                   */
  /* ---------------------------------------------------------------------- */
  const NAV = [
    ['overview', 'Overview', '◧'],
    ['signins', 'Sign-in Analytics', '⇲'],
    ['governance', 'Governance & Threats', '⛨'],
    ['audit', 'Audit Logs', '☰'],
    ['source', 'Data Source', '⛁'],
  ];

  function render() {
    recomputeRanged();
    el('nav').innerHTML = NAV.map(([id, label, icon]) =>
      `<button class="nav-item ${state.view === id ? 'active' : ''}" data-view="${id}">
         <span class="nav-icon">${icon}</span>${label}</button>`).join('');
    el('source-badge').innerHTML = sourceBadge();
    renderTopbar();
    const v = state.view;
    const body = el('view');
    if (v === 'overview') body.innerHTML = viewOverview();
    else if (v === 'signins') { body.innerHTML = viewSignins(); wireSignins(); }
    else if (v === 'governance') { body.innerHTML = viewGovernance(); wireGovernance(); }
    else if (v === 'audit') { body.innerHTML = viewAudit(); wireAudit(); }
    else if (v === 'source') { body.innerHTML = viewSource(); wireSource(); }
  }

  function sourceBadge() {
    const map = { sample: ['Sample data', 'low'], upload: ['Uploaded export', 'medium'], loganalytics: ['Log Analytics', 'ok'] };
    const [label] = map[state.source] || ['—', 'none'];
    const when = state.loadedAt ? ` · ${ago(state.loadedAt)}` : '';
    return `<span class="src-dot src-${state.source}"></span>${esc(label)}${esc(when)}`;
  }

  /* ---------------------------------------------------------------------- */
  /* Overview                                                                */
  /* ---------------------------------------------------------------------- */
  function viewOverview() {
    const s = sigCache.signins;
    const days = rangeDays();
    const failures = s.filter((x) => !x.success);
    const legacy = s.filter((x) => x.isLegacy);
    const unusual = sigCache.unusual || (sigCache.unusual = Analytics.unusualActivity(s));
    const series = Analytics.dailySeries(s, days);
    const failSeries = Analytics.dailySeries(s, days, (x) => !x.success);
    const merged = series.map((d, i) => ({ ...d, alert: failSeries[i].value > 12 }));
    const ru = sigCache.riskyUsers, rs = sigCache.riskySignins, au = sigCache.audit;
    const auditFail = au.filter((a) => a.result === 'failure').length;
    const ga = Governance.globalAdmins(state.privRoles).length;
    const defender = sigCache.defender;
    const delivered = defender.filter((d) => d.delivered).length;

    return `
      ${header('Security Overview', 'Sign-in, audit, governance & threat posture across Microsoft Entra ID and M365')}
      <div class="grid stats">
        ${stat('Sign-ins', fmtNum(s.length), `${fmtNum(failures.length)} failed`, 'low', 'stat:signins')}
        ${stat('Risky users', fmtNum(ru.length), countLvl(ru, 'high') + ' high', 'medium', 'stat:riskyUsers')}
        ${stat('Risky sign-ins', fmtNum(rs.length), countLvl(rs, 'high', 'riskLevel') + ' high', 'medium', 'stat:riskySignins')}
        ${stat('Legacy auth', fmtNum(legacy.length), pctOf(legacy.length, s.length) + ' of traffic', 'high', 'stat:legacy')}
        ${stat('Flagged users', fmtNum(unusual.length), unusual.filter((u) => u.severity === 'high').length + ' high severity', 'high', 'stat:flagged')}
        ${stat('Global Admins', fmtNum(ga), ga > 5 ? 'above recommended' : 'within guidance', ga > 5 ? 'high' : 'low', 'stat:globalAdmins')}
        ${stat('OAuth consents', fmtNum(Governance.oauthConsents(au).length), Governance.oauthConsents(au).filter((c) => c.risky).length + ' high-risk', 'medium', 'stat:oauth')}
        ${stat('Defender threats', fmtNum(defender.length), `${fmtNum(delivered)} delivered`, 'high', 'stat:defender')}
        ${stat('Audit events', fmtNum(au.length), auditFail + ' failed', 'low', 'stat:audit')}
      </div>
      <div class="grid cols-2">
        ${card('Sign-in volume', `<div data-drill="signinDay">${Charts.vbar(merged)}</div>`, 'Click a bar to drill into that day · red marks elevated failures')}
        ${card('Sign-in outcome', `<div data-drill="signinOutcome">${Charts.donut([
          { label: 'Success', value: s.length - failures.length, color: RISK.low },
          { label: 'Failure', value: failures.length, color: RISK.high },
        ], { centerLabel: 'sign-ins' })}</div>`, 'Click a segment to view those sign-ins')}
      </div>
      <div class="grid cols-2">
        ${card('Top flagged users (unusual activity)', topFlaggedMini(unusual), 'Click a user to view their sign-ins')}
        ${card('Email threats by type (Defender)', `<div data-drill="defenderType">${Charts.donut(threatBreakdown(defender), { centerLabel: 'threats' })}</div>`, 'Click a segment to view those threats')}
      </div>`;
  }
  function threatBreakdown(defender) {
    const c = { Phish: 0, Malware: 0, Spam: 0 };
    defender.forEach((d) => { if (c[d.threat] !== undefined) c[d.threat]++; });
    return [
      { label: 'Phish', value: c.Phish, color: RISK.high },
      { label: 'Malware', value: c.Malware, color: RISK.medium },
      { label: 'Spam', value: c.Spam, color: RISK.low },
    ].filter((x) => x.value > 0);
  }

  function topFlaggedMini(unusual) {
    if (!unusual.length) return '<div class="ch-empty">No unusual activity detected</div>';
    return `<div class="mini-list">` + unusual.slice(0, 6).map((u) => `
      <div class="mini-row" data-drill="signinUser" data-k="${esc(u.upn)}">
        <span class="sev-dot" style="background:${sevColor(u.severity)}"></span>
        <span class="mini-name">${esc(u.user)}</span>
        <span class="score-bar"><i style="width:${u.score}%;background:${sevColor(u.severity)}"></i></span>
        <b>${u.score}</b>
      </div>`).join('') + `</div>`;
  }

  /* ---------------------------------------------------------------------- */
  /* Sign-in analytics — the four required widgets                           */
  /* ---------------------------------------------------------------------- */
  function viewSignins() {
    return `
      ${header('Sign-in Analytics', 'Exported from Entra ID sign-in logs & Identity Protection')}
      ${widgetUnusual()}
      <div class="grid cols-2">
        ${widgetRiskyUsers()}
        ${widgetRiskySignins()}
      </div>
      ${widgetLegacy()}`;
  }

  /* Per-widget filter state (persists while navigating; reset on data load) */
  const SIGNIN_FILTER_DEFAULTS = () => ({
    unusual: { severity: 'all', q: '' },
    riskyUsers: { level: 'all', state: 'all', q: '' },
    riskySignins: { level: 'all', detail: 'all', q: '' },
    legacy: { proto: 'all', result: 'all', q: '' },
  });
  let signinFilters = SIGNIN_FILTER_DEFAULTS();
  const sigCache = {};

  /* Filter-control builders */
  function fSel(id, value, opts) {
    return `<select id="${id}" class="filter-sel sm">` +
      opts.map(([v, l]) => `<option value="${esc(v)}" ${value === v ? 'selected' : ''}>${esc(l)}</option>`).join('') +
      `</select>`;
  }
  function fSearch(id, value, ph) {
    return `<div class="search-box sm"><span class="search-icon">⌕</span>
      <input id="${id}" type="search" placeholder="${esc(ph)}" value="${esc(value)}" autocomplete="off"/></div>`;
  }
  const distinct = (arr, fn) => [...new Set(arr.map(fn).filter(Boolean))].sort();
  const matches = (q, ...fields) => { q = q.trim().toLowerCase(); return !q || fields.some((f) => String(f || '').toLowerCase().includes(q)); };
  function setCount(id, shown, total, noun) { const e = el(id); if (e) e.textContent = `${fmtNum(shown)} of ${fmtNum(total)} ${noun}`; }

  /* Widget 1 — Unusual sign-in activity ---------------------------------- */
  function widgetUnusual() {
    const f = signinFilters.unusual;
    return cardWide('Unusual sign-in activity',
      `<div class="widget-filters">
         ${fSel('fu-sev', f.severity, [['all', 'All severities'], ['high', 'High'], ['medium', 'Medium'], ['low', 'Low']])}
         ${fSearch('fu-q', f.q, 'Filter by user…')}
         <span id="fu-count" class="filter-count muted"></span>
       </div>
       <div id="unusual-body"></div>`,
      'Impossible travel, password spray, off-hours bursts, new geographies, legacy auth & Identity Protection signals');
  }
  function renderUnusualBody() {
    const all = sigCache.unusual || (sigCache.unusual = Analytics.unusualActivity(sigCache.signins));
    const counts = { high: 0, medium: 0, low: 0 };
    all.forEach((u) => counts[u.severity]++);
    const f = signinFilters.unusual;
    let list = all.filter((u) => f.severity === 'all' || u.severity === f.severity);
    if (f.q.trim()) list = list.filter((u) => matches(f.q, u.user, u.upn));
    const cards = list.slice(0, 24).map((u) => `
      <div class="flag-card sev-${u.severity} drillable" data-drill="signinUser" data-k="${esc(u.upn)}">
        <div class="flag-head">
          <span class="sev-dot" style="background:${sevColor(u.severity)}"></span>
          <div>
            <div class="flag-name">${esc(u.user)}</div>
            <div class="flag-upn">${esc(u.upn)}</div>
          </div>
          <div class="flag-score" style="color:${sevColor(u.severity)}">${u.score}<small>/100</small></div>
        </div>
        <ul class="flag-reasons">${u.reasons.map((r) => `<li>${esc(r)}</li>`).join('')}</ul>
        <div class="flag-stats">
          <span>${u.stats.total} sign-ins</span><span>${u.stats.failures} failed</span>
          <span>${u.stats.countries} countries</span><span>${u.stats.legacy} legacy</span>
          <span>last ${ago(u.stats.lastSeen)}</span>
        </div>
      </div>`).join('');
    el('unusual-body').innerHTML =
      `<div class="widget-summary">
         ${chipCount('High', counts.high, RISK.high)}
         ${chipCount('Medium', counts.medium, RISK.medium)}
         ${chipCount('Low', counts.low, RISK.low)}
         <span class="muted">Behavioural anomaly scoring across ${fmtNum(sigCache.signins.length)} sign-ins</span>
       </div>
       <div class="flag-grid">${cards || '<div class="ch-empty">No users match this filter</div>'}</div>`;
    setCount('fu-count', list.length, all.length, 'users');
  }

  /* Widget 2 — Risky users ----------------------------------------------- */
  function widgetRiskyUsers() {
    const f = signinFilters.riskyUsers;
    const states = distinct(sigCache.riskyUsers, (r) => r.riskState);
    return card('Risky users',
      `<div class="widget-filters">
         ${fSel('fru-level', f.level, [['all', 'All risk'], ['high', 'High'], ['medium', 'Medium'], ['low', 'Low']])}
         ${fSel('fru-state', f.state, [['all', 'Any state'], ...states.map((s) => [s, humanize(s)])])}
         ${fSearch('fru-q', f.q, 'Filter user…')}
         <span id="fru-count" class="filter-count muted"></span>
       </div>
       <div id="ru-body"></div>`,
      'Identity Protection aggregate risk per user');
  }
  function renderRiskyUsersBody() {
    const f = signinFilters.riskyUsers;
    let u = [...sigCache.riskyUsers].sort((a, b) => lvlRank(b.riskLevel) - lvlRank(a.riskLevel));
    if (f.level !== 'all') u = u.filter((r) => r.riskLevel === f.level);
    if (f.state !== 'all') u = u.filter((r) => r.riskState === f.state);
    if (f.q.trim()) u = u.filter((r) => matches(f.q, r.user, r.upn));
    const rows = u.slice(0, 250).map((r) => `
      <tr class="row-link" data-drill="signinUser" data-k="${esc(r.upn)}" title="View sign-ins for ${esc(r.user)}">
        <td><div class="cell-name">${esc(r.user)}</div><div class="cell-sub">${esc(r.upn)}</div></td>
        <td>${pill(r.riskLevel)}</td>
        <td><span class="state-${esc(r.riskState)}">${esc(humanize(r.riskState))}</span></td>
        <td class="muted nowrap">${r.lastUpdated && !isNaN(r.lastUpdated) ? ago(r.lastUpdated) : '—'}</td>
      </tr>`).join('');
    const chart = Charts.donut(riskBreakdown(u, 'riskLevel'), { centerLabel: 'users', size: 150 });
    el('ru-body').innerHTML =
      `<div class="split"><div data-drill="riskyUserLevel">${chart}</div>
        <div class="tbl-scroll"><table class="tbl"><thead><tr><th>User</th><th>Risk</th><th>State</th><th>Updated</th></tr></thead>
        <tbody>${rows || emptyRow(4)}</tbody></table></div></div>`;
    setCount('fru-count', u.length, sigCache.riskyUsers.length, 'users');
  }

  /* Widget 3 — Risky sign-ins -------------------------------------------- */
  function widgetRiskySignins() {
    const f = signinFilters.riskySignins;
    const details = distinct(sigCache.riskySignins, (r) => r.riskDetail).filter((d) => d && d !== 'none');
    return card('Risky sign-ins',
      `<div class="widget-filters">
         ${fSel('frs-level', f.level, [['all', 'All risk'], ['high', 'High'], ['medium', 'Medium'], ['low', 'Low']])}
         ${fSel('frs-detail', f.detail, [['all', 'Any detection'], ...details.map((d) => [d, humanize(d)])])}
         ${fSearch('frs-q', f.q, 'Filter user / IP…')}
         <span id="frs-count" class="filter-count muted"></span>
       </div>
       <div id="rs-body"></div>`,
      'Sign-ins flagged at-risk by Identity Protection');
  }
  function renderRiskySigninsBody() {
    const f = signinFilters.riskySignins;
    let rs = [...sigCache.riskySignins].sort((a, b) => b.dateTime - a.dateTime);
    if (f.level !== 'all') rs = rs.filter((r) => r.riskLevel === f.level);
    if (f.detail !== 'all') rs = rs.filter((r) => r.riskDetail === f.detail);
    if (f.q.trim()) rs = rs.filter((r) => matches(f.q, r.user, r.upn, r.ip, r.location));
    const rows = rs.slice(0, 250).map((r) => `
      <tr class="row-link" data-drill="signinUser" data-k="${esc(r.upn)}" title="View sign-ins for ${esc(r.user)}">
        <td><div class="cell-name">${esc(r.user)}</div><div class="cell-sub">${esc(r.location || r.ip)}</div></td>
        <td>${pill(r.riskLevel)}</td>
        <td class="muted">${esc(humanize(r.riskDetail))}</td>
        <td class="muted nowrap">${ago(r.dateTime)}</td>
      </tr>`).join('');
    const chart = Charts.donut(riskBreakdown(rs, 'riskLevel'), { centerLabel: 'sign-ins', size: 150 });
    el('rs-body').innerHTML =
      `<div class="split"><div data-drill="riskySigninLevel">${chart}</div>
        <div class="tbl-scroll"><table class="tbl"><thead><tr><th>User / source</th><th>Risk</th><th>Detection</th><th>When</th></tr></thead>
        <tbody>${rows || emptyRow(4)}</tbody></table></div></div>`;
    setCount('frs-count', rs.length, sigCache.riskySignins.length, 'sign-ins');
  }

  /* Widget 4 — Legacy sign-in attempts ----------------------------------- */
  function widgetLegacy() {
    const f = signinFilters.legacy;
    const protos = distinct(sigCache.signins.filter((s) => s.isLegacy), (s) => s.clientApp || 'Unknown');
    return cardWide('Legacy authentication attempts',
      `<div class="widget-filters">
         ${fSel('fl-proto', f.proto, [['all', 'All protocols'], ...protos.map((p) => [p, p])])}
         ${fSel('fl-result', f.result, [['all', 'Any result'], ['success', 'Success'], ['failure', 'Failure']])}
         ${fSearch('fl-q', f.q, 'Filter user…')}
         <span id="fl-count" class="filter-count muted"></span>
       </div>
       <div id="legacy-body"></div>`,
      'Detected via client app (IMAP/POP/SMTP/ActiveSync/MAPI) and legacy user agents');
  }
  function renderLegacyBody() {
    const f = signinFilters.legacy;
    const allLegacy = sigCache.signins.filter((s) => s.isLegacy);
    const pass = (s) =>
      (f.proto === 'all' || (s.clientApp || 'Unknown') === f.proto) &&
      (f.result === 'all' || (f.result === 'success' ? s.success : !s.success)) &&
      (!f.q.trim() || matches(f.q, s.user, s.upn));
    const legacy = allLegacy.filter(pass);
    const byProto = Analytics.topBy(legacy, (s) => s.clientApp || 'Unknown', 8);
    const byUser = Analytics.topBy(legacy, (s) => s.user || s.upn, 8);
    const series = Analytics.dailySeries(legacy, rangeDays(), () => true);
    const failed = legacy.filter((s) => !s.success).length;
    el('legacy-body').innerHTML =
      `<div class="widget-summary">
         ${chipCount('Attempts', legacy.length, RISK.high)}
         ${chipCount('Failed', failed, RISK.medium)}
         ${chipCount('Users', new Set(legacy.map((s) => s.upn)).size, RISK.low)}
         <span class="muted">Legacy protocols bypass modern auth & MFA — block via Conditional Access</span>
       </div>
       <div class="grid cols-3">
         <div class="sub-card"><h4>By protocol</h4><div data-drill="legacyProto">${Charts.hbar(byProto.map((d, i) => ({ ...d, color: Charts.PALETTE[i % Charts.PALETTE.length] })))}</div></div>
         <div class="sub-card"><h4>Top users</h4><div data-drill="legacyUser">${Charts.hbar(byUser.map((d) => ({ ...d, color: RISK.medium })))}</div></div>
         <div class="sub-card"><h4>Daily trend</h4><div data-drill="legacyDay">${Charts.vbar(series.map((d) => ({ ...d, color: RISK.high })), { width: 380, height: 180 })}</div></div>
       </div>`;
    setCount('fl-count', legacy.length, allLegacy.length, 'attempts');
  }

  /* Wire all sign-in widget filters after the view is rendered ------------ */
  function wireSignins() {
    sigCache.unusual = Analytics.unusualActivity(sigCache.signins);
    renderUnusualBody();
    renderRiskyUsersBody();
    renderRiskySigninsBody();
    renderLegacyBody();

    const onSel = (id, fn) => { const e = el(id); if (e) e.addEventListener('change', () => fn(e.value)); };
    const onSearch = (id, fn) => {
      const e = el(id); if (!e) return; let t;
      e.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => fn(e.value), 150); });
    };
    onSel('fu-sev', (v) => { signinFilters.unusual.severity = v; renderUnusualBody(); });
    onSearch('fu-q', (v) => { signinFilters.unusual.q = v; renderUnusualBody(); });
    onSel('fru-level', (v) => { signinFilters.riskyUsers.level = v; renderRiskyUsersBody(); });
    onSel('fru-state', (v) => { signinFilters.riskyUsers.state = v; renderRiskyUsersBody(); });
    onSearch('fru-q', (v) => { signinFilters.riskyUsers.q = v; renderRiskyUsersBody(); });
    onSel('frs-level', (v) => { signinFilters.riskySignins.level = v; renderRiskySigninsBody(); });
    onSel('frs-detail', (v) => { signinFilters.riskySignins.detail = v; renderRiskySigninsBody(); });
    onSearch('frs-q', (v) => { signinFilters.riskySignins.q = v; renderRiskySigninsBody(); });
    onSel('fl-proto', (v) => { signinFilters.legacy.proto = v; renderLegacyBody(); });
    onSel('fl-result', (v) => { signinFilters.legacy.result = v; renderLegacyBody(); });
    onSearch('fl-q', (v) => { signinFilters.legacy.q = v; renderLegacyBody(); });
  }

  /* ---------------------------------------------------------------------- */
  /* Governance & Threats — components 1–9                                    */
  /* ---------------------------------------------------------------------- */
  const govFilters = {};
  let govCache = {};

  function computeGov() {
    const au = sigCache.audit;
    govCache = {
      ga: Governance.globalAdmins(state.privRoles),
      roleInv: Governance.roleInventory(state.privRoles),
      gaChanges: Governance.globalAdminChanges(au),
      priv: Governance.privilegedAssignments(au),
      ca: Governance.caChanges(au),
      sharing: Governance.sharingPolicyChanges(au),
      external: Governance.externalUsers(au),
      anon: Governance.anonymousLinks(au),
      forward: Governance.forwardingRules(au),
      oauth: Governance.oauthConsents(au),
      defender: sigCache.defender,
    };
  }

  function viewGovernance() {
    computeGov();
    const ga = govCache.ga.length;
    return `
      ${header('Governance & Threats', 'Privileged access, tenant-configuration changes & Microsoft Defender threats')}
      <div class="grid stats">
        ${stat('Global Admins', fmtNum(ga), ga > 5 ? 'above recommended (≤5)' : 'within guidance', ga > 5 ? 'high' : 'low', 'stat:globalAdmins')}
        ${stat('New priv. assignments', fmtNum(govCache.priv.length), 'in selected range', 'medium', 'stat:priv')}
        ${stat('Cond. Access changes', fmtNum(govCache.ca.length), 'in selected range', 'medium', 'stat:ca')}
        ${stat('SharePoint policy', fmtNum(govCache.sharing.length), 'sharing changes', 'medium', 'stat:sharing')}
        ${stat('New external users', fmtNum(govCache.external.length), 'guest invitations', 'medium', 'stat:external')}
        ${stat('Anonymous links', fmtNum(govCache.anon.length), 'created', 'high', 'stat:anon')}
        ${stat('Forwarding rules', fmtNum(govCache.forward.length), govCache.forward.filter((f) => f.external).length + ' external', 'high', 'stat:forward')}
        ${stat('OAuth consents', fmtNum(govCache.oauth.length), govCache.oauth.filter((c) => c.risky).length + ' high-risk', 'medium', 'stat:oauth')}
        ${stat('Defender threats', fmtNum(govCache.defender.length), govCache.defender.filter((d) => d.delivered).length + ' delivered', 'high', 'stat:defender')}
      </div>
      <div class="grid cols-2">
        ${govShellGlobalAdmins()}
        ${govShell('priv', 'New privileged role assignments', 'Members added to privileged directory roles', 'Filter member / role…')}
      </div>
      <div class="grid cols-2">
        ${govShell('ca', 'Conditional Access changes', 'CA policies added, updated or deleted', 'Filter policy…')}
        ${govShell('sharing', 'SharePoint sharing policy changes', 'Tenant external-sharing configuration', 'Filter change…')}
      </div>
      <div class="grid cols-2">
        ${govShell('external', 'New external (guest) users', 'B2B invitations / #EXT# accounts', 'Filter user…')}
        ${govShell('anon', 'Anonymous sharing links created', 'Anyone-with-the-link files (SharePoint/OneDrive)', 'Filter file…')}
      </div>
      <div class="grid cols-2">
        ${govShell('forward', 'Mail forwarding rules', 'Inbox rules & mailbox forwarding', 'Filter mailbox / target…')}
        ${govShell('oauth', 'OAuth app consents', 'Delegated & application permission grants', 'Filter app…')}
      </div>
      ${govShellDefender()}`;
  }

  function govShell(id, title, foot, ph) {
    govFilters[id] = govFilters[id] || '';
    return card(title,
      `<div class="widget-filters">${fSearch('gf-' + id, govFilters[id], ph)}<span id="gc-${id}" class="filter-count muted"></span></div>
       <div id="gb-${id}"></div>`, foot);
  }
  function govShellGlobalAdmins() {
    return card('Global administrators',
      `<div id="gb-ga"></div>`, 'Standing Global Administrator membership (point-in-time) + recent changes');
  }
  function govShellDefender() {
    govFilters.defender = govFilters.defender || '';
    return cardWide('Microsoft Defender for Office 365 — phishing & malware',
      `<div class="widget-filters">${fSearch('gf-defender', govFilters.defender, 'Filter sender / subject / recipient…')}<span id="gc-defender" class="filter-count muted"></span></div>
       <div id="gb-defender"></div>`, 'Email threats detected by Defender (EmailEvents) across the selected range');
  }

  /* Generic ranged + searchable table renderer for governance widgets */
  function renderGovBody(id, all, columns, searchFields, opts = {}) {
    const q = (govFilters[id] || '').trim().toLowerCase();
    const rows = q ? all.filter((r) => searchFields(r).some((f) => String(f || '').toLowerCase().includes(q))) : all;
    const head = '<tr>' + columns.map((c) => `<th>${esc(c.h)}</th>`).join('') + '</tr>';
    const body = rows.slice(0, 300).map((r) => '<tr>' + columns.map((c) => `<td>${c.c(r)}</td>`).join('') + '</tr>').join('') || emptyRow(columns.length);
    el('gb-' + id).innerHTML =
      `${opts.summary ? `<div class="widget-summary">${opts.summary}</div>` : ''}
       <div class="tbl-scroll"><table class="tbl"><thead>${head}</thead><tbody>${body}</tbody></table></div>`;
    setCount('gc-' + id, rows.length, all.length, opts.noun || 'events');
  }

  const privPillClass = (role) => /global|privileged|security|authentication admin/i.test(role) ? 'pill-high' : 'pill-medium';
  const threatPill = (t) => `<span class="pill ${t === 'Phish' ? 'pill-high' : t === 'Malware' ? 'pill-medium' : 'pill-low'}">${esc(t)}</span>`;
  const countThreat = (arr, t) => arr.filter((d) => d.threat === t).length;

  /* Component 1 — Global administrators (point-in-time membership + changes) */
  function renderGovGlobalAdmins() {
    const ga = govCache.ga;
    const inv = govCache.roleInv;
    const changes = govCache.gaChanges;
    const over = ga.length > 5;
    const members = ga.map((m) => `<tr><td><div class="cell-name">${esc(m.member)}</div><div class="cell-sub">${esc(m.upn)}</div></td><td>${esc(m.assignmentType || 'Assigned')}</td></tr>`).join('');
    const changeRows = changes.slice(0, 6).map((c) => `<tr>
        <td>${/add/i.test(c.activity) ? pill('high', 'Added') : pill('low', 'Removed')}</td>
        <td><div class="cell-name">${esc(c.member)}</div></td>
        <td class="muted nowrap">${ago(c.dateTime)}</td></tr>`).join('');
    el('gb-ga').innerHTML = `
      <div class="ga-head">
        <div class="ga-num ${over ? 'over' : ''}">${ga.length}<small>Global Admins</small></div>
        <div class="ga-note">${over
          ? `<span class="warn">⚠ Above Microsoft's recommended maximum of 5.</span> Reduce standing access and use PIM eligibility.`
          : `Within the recommended limit (≤5). Keep standing access minimal.`}</div>
      </div>
      <div class="split" style="margin-top:6px">
        <div style="flex:1;min-width:200px">
          <h4 class="sub-h">Members</h4>
          <div class="tbl-scroll" style="max-height:200px"><table class="tbl"><tbody>${members || emptyRow(2)}</tbody></table></div>
        </div>
        <div style="flex:1;min-width:200px">
          <h4 class="sub-h">Recent Global Admin changes</h4>
          <div class="tbl-scroll" style="max-height:200px"><table class="tbl"><tbody>${changeRows || emptyRow(3)}</tbody></table></div>
        </div>
      </div>
      <h4 class="sub-h" style="margin-top:12px">Privileged role inventory <span class="muted" style="font-weight:400">— click a role for members</span></h4>
      <div data-drill="role">${Charts.hbar(inv.map((d, i) => ({ ...d, color: privPillClass(d.label) === 'pill-high' ? RISK.high : Charts.PALETTE[i % Charts.PALETTE.length] })))}</div>`;
  }

  /* Component 2 — New privileged role assignments */
  function renderGovPriv() {
    renderGovBody('priv', govCache.priv, [
      { h: 'Member', c: (r) => `<div class="cell-name">${esc(r.member)}</div>` },
      { h: 'Role', c: (r) => `<span class="pill ${privPillClass(r.role)}">${esc(r.role)}</span>` },
      { h: 'Initiated by', c: (r) => `<div class="cell-sub">${esc(r.actor || '—')}</div>` },
      { h: 'When', c: (r) => `<span class="muted nowrap">${ago(r.dateTime)}</span>` },
    ], (r) => [r.member, r.role, r.actor], { noun: 'assignments' });
  }

  /* Component 3 — Conditional Access changes */
  function renderGovCA() {
    renderGovBody('ca', govCache.ca, [
      { h: 'Policy', c: (r) => `<div class="cell-name">${esc(r.policy || '—')}</div>${r.change ? `<div class="cell-sub">${esc(r.change)}</div>` : ''}` },
      { h: 'Operation', c: (r) => `<span class="muted">${esc(r.activity.replace(' conditional access policy', ''))}</span>` },
      { h: 'Initiated by', c: (r) => `<div class="cell-sub">${esc(r.actor || '—')}</div>` },
      { h: 'When', c: (r) => `<span class="muted nowrap">${ago(r.dateTime)}</span>` },
    ], (r) => [r.policy, r.change, r.actor, r.activity], { noun: 'changes' });
  }

  /* Component 4 — SharePoint sharing policy changes */
  function renderGovSharing() {
    renderGovBody('sharing', govCache.sharing, [
      { h: 'Change', c: (r) => `<div class="cell-name">${esc(r.activity)}</div><div class="cell-sub">${esc(r.change || '')}</div>` },
      { h: 'Service', c: (r) => `<span class="muted">${esc(r.service)}</span>` },
      { h: 'Initiated by', c: (r) => `<div class="cell-sub">${esc(r.actor || '—')}</div>` },
      { h: 'When', c: (r) => `<span class="muted nowrap">${ago(r.dateTime)}</span>` },
    ], (r) => [r.activity, r.change, r.actor], { noun: 'changes' });
  }

  /* Component 5 — New external users */
  function renderGovExternal() {
    renderGovBody('external', govCache.external, [
      { h: 'External user', c: (r) => `<div class="cell-name">${esc(r.email)}</div>` },
      { h: 'Invited as', c: (r) => `<div class="cell-sub">${esc(trunc(r.target || '', 32))}</div>` },
      { h: 'Invited by', c: (r) => `<div class="cell-sub">${esc(r.actor || '—')}</div>` },
      { h: 'When', c: (r) => `<span class="muted nowrap">${ago(r.dateTime)}</span>` },
    ], (r) => [r.email, r.target, r.actor], { noun: 'users' });
  }

  /* Component 6 — Anonymous sharing links */
  function renderGovAnon() {
    renderGovBody('anon', govCache.anon, [
      { h: 'Resource', c: (r) => `<div class="cell-name">${esc(r.resource)}</div>` },
      { h: 'Link', c: (r) => `<span class="pill ${r.linkType === 'Edit' ? 'pill-high' : 'pill-low'}">${esc(r.linkType || 'View')}</span>` },
      { h: 'Service', c: (r) => `<span class="muted">${esc(r.service)}</span>` },
      { h: 'Created by', c: (r) => `<div class="cell-sub">${esc(r.actor || '—')}</div>` },
      { h: 'When', c: (r) => `<span class="muted nowrap">${ago(r.dateTime)}</span>` },
    ], (r) => [r.resource, r.actor, r.service], { noun: 'links' });
  }

  /* Component 7 — Mail forwarding rules */
  function renderGovForward() {
    renderGovBody('forward', govCache.forward, [
      { h: 'Mailbox', c: (r) => `<div class="cell-name">${esc(r.actor || '—')}</div>` },
      { h: 'Forwards to', c: (r) => `<div class="cell-name">${esc(r.forwardTo || '')}</div>` },
      { h: 'Scope', c: (r) => r.external ? pill('high', 'External') : pill('low', 'Internal') },
      { h: 'When', c: (r) => `<span class="muted nowrap">${ago(r.dateTime)}</span>` },
    ], (r) => [r.actor, r.forwardTo], { noun: 'rules' });
  }

  /* Component 8 — OAuth app consents */
  function renderGovOAuth() {
    renderGovBody('oauth', govCache.oauth, [
      { h: 'Application', c: (r) => `<div class="cell-name">${esc(r.app)}</div><div class="cell-sub">${esc(r.consentType || '')}</div>` },
      { h: 'Permissions', c: (r) => `<div class="perm-tags">${(r.permissions || []).map((p) => `<span class="perm ${/readwrite|\.all|full_access|directory|mail\.|files\./i.test(p) ? 'perm-risk' : ''}">${esc(p)}</span>`).join('') || '—'}</div>` },
      { h: 'Risk', c: (r) => r.risky ? pill('high', 'High') : pill('low', 'Low') },
      { h: 'When', c: (r) => `<span class="muted nowrap">${ago(r.dateTime)}</span>` },
    ], (r) => [r.app, (r.permissions || []).join(' '), r.actor], { noun: 'consents' });
  }

  /* Component 9 — Defender phishing / malware trends */
  function renderGovDefender() {
    const all = govCache.defender;
    const q = (govFilters.defender || '').trim().toLowerCase();
    const rows = q ? all.filter((d) => [d.sender, d.subject, d.recipient, d.recipientName, d.threat, d.malwareFamily].some((f) => String(f || '').toLowerCase().includes(q))) : all;
    const series = Analytics.dailySeries(rows, rangeDays(), () => true);
    const delivered = rows.filter((d) => d.delivered).length;
    const table = rows.slice(0, 150).map((d) => `<tr>
        <td class="muted nowrap">${fmtDate(d.dateTime)}</td>
        <td>${threatPill(d.threat)}</td>
        <td><div class="cell-name">${esc(trunc(d.subject, 46))}</div><div class="cell-sub">${esc(d.sender)}</div></td>
        <td>${esc(d.recipientName || d.recipient)}</td>
        <td>${d.delivered ? pill('high', 'Delivered') : pill('low', esc(d.delivery || 'Blocked'))}</td>
      </tr>`).join('');
    el('gb-defender').innerHTML = `
      <div class="widget-summary">
        ${chipCount('Phish', countThreat(rows, 'Phish'), RISK.high)}
        ${chipCount('Malware', countThreat(rows, 'Malware'), RISK.medium)}
        ${chipCount('Spam', countThreat(rows, 'Spam'), RISK.low)}
        ${chipCount('Delivered', delivered, RISK.high)}
        <span class="muted">Blocked vs delivered email threats over the selected range</span>
      </div>
      <div class="grid cols-3">
        <div class="sub-card"><h4>Daily volume</h4><div data-drill="defenderDay">${Charts.vbar(series.map((s) => ({ ...s, color: RISK.high })), { width: 380, height: 180 })}</div></div>
        <div class="sub-card"><h4>By type</h4><div data-drill="defenderType">${Charts.donut(threatBreakdown(rows), { centerLabel: 'threats', size: 150 })}</div></div>
        <div class="sub-card"><h4>Top targeted users</h4><div data-drill="defenderUser">${Charts.hbar(Analytics.topBy(rows, (d) => d.recipientName || d.recipient, 6).map((x) => ({ ...x, color: RISK.medium })))}</div></div>
      </div>
      <div class="tbl-scroll" style="margin-top:12px"><table class="tbl"><thead><tr><th>Time (UTC)</th><th>Type</th><th>Subject / sender</th><th>Recipient</th><th>Delivery</th></tr></thead><tbody>${table || emptyRow(5)}</tbody></table></div>`;
    setCount('gc-defender', rows.length, all.length, 'emails');
  }

  function wireGovernance() {
    computeGov();
    renderGovGlobalAdmins();
    renderGovPriv(); renderGovCA(); renderGovSharing(); renderGovExternal();
    renderGovAnon(); renderGovForward(); renderGovOAuth(); renderGovDefender();
    const onSearch = (id, fn) => {
      const e = el('gf-' + id); if (!e) return; let t;
      e.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => { govFilters[id] = e.value; fn(); }, 150); });
    };
    onSearch('priv', renderGovPriv); onSearch('ca', renderGovCA); onSearch('sharing', renderGovSharing);
    onSearch('external', renderGovExternal); onSearch('anon', renderGovAnon); onSearch('forward', renderGovForward);
    onSearch('oauth', renderGovOAuth); onSearch('defender', renderGovDefender);
  }

  /* ---------------------------------------------------------------------- */
  /* Audit logs — searchable interface                                       */
  /* ---------------------------------------------------------------------- */
  const auditState = { q: '', service: '', result: '', sort: 'dateTime', dir: -1, page: 0, size: 25 };

  function viewAudit() {
    const services = [...new Set(sigCache.audit.map((a) => a.service).filter(Boolean))].sort();
    return `
      ${header('Audit Logs', 'Directory & Microsoft 365 activity — search and drill down')}
      ${card('', `
        <div class="audit-toolbar">
          <div class="search-box">
            <span class="search-icon">⌕</span>
            <input id="audit-q" type="search" placeholder="Search activity, user, target, IP, category…" value="${esc(auditState.q)}" autocomplete="off"/>
          </div>
          <select id="audit-service" class="filter-sel">
            <option value="">All services</option>
            ${services.map((s) => `<option value="${esc(s)}" ${auditState.service === s ? 'selected' : ''}>${esc(s)}</option>`).join('')}
          </select>
          <select id="audit-result" class="filter-sel">
            <option value="">Any result</option>
            <option value="success" ${auditState.result === 'success' ? 'selected' : ''}>Success</option>
            <option value="failure" ${auditState.result === 'failure' ? 'selected' : ''}>Failure</option>
          </select>
          <button id="audit-clear" class="btn-ghost">Clear</button>
        </div>
        <div id="audit-results"></div>
      `, '', 'audit-card')}`;
  }

  function filteredAudit() {
    const q = auditState.q.trim().toLowerCase();
    let rows = sigCache.audit.filter((a) => {
      if (auditState.service && a.service !== auditState.service) return false;
      if (auditState.result && a.result !== auditState.result) return false;
      if (!q) return true;
      return [a.activity, a.actor, a.actorUpn, a.target, a.ip, a.category, a.service, a.resultReason]
        .some((f) => String(f || '').toLowerCase().includes(q));
    });
    const { sort, dir } = auditState;
    rows.sort((a, b) => {
      let av = a[sort], bv = b[sort];
      if (sort === 'dateTime') { av = +a.dateTime; bv = +b.dateTime; }
      else { av = String(av || '').toLowerCase(); bv = String(bv || '').toLowerCase(); }
      return av < bv ? -dir : av > bv ? dir : 0;
    });
    return rows;
  }

  function renderAuditResults() {
    const rows = filteredAudit();
    const total = rows.length;
    const pages = Math.max(1, Math.ceil(total / auditState.size));
    auditState.page = Math.min(auditState.page, pages - 1);
    const start = auditState.page * auditState.size;
    const page = rows.slice(start, start + auditState.size);
    const sortHdr = (key, label) =>
      `<th class="sortable ${auditState.sort === key ? 'sorted' : ''}" data-sort="${key}">${label}${auditState.sort === key ? (auditState.dir === 1 ? ' ▲' : ' ▼') : ''}</th>`;

    const body = page.map((a, i) => `
      <tr class="audit-row" data-idx="${start + i}">
        <td class="nowrap muted">${fmtDate(a.dateTime)}</td>
        <td><div class="cell-name">${esc(a.activity)}</div><div class="cell-sub">${esc(a.category)}</div></td>
        <td>${esc(a.service)}</td>
        <td><div class="cell-name">${esc(a.actor || '—')}</div><div class="cell-sub">${esc(a.ip || '')}</div></td>
        <td>${esc(a.target || '—')}</td>
        <td>${a.result === 'failure' ? pill('high', 'failure') : pill('low', 'success')}</td>
      </tr>
      <tr class="audit-detail" id="ad-${start + i}" hidden><td colspan="6">${auditDetail(a)}</td></tr>
    `).join('');

    el('audit-results').innerHTML = `
      <div class="result-meta">${fmtNum(total)} event${total === 1 ? '' : 's'}${auditState.q ? ` matching “${esc(auditState.q)}”` : ''}</div>
      <div class="tbl-scroll">
        <table class="tbl audit-tbl">
          <thead><tr>${sortHdr('dateTime', 'Time (UTC)')}${sortHdr('activity', 'Activity')}${sortHdr('service', 'Service')}${sortHdr('actor', 'Initiated by')}${sortHdr('target', 'Target')}${sortHdr('result', 'Result')}</tr></thead>
          <tbody>${body || `<tr><td colspan="6" class="ch-empty">No matching audit events</td></tr>`}</tbody>
        </table>
      </div>
      <div class="pager">
        <button class="btn-ghost" data-page="prev" ${auditState.page === 0 ? 'disabled' : ''}>← Prev</button>
        <span class="muted">Page ${auditState.page + 1} of ${pages}</span>
        <button class="btn-ghost" data-page="next" ${auditState.page >= pages - 1 ? 'disabled' : ''}>Next →</button>
      </div>`;

    // wire row interactions
    $('#audit-results').querySelectorAll('.audit-row').forEach((tr) => {
      tr.addEventListener('click', () => {
        const d = el('ad-' + tr.dataset.idx);
        if (d) d.hidden = !d.hidden;
      });
    });
    $('#audit-results').querySelectorAll('.sortable').forEach((th) => {
      th.addEventListener('click', () => {
        const k = th.dataset.sort;
        if (auditState.sort === k) auditState.dir *= -1; else { auditState.sort = k; auditState.dir = k === 'dateTime' ? -1 : 1; }
        renderAuditResults();
      });
    });
    $('#audit-results').querySelectorAll('[data-page]').forEach((b) => {
      b.addEventListener('click', () => {
        auditState.page += b.dataset.page === 'next' ? 1 : -1;
        renderAuditResults();
      });
    });
  }

  function auditDetail(a) {
    const raw = JSON.stringify(a.raw, null, 2);
    const kv = [
      ['Correlation ID', a.correlationId], ['Result reason', a.resultReason],
      ['Initiated by', a.actorUpn || a.actor], ['Source IP', a.ip],
      ['Target', a.target], ['Target type', a.targetType], ['Category', a.category],
    ].filter(([, v]) => v);
    return `<div class="detail-wrap">
      <div class="detail-kv">${kv.map(([k, v]) => `<div><span>${esc(k)}</span><b>${esc(v)}</b></div>`).join('')}</div>
      <details class="raw-details"><summary>Raw event JSON</summary><pre class="raw-json">${esc(raw)}</pre></details>
    </div>`;
  }

  function wireAudit() {
    renderAuditResults();
    const q = el('audit-q');
    let t;
    q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => { auditState.q = q.value; auditState.page = 0; renderAuditResults(); }, 150); });
    el('audit-service').addEventListener('change', (e) => { auditState.service = e.target.value; auditState.page = 0; renderAuditResults(); });
    el('audit-result').addEventListener('change', (e) => { auditState.result = e.target.value; auditState.page = 0; renderAuditResults(); });
    el('audit-clear').addEventListener('click', () => {
      auditState.q = ''; auditState.service = ''; auditState.result = ''; auditState.page = 0;
      q.value = ''; el('audit-service').value = ''; el('audit-result').value = ''; renderAuditResults();
    });
  }

  /* ---------------------------------------------------------------------- */
  /* Data source view                                                        */
  /* ---------------------------------------------------------------------- */
  function viewSource() {
    return `
      ${header('Data Source', 'Choose where the dashboard reads audit & sign-in data from')}
      <div class="grid cols-3">
        ${card('① Sample data', `
          <p class="muted">Bundled, anonymised sample of Entra ID / M365 exports with seeded anomalies — useful for a demo or offline review.</p>
          <button id="src-sample" class="btn">Load sample data</button>`)}
        ${card('② Upload exports', `
          <p class="muted">Drop Entra ID / M365 exports — JSON (“Download JSON”), CSV, or a raw Log Analytics query result. File type is auto-detected by name & schema.</p>
          <div id="dropzone" class="dropzone">
            <input id="file-input" type="file" multiple accept=".json,.csv" hidden/>
            <span>Drag files here or <button id="browse" class="link-btn">browse</button></span>
          </div>
          <div id="upload-log" class="upload-log"></div>`)}
        ${card('③ Azure Log Analytics', `
          <p class="muted">Query the workspace directly via the Log Analytics API. Get a token with:<br>
          <code>az account get-access-token --resource https://api.loganalytics.io</code></p>
          <label class="fld">Workspace ID<input id="la-ws" type="text" placeholder="00000000-0000-0000-0000-000000000000"/></label>
          <label class="fld">Bearer token<input id="la-token" type="password" placeholder="eyJ0eXAiOiJKV1Qi…"/></label>
          <label class="fld">Time range
            <select id="la-range"><option value="24h">Last 24h</option><option value="7d">Last 7 days</option><option value="30d" selected>Last 30 days</option><option value="90d">Last 90 days</option></select>
          </label>
          <button id="src-la" class="btn">Connect & query</button>
          <div id="la-log" class="upload-log"></div>`)}
      </div>
      ${card('Reference — KQL used for Log Analytics', `
        <p class="muted">These are the queries this dashboard runs against your workspace. You can also paste their JSON output via the upload panel.</p>
        <div class="kql-tabs">
          ${Object.entries({ 'Sign-ins': 'signins', 'Risky sign-ins': 'riskySignins', 'Risky users': 'riskyUsers', 'Audit logs': 'audit', 'Privileged roles': 'privRoles', 'Defender threats': 'defender' })
            .map(([label, k], i) => `<button class="kql-tab ${i === 0 ? 'active' : ''}" data-kql="${k}">${label}</button>`).join('')}
        </div>
        <pre id="kql-view" class="raw-json kql-view">${esc(LogAnalytics.KQL.signins('30d').trim())}</pre>`)}
    `;
  }

  function wireSource() {
    el('src-sample').addEventListener('click', () => loadSample().then(() => { state.view = 'overview'; render(); }).catch(err));

    const fi = el('file-input');
    el('browse').addEventListener('click', () => fi.click());
    fi.addEventListener('change', () => handleFiles(fi.files));
    const dz = el('dropzone');
    ['dragover', 'dragenter'].forEach((e) => dz.addEventListener(e, (ev) => { ev.preventDefault(); dz.classList.add('over'); }));
    ['dragleave', 'drop'].forEach((e) => dz.addEventListener(e, (ev) => { ev.preventDefault(); dz.classList.remove('over'); }));
    dz.addEventListener('drop', (ev) => handleFiles(ev.dataTransfer.files));

    el('src-la').addEventListener('click', async () => {
      const workspaceId = el('la-ws').value.trim();
      const token = el('la-token').value.trim();
      const range = el('la-range').value;
      const log = el('la-log');
      if (!workspaceId || !token) { log.innerHTML = '<span class="err">Workspace ID and token are required.</span>'; return; }
      log.innerHTML = '<span class="muted">Querying…</span>';
      try {
        await loadFromLogAnalytics({ workspaceId, token, range });
        log.innerHTML = `<span class="ok">✔ Loaded ${fmtNum(state.signins.length)} sign-ins, ${fmtNum(state.audit.length)} audit events.</span>`;
        state.view = 'overview'; render();
      } catch (e) {
        log.innerHTML = `<span class="err">✖ ${esc(e.message)}</span><div class="muted">If this is a CORS/401 error, confirm the token targets <code>api.loganalytics.io</code> and the workspace ID is correct.</div>`;
      }
    });

    // KQL tab switching
    document.querySelectorAll('.kql-tab').forEach((tab) => {
      tab.addEventListener('click', () => {
        document.querySelectorAll('.kql-tab').forEach((t) => t.classList.remove('active'));
        tab.classList.add('active');
        const k = tab.dataset.kql;
        const range = '30d';
        const q = k === 'riskyUsers' ? LogAnalytics.KQL.riskyUsers('90d') : LogAnalytics.KQL[k](range);
        el('kql-view').textContent = q.trim();
      });
    });
  }

  function handleFiles(files) {
    const log = el('upload-log');
    [...files].forEach((file) => {
      const reader = new FileReader();
      reader.onload = () => {
        try {
          const kind = ingestUpload(reader.result, file.name);
          state.loadedAt = new Date();
          if (!state.riskySignins.length && state.signins.length) finishLoad(); else render();
          log.insertAdjacentHTML('beforeend', `<div class="ok">✔ ${esc(file.name)} → ${esc(kindLabel(kind))}</div>`);
        } catch (e) {
          log.insertAdjacentHTML('beforeend', `<div class="err">✖ ${esc(file.name)}: ${esc(e.message)}</div>`);
        }
      };
      reader.readAsText(file);
    });
  }
  const kindLabel = (k) => ({ signins: 'Sign-in logs', audit: 'Audit logs', riskyUsers: 'Risky users', riskySignins: 'Risky sign-ins', privRoles: 'Privileged roles', defender: 'Defender threats' }[k] || k);

  /* ---------------------------------------------------------------------- */
  /* Small render helpers                                                     */
  /* ---------------------------------------------------------------------- */
  function header(title, sub) { return `<div class="view-head"><h1>${esc(title)}</h1><p>${esc(sub)}</p></div>`; }
  function stat(label, value, sub, level, drill) {
    const d = drill ? ` drillable" data-drill="${esc(drill)}" tabindex="0` : '';
    return `<div class="stat-card${d}">
      <div class="stat-accent" style="background:${sevColor(level)}"></div>
      <div class="stat-label">${esc(label)}</div>
      <div class="stat-value">${esc(value)}</div>
      <div class="stat-sub">${esc(sub)}</div></div>`;
  }
  function card(title, body, foot, cls = '') {
    return `<div class="card ${cls}">
      ${title ? `<div class="card-head"><h3>${title}</h3></div>` : ''}
      <div class="card-body">${body}</div>
      ${foot ? `<div class="card-foot">${esc(foot)}</div>` : ''}</div>`;
  }
  function cardWide(title, body, foot) { return `<div class="card wide"><div class="card-head"><h3>${esc(title)}</h3></div><div class="card-body">${body}</div>${foot ? `<div class="card-foot">${esc(foot)}</div>` : ''}</div>`; }
  function chipCount(label, n, color) { return `<span class="chip"><i style="background:${color}"></i>${esc(label)} <b>${fmtNum(n)}</b></span>`; }
  function emptyRow(cols) { return `<tr><td colspan="${cols}" class="ch-empty">No data</td></tr>`; }

  function riskBreakdown(records, field) {
    const c = { high: 0, medium: 0, low: 0 };
    records.forEach((r) => { const l = (r[field] || 'none'); if (c[l] !== undefined) c[l]++; });
    return [
      { label: 'High', value: c.high, color: RISK.high },
      { label: 'Medium', value: c.medium, color: RISK.medium },
      { label: 'Low', value: c.low, color: RISK.low },
    ].filter((x) => x.value > 0);
  }
  const lvlRank = (l) => ({ high: 3, medium: 2, low: 1, none: 0 }[l] || 0);
  const countLvl = (arr, lvl, field = 'riskLevel') => arr.filter((x) => x[field] === lvl).length;
  const countAuditFail = () => state.audit.filter((a) => a.result === 'failure').length;
  const pctOf = (n, total) => total ? Math.round((n / total) * 100) + '%' : '0%';
  const humanize = (s) => String(s || '').replace(/([a-z])([A-Z])/g, '$1 $2').replace(/^./, (c) => c.toUpperCase());
  const trunc = (s, n) => { s = String(s || ''); return s.length > n ? s.slice(0, n - 1) + '…' : s; };

  function setStatus(msg) { const b = el('status'); if (b) { b.textContent = msg; b.style.display = msg ? 'block' : 'none'; } }
  function err(e) { setStatus(''); console.error(e); alert('Error loading data: ' + e.message); }

  /* ---------------------------------------------------------------------- */
  /* Drill-down — clicking widgets opens a filtered detail view              */
  /* ---------------------------------------------------------------------- */
  const dayKeyOf = (d) => { const x = d instanceof Date ? d : new Date(d); return isNaN(x) ? '' : x.toISOString().slice(0, 10); };

  /* Column sets for the detail tables */
  const COLS = {
    signins: () => [
      { h: 'Time (UTC)', c: (s) => `<span class="nowrap">${fmtDate(s.dateTime)}</span>` },
      { h: 'User', c: (s) => `<div class="cell-name">${esc(s.user)}</div><div class="cell-sub">${esc(s.upn)}</div>` },
      { h: 'IP / Location', c: (s) => `${esc(s.ip || '')}<div class="cell-sub">${esc(s.location || '')}</div>` },
      { h: 'App', c: (s) => esc(s.app || '') },
      { h: 'Client', c: (s) => `${esc(s.clientApp || '')}${s.isLegacy ? ' ' + pill('high', 'legacy') : ''}` },
      { h: 'Risk', c: (s) => (s.riskLevel && s.riskLevel !== 'none') ? pill(s.riskLevel) : '<span class="muted">—</span>' },
      { h: 'Status', c: (s) => s.success ? pill('low', 'success') : pill('high', 'fail' + (s.errorCode ? ' ' + s.errorCode : '')) },
    ],
    riskyUsers: () => [
      { h: 'User', c: (r) => `<div class="cell-name">${esc(r.user)}</div><div class="cell-sub">${esc(r.upn)}</div>` },
      { h: 'Risk', c: (r) => pill(r.riskLevel) },
      { h: 'State', c: (r) => esc(humanize(r.riskState)) },
      { h: 'Detail', c: (r) => esc(humanize(r.riskDetail)) },
      { h: 'Updated', c: (r) => `<span class="nowrap muted">${r.lastUpdated && !isNaN(r.lastUpdated) ? fmtDate(r.lastUpdated) : '—'}</span>` },
    ],
    riskySignins: () => [
      { h: 'Time (UTC)', c: (s) => `<span class="nowrap">${fmtDate(s.dateTime)}</span>` },
      { h: 'User', c: (s) => `<div class="cell-name">${esc(s.user)}</div><div class="cell-sub">${esc(s.upn)}</div>` },
      { h: 'Source', c: (s) => `${esc(s.ip || '')}<div class="cell-sub">${esc(s.location || '')}</div>` },
      { h: 'Risk', c: (s) => pill(s.riskLevel) },
      { h: 'Detection', c: (s) => esc(humanize(s.riskDetail)) },
    ],
    flagged: () => [
      { h: 'User', c: (u) => `<div class="cell-name">${esc(u.user)}</div><div class="cell-sub">${esc(u.upn)}</div>` },
      { h: 'Severity', c: (u) => pill(u.severity) },
      { h: 'Score', c: (u) => `<b>${u.score}</b>` },
      { h: 'Reasons', c: (u) => u.reasons.map((r) => `<div class="cell-sub">• ${esc(r)}</div>`).join('') },
      { h: 'Last seen', c: (u) => `<span class="nowrap muted">${ago(u.stats.lastSeen)}</span>` },
    ],
    defender: () => [
      { h: 'Time (UTC)', c: (d) => `<span class="nowrap">${fmtDate(d.dateTime)}</span>` },
      { h: 'Type', c: (d) => threatPill(d.threat) },
      { h: 'Subject / sender', c: (d) => `<div class="cell-name">${esc(trunc(d.subject, 50))}</div><div class="cell-sub">${esc(d.sender)}</div>` },
      { h: 'Recipient', c: (d) => esc(d.recipientName || d.recipient) },
      { h: 'Delivery', c: (d) => d.delivered ? pill('high', 'Delivered') : pill('low', esc(d.delivery || 'Blocked')) },
    ],
    audit: () => [
      { h: 'Time (UTC)', c: (a) => `<span class="nowrap">${fmtDate(a.dateTime)}</span>` },
      { h: 'Activity', c: (a) => `<div class="cell-name">${esc(a.activity)}</div><div class="cell-sub">${esc(a.category)}</div>` },
      { h: 'Service', c: (a) => esc(a.service) },
      { h: 'Initiated by', c: (a) => `${esc(a.actor || '')}<div class="cell-sub">${esc(a.ip || '')}</div>` },
      { h: 'Target', c: (a) => esc(a.target || '') },
      { h: 'Result', c: (a) => a.result === 'failure' ? pill('high', 'failure') : pill('low', 'success') },
    ],
    gov: () => [
      { h: 'Time (UTC)', c: (a) => `<span class="nowrap">${fmtDate(a.dateTime)}</span>` },
      { h: 'Activity', c: (a) => esc(a.activity) },
      { h: 'Detail', c: (a) => esc(a.role || a.policy || a.app || a.forwardTo || a.email || a.resource || a.change || a.target || '') },
      { h: 'Initiated by', c: (a) => esc(a.actor || '') },
      { h: 'Result', c: (a) => a.result === 'failure' ? pill('high', 'failure') : pill('low', 'success') },
    ],
    ga: () => [
      { h: 'Member', c: (m) => `<div class="cell-name">${esc(m.member)}</div><div class="cell-sub">${esc(m.upn)}</div>` },
      { h: 'Assignment', c: (m) => esc(m.assignmentType || 'Assigned') },
      { h: 'Assigned', c: (m) => `<span class="nowrap muted">${m.created && !isNaN(m.created) ? fmtDate(m.created) : '—'}</span>` },
    ],
  };

  function dispatchDrill(type, key) {
    if (!key && !type.startsWith('stat:')) return; // chart/row drills require a key
    const S = sigCache;
    const lc = (x) => String(x || '').toLowerCase();
    const unusual = () => (S.unusual || (S.unusual = Analytics.unusualActivity(S.signins)));
    let title, columns, rows;
    switch (type) {
      case 'stat:signins': title = 'All sign-ins'; columns = COLS.signins(); rows = S.signins; break;
      case 'signinOutcome': { const fail = lc(key).startsWith('fail'); title = fail ? 'Failed sign-ins' : 'Successful sign-ins'; columns = COLS.signins(); rows = S.signins.filter((s) => fail ? !s.success : s.success); break; }
      case 'signinDay': title = `Sign-ins on ${key}`; columns = COLS.signins(); rows = S.signins.filter((s) => dayKeyOf(s.dateTime) === key); break;
      case 'signinUser': title = `Sign-ins — ${key}`; columns = COLS.signins(); rows = S.signins.filter((s) => s.upn === key || s.user === key); break;
      case 'stat:legacy': title = 'Legacy authentication attempts'; columns = COLS.signins(); rows = S.signins.filter((s) => s.isLegacy); break;
      case 'legacyProto': title = `Legacy auth — ${key}`; columns = COLS.signins(); rows = S.signins.filter((s) => s.isLegacy && (s.clientApp || 'Unknown') === key); break;
      case 'legacyUser': title = `Legacy auth — ${key}`; columns = COLS.signins(); rows = S.signins.filter((s) => s.isLegacy && (s.user === key || s.upn === key)); break;
      case 'legacyDay': title = `Legacy auth on ${key}`; columns = COLS.signins(); rows = S.signins.filter((s) => s.isLegacy && dayKeyOf(s.dateTime) === key); break;
      case 'stat:riskyUsers': title = 'Risky users'; columns = COLS.riskyUsers(); rows = S.riskyUsers; break;
      case 'riskyUserLevel': title = `Risky users — ${humanize(key)}`; columns = COLS.riskyUsers(); rows = S.riskyUsers.filter((r) => r.riskLevel === lc(key)); break;
      case 'stat:riskySignins': title = 'Risky sign-ins'; columns = COLS.riskySignins(); rows = S.riskySignins; break;
      case 'riskySigninLevel': title = `Risky sign-ins — ${humanize(key)}`; columns = COLS.riskySignins(); rows = S.riskySignins.filter((r) => r.riskLevel === lc(key)); break;
      case 'stat:flagged': title = 'Flagged users (unusual activity)'; columns = COLS.flagged(); rows = unusual(); break;
      case 'stat:defender': title = 'Defender email threats'; columns = COLS.defender(); rows = S.defender; break;
      case 'defenderType': title = `Defender — ${key}`; columns = COLS.defender(); rows = S.defender.filter((d) => d.threat === key); break;
      case 'defenderUser': title = `Defender threats — ${key}`; columns = COLS.defender(); rows = S.defender.filter((d) => (d.recipientName || d.recipient) === key); break;
      case 'defenderDay': title = `Defender threats on ${key}`; columns = COLS.defender(); rows = S.defender.filter((d) => dayKeyOf(d.dateTime) === key); break;
      case 'stat:audit': title = 'Audit events'; columns = COLS.audit(); rows = S.audit; break;
      case 'stat:globalAdmins': title = 'Global administrators'; columns = COLS.ga(); rows = Governance.globalAdmins(state.privRoles); break;
      case 'role': title = `Role members — ${key}`; columns = COLS.ga(); rows = state.privRoles.filter((r) => r.role === key); break;
      case 'stat:priv': title = 'New privileged role assignments'; columns = COLS.gov(); rows = Governance.privilegedAssignments(S.audit); break;
      case 'stat:ca': title = 'Conditional Access changes'; columns = COLS.gov(); rows = Governance.caChanges(S.audit); break;
      case 'stat:sharing': title = 'SharePoint sharing policy changes'; columns = COLS.gov(); rows = Governance.sharingPolicyChanges(S.audit); break;
      case 'stat:external': title = 'New external users'; columns = COLS.gov(); rows = Governance.externalUsers(S.audit); break;
      case 'stat:anon': title = 'Anonymous sharing links'; columns = COLS.gov(); rows = Governance.anonymousLinks(S.audit); break;
      case 'stat:forward': title = 'Mail forwarding rules'; columns = COLS.gov(); rows = Governance.forwardingRules(S.audit); break;
      case 'stat:oauth': title = 'OAuth app consents'; columns = COLS.gov(); rows = Governance.oauthConsents(S.audit); break;
      default: return;
    }
    openDrill(title, columns, rows || []);
  }

  let drillState = null;
  const stripTags = (html) => String(html).replace(/<[^>]*>/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/\s+/g, ' ').trim();

  /* Type-aware comparator: risk rank > numeric > date > text */
  const RANK = { high: 3, medium: 2, low: 1, none: 0 };
  function cmpCell(a, b) {
    const la = a.toLowerCase(), lb = b.toLowerCase();
    if (RANK[la] != null && RANK[lb] != null) return RANK[la] - RANK[lb];
    const na = parseFloat(a.replace(/[,\s]/g, '')), nb = parseFloat(b.replace(/[,\s]/g, ''));
    const aNum = a !== '' && !isNaN(na) && /^[\d.,\s%-]+$/.test(a.trim());
    const bNum = b !== '' && !isNaN(nb) && /^[\d.,\s%-]+$/.test(b.trim());
    if (aNum && bNum) return na - nb;
    const da = Date.parse(a), db = Date.parse(b);
    if (!isNaN(da) && !isNaN(db)) return da - db;
    return a.localeCompare(b);
  }

  function openDrill(title, columns, rows) {
    // Precompute the plain-text cell matrix once for fast filter/sort
    const indexed = rows.map((r) => ({ r, t: columns.map((c) => stripTags(c.c(r))) }));
    drillState = { title, columns, rows, indexed, q: '', colFilters: {}, sort: { idx: -1, dir: 1 }, filtered: rows };
    const o = el('drill');
    o.hidden = false;
    o.innerHTML = `
      <div class="drill-modal" role="dialog" aria-modal="true">
        <div class="drill-head">
          <div><h3>${esc(title)}</h3><span id="drill-count" class="muted"></span></div>
          <div class="drill-actions">
            <div class="search-box sm"><span class="search-icon">⌕</span><input id="drill-q" type="search" placeholder="Search all columns…" autocomplete="off"/></div>
            <button id="drill-clear" class="btn-ghost">Clear</button>
            <button id="drill-csv" class="btn-ghost">Export CSV</button>
            <button id="drill-close" class="btn-ghost" aria-label="Close">✕</button>
          </div>
        </div>
        <div class="drill-body"><table class="tbl drill-tbl">
          <thead>
            <tr>${columns.map((c, i) => `<th class="sortable" data-col="${i}"><span>${esc(c.h)}</span><span class="sort-ind" id="si-${i}"></span></th>`).join('')}</tr>
            <tr class="filter-row">${columns.map((c, i) => `<th><input class="col-filter" data-col="${i}" type="search" placeholder="filter…" autocomplete="off"/></th>`).join('')}</tr>
          </thead>
          <tbody id="drill-tbody"></tbody>
        </table></div>
      </div>`;
    document.body.style.overflow = 'hidden';
    let t;
    el('drill-q').addEventListener('input', (e) => { clearTimeout(t); t = setTimeout(() => { drillState.q = e.target.value; renderDrillRows(); }, 120); });
    o.querySelectorAll('.col-filter').forEach((inp) => {
      let ct; inp.addEventListener('input', () => { clearTimeout(ct); ct = setTimeout(() => { drillState.colFilters[inp.dataset.col] = inp.value; renderDrillRows(); }, 120); });
    });
    o.querySelectorAll('th.sortable').forEach((th) => {
      th.addEventListener('click', () => {
        const idx = +th.dataset.col, s = drillState.sort;
        if (s.idx === idx) s.dir *= -1; else { s.idx = idx; s.dir = 1; }
        renderDrillRows();
      });
    });
    el('drill-clear').addEventListener('click', () => {
      drillState.q = ''; drillState.colFilters = {}; drillState.sort = { idx: -1, dir: 1 };
      el('drill-q').value = '';
      o.querySelectorAll('.col-filter').forEach((i) => { i.value = ''; });
      renderDrillRows();
    });
    el('drill-close').addEventListener('click', closeDrill);
    el('drill-csv').addEventListener('click', () => exportCSV(drillState.title, drillState.columns, drillState.filtered));
    renderDrillRows();
  }

  function renderDrillRows() {
    const d = drillState; if (!d) return;
    const gq = d.q.trim().toLowerCase();
    const active = Object.entries(d.colFilters).filter(([, v]) => v && v.trim()).map(([i, v]) => [+i, v.trim().toLowerCase()]);
    let list = d.indexed;
    if (gq) list = list.filter((x) => x.t.join(' ').toLowerCase().includes(gq));
    if (active.length) list = list.filter((x) => active.every(([i, v]) => x.t[i].toLowerCase().includes(v)));
    const s = d.sort;
    if (s.idx >= 0) list = [...list].sort((a, b) => s.dir * cmpCell(a.t[s.idx], b.t[s.idx]));
    d.filtered = list.map((x) => x.r);
    el('drill-tbody').innerHTML = list.slice(0, 2000).map((x) =>
      '<tr>' + d.columns.map((c) => `<td>${c.c(x.r)}</td>`).join('') + '</tr>').join('') ||
      `<tr><td colspan="${d.columns.length}" class="ch-empty">No matching records</td></tr>`;
    el('drill-count').textContent = `${fmtNum(list.length)} of ${fmtNum(d.rows.length)} records · ${rangeSummary()}`;
    d.columns.forEach((c, i) => { const si = el('si-' + i); if (si) si.textContent = s.idx === i ? (s.dir === 1 ? ' ▲' : ' ▼') : ''; });
  }

  function closeDrill() {
    drillState = null;
    const o = el('drill'); o.hidden = true; o.innerHTML = '';
    document.body.style.overflow = '';
  }

  function exportCSV(title, columns, rows) {
    const esc2 = (v) => `"${String(v).replace(/"/g, '""')}"`;
    const lines = [columns.map((c) => esc2(c.h)).join(',')];
    rows.forEach((r) => lines.push(columns.map((c) => esc2(stripTags(c.c(r)))).join(',')));
    const blob = new Blob([lines.join('\r\n')], { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') + '.csv';
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  /* ---------------------------------------------------------------------- */
  /* Boot                                                                    */
  /* ---------------------------------------------------------------------- */
  document.addEventListener('click', (e) => {
    // Close drill-down when clicking the backdrop
    if (e.target.id === 'drill') { closeDrill(); return; }
    // Drill-down on any element tagged with data-drill (chart segment, stat card, row)
    const drill = e.target.closest('[data-drill]');
    if (drill) {
      const seg = e.target.closest('[data-k]');
      const key = seg && drill.contains(seg) ? seg.dataset.k : (drill.dataset.k || '');
      dispatchDrill(drill.dataset.drill, key);
      return;
    }
    const nav = e.target.closest('[data-view]');
    if (nav) { state.view = nav.dataset.view; render(); window.scrollTo(0, 0); return; }
  });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && drillState) closeDrill(); });

  loadSample().catch(err);
})();
