/* =========================================================================
 * app.js — Show-back security dashboard.
 * Data sources: bundled sample data, uploaded Entra/M365 exports, or a live
 * Azure Log Analytics workspace (KQL).
 * ========================================================================= */
(function () {
  'use strict';

  const state = {
    signins: [], riskySignins: [], riskyUsers: [], audit: [],
    source: 'sample', view: 'overview', loadedAt: null, range: '30d',
  };

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
    const [si, au, ru, rs] = await Promise.all([
      j('signin-logs.json'), j('audit-logs.json'), j('risky-users.json'), j('risky-signins.json'),
    ]);
    state.signins = Parsers.normalizeSignIns(si);
    state.audit = Parsers.normalizeAudit(au);
    state.riskyUsers = Parsers.normalizeRiskyUsers(ru);
    state.riskySignins = Parsers.normalizeRiskySignIns(rs);
    state.source = 'sample';
    finishLoad();
  }

  async function loadFromLogAnalytics(cfg) {
    setStatus('Querying Log Analytics workspace…');
    const data = await LogAnalytics.loadAll(cfg);
    Object.assign(state, data);
    state.source = 'loganalytics';
    state.range = cfg.range;
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
    render();
    setStatus('');
  }

  /* ---------------------------------------------------------------------- */
  /* Shell                                                                   */
  /* ---------------------------------------------------------------------- */
  const NAV = [
    ['overview', 'Overview', '◧'],
    ['signins', 'Sign-in Analytics', '⇲'],
    ['audit', 'Audit Logs', '☰'],
    ['source', 'Data Source', '⛁'],
  ];

  function render() {
    el('nav').innerHTML = NAV.map(([id, label, icon]) =>
      `<button class="nav-item ${state.view === id ? 'active' : ''}" data-view="${id}">
         <span class="nav-icon">${icon}</span>${label}</button>`).join('');
    el('source-badge').innerHTML = sourceBadge();
    const v = state.view;
    const body = el('view');
    if (v === 'overview') body.innerHTML = viewOverview();
    else if (v === 'signins') body.innerHTML = viewSignins();
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
    const s = state.signins;
    const failures = s.filter((x) => !x.success);
    const legacy = s.filter((x) => x.isLegacy);
    const unusual = Analytics.unusualActivity(s);
    const series = Analytics.dailySeries(s, 30);
    const failSeries = Analytics.dailySeries(s, 30, (x) => !x.success);
    const merged = series.map((d, i) => ({ ...d, alert: failSeries[i].value > 12 }));

    return `
      ${header('Security Overview', 'Sign-in & audit posture across Microsoft Entra ID and M365')}
      <div class="grid stats">
        ${stat('Sign-ins', fmtNum(s.length), `${fmtNum(failures.length)} failed`, 'low')}
        ${stat('Risky users', fmtNum(state.riskyUsers.length), countLvl(state.riskyUsers, 'high') + ' high', 'medium')}
        ${stat('Risky sign-ins', fmtNum(state.riskySignins.length), countLvl(state.riskySignins, 'high', 'riskLevel') + ' high', 'medium')}
        ${stat('Legacy auth', fmtNum(legacy.length), pctOf(legacy.length, s.length) + ' of traffic', 'high')}
        ${stat('Flagged users', fmtNum(unusual.length), unusual.filter((u) => u.severity === 'high').length + ' high severity', 'high')}
        ${stat('Audit events', fmtNum(state.audit.length), countAuditFail() + ' failed', 'low')}
      </div>
      <div class="grid cols-2">
        ${card('Sign-in volume — last 30 days', Charts.vbar(merged), 'Red bars mark days with elevated failure counts')}
        ${card('Sign-in outcome', Charts.donut([
          { label: 'Success', value: s.length - failures.length, color: RISK.low },
          { label: 'Failure', value: failures.length, color: RISK.high },
        ], { centerLabel: 'sign-ins' }))}
      </div>
      <div class="grid cols-2">
        ${card('Top flagged users (unusual activity)', topFlaggedMini(unusual))}
        ${card('Sign-in risk levels', Charts.donut(riskBreakdown(state.riskySignins, 'riskLevel'), { centerLabel: 'risky' }))}
      </div>`;
  }

  function topFlaggedMini(unusual) {
    if (!unusual.length) return '<div class="ch-empty">No unusual activity detected</div>';
    return `<div class="mini-list">` + unusual.slice(0, 6).map((u) => `
      <div class="mini-row" data-jump="signins">
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

  /* Widget 1 — Unusual sign-in activity ---------------------------------- */
  function widgetUnusual() {
    const unusual = Analytics.unusualActivity(state.signins);
    const counts = { high: 0, medium: 0, low: 0 };
    unusual.forEach((u) => counts[u.severity]++);
    const cards = unusual.slice(0, 12).map((u) => `
      <div class="flag-card sev-${u.severity}">
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

    return cardWide(
      'Unusual sign-in activity',
      `<div class="widget-summary">
         ${chipCount('High', counts.high, RISK.high)}
         ${chipCount('Medium', counts.medium, RISK.medium)}
         ${chipCount('Low', counts.low, RISK.low)}
         <span class="muted">Behavioural anomaly scoring across ${fmtNum(state.signins.length)} sign-ins</span>
       </div>
       <div class="flag-grid">${cards || '<div class="ch-empty">No anomalies detected</div>'}</div>`,
      'Impossible travel, password spray, off-hours bursts, new geographies, legacy auth & Identity Protection signals'
    );
  }

  /* Widget 2 — Risky users ----------------------------------------------- */
  function widgetRiskyUsers() {
    const u = [...state.riskyUsers].sort((a, b) => lvlRank(b.riskLevel) - lvlRank(a.riskLevel));
    const rows = u.slice(0, 12).map((r) => `
      <tr>
        <td><div class="cell-name">${esc(r.user)}</div><div class="cell-sub">${esc(r.upn)}</div></td>
        <td>${pill(r.riskLevel)}</td>
        <td><span class="state-${esc(r.riskState)}">${esc(humanize(r.riskState))}</span></td>
        <td class="muted nowrap">${r.lastUpdated && !isNaN(r.lastUpdated) ? ago(r.lastUpdated) : '—'}</td>
      </tr>`).join('');
    const chart = Charts.donut(riskBreakdown(u, 'riskLevel'), { centerLabel: 'users', size: 150 });
    return card(`Risky users <span class="count-chip">${u.length}</span>`,
      `<div class="split">${chart}
        <div class="tbl-scroll"><table class="tbl"><thead><tr><th>User</th><th>Risk</th><th>State</th><th>Updated</th></tr></thead>
        <tbody>${rows || emptyRow(4)}</tbody></table></div></div>`,
      'Identity Protection aggregate risk per user');
  }

  /* Widget 3 — Risky sign-ins -------------------------------------------- */
  function widgetRiskySignins() {
    const rs = [...state.riskySignins].sort((a, b) => b.dateTime - a.dateTime);
    const rows = rs.slice(0, 12).map((r) => `
      <tr>
        <td><div class="cell-name">${esc(r.user)}</div><div class="cell-sub">${esc(r.location || r.ip)}</div></td>
        <td>${pill(r.riskLevel)}</td>
        <td class="muted">${esc(humanize(r.riskDetail))}</td>
        <td class="muted nowrap">${ago(r.dateTime)}</td>
      </tr>`).join('');
    const chart = Charts.donut(riskBreakdown(rs, 'riskLevel'), { centerLabel: 'sign-ins', size: 150 });
    return card(`Risky sign-ins <span class="count-chip">${rs.length}</span>`,
      `<div class="split">${chart}
        <div class="tbl-scroll"><table class="tbl"><thead><tr><th>User / source</th><th>Risk</th><th>Detection</th><th>When</th></tr></thead>
        <tbody>${rows || emptyRow(4)}</tbody></table></div></div>`,
      'Sign-ins flagged at-risk by Identity Protection');
  }

  /* Widget 4 — Legacy sign-in attempts ----------------------------------- */
  function widgetLegacy() {
    const legacy = state.signins.filter((s) => s.isLegacy);
    const byProto = Analytics.topBy(legacy, (s) => s.clientApp || 'Unknown', 8);
    const byUser = Analytics.topBy(legacy, (s) => s.user || s.upn, 8)
      .map((d) => ({ ...d, meta: 'legacy attempts' }));
    const series = Analytics.dailySeries(state.signins, 30, (s) => s.isLegacy);
    const failed = legacy.filter((s) => !s.success).length;
    return cardWide(`Legacy authentication attempts`,
      `<div class="widget-summary">
         ${chipCount('Total', legacy.length, RISK.high)}
         ${chipCount('Failed', failed, RISK.medium)}
         ${chipCount('Users', new Set(legacy.map((s) => s.upn)).size, RISK.low)}
         <span class="muted">Legacy protocols bypass modern auth & MFA — block via Conditional Access</span>
       </div>
       <div class="grid cols-3">
         <div class="sub-card"><h4>By protocol</h4>${Charts.hbar(byProto.map((d, i) => ({ ...d, color: Charts.PALETTE[i % Charts.PALETTE.length] })))}</div>
         <div class="sub-card"><h4>Top users</h4>${Charts.hbar(byUser.map((d) => ({ ...d, color: RISK.medium })))}</div>
         <div class="sub-card"><h4>Daily trend</h4>${Charts.vbar(series.map((d) => ({ ...d, color: RISK.high })), { width: 380, height: 180 })}</div>
       </div>`,
      'Detected via client app (IMAP/POP/SMTP/ActiveSync/MAPI) and legacy user agents');
  }

  /* ---------------------------------------------------------------------- */
  /* Audit logs — searchable interface                                       */
  /* ---------------------------------------------------------------------- */
  const auditState = { q: '', service: '', result: '', sort: 'dateTime', dir: -1, page: 0, size: 25 };

  function viewAudit() {
    const services = [...new Set(state.audit.map((a) => a.service).filter(Boolean))].sort();
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
    let rows = state.audit.filter((a) => {
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
          ${Object.entries({ 'Sign-ins': 'signins', 'Risky sign-ins': 'riskySignins', 'Risky users': 'riskyUsers', 'Audit logs': 'audit' })
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
  const kindLabel = (k) => ({ signins: 'Sign-in logs', audit: 'Audit logs', riskyUsers: 'Risky users', riskySignins: 'Risky sign-ins' }[k] || k);

  /* ---------------------------------------------------------------------- */
  /* Small render helpers                                                     */
  /* ---------------------------------------------------------------------- */
  function header(title, sub) { return `<div class="view-head"><h1>${esc(title)}</h1><p>${esc(sub)}</p></div>`; }
  function stat(label, value, sub, level) {
    return `<div class="stat-card">
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

  function setStatus(msg) { const b = el('status'); if (b) { b.textContent = msg; b.style.display = msg ? 'block' : 'none'; } }
  function err(e) { setStatus(''); console.error(e); alert('Error loading data: ' + e.message); }

  /* ---------------------------------------------------------------------- */
  /* Boot                                                                    */
  /* ---------------------------------------------------------------------- */
  document.addEventListener('click', (e) => {
    const nav = e.target.closest('[data-view]');
    if (nav) { state.view = nav.dataset.view; render(); window.scrollTo(0, 0); return; }
    const jump = e.target.closest('[data-jump]');
    if (jump) { state.view = jump.dataset.jump; render(); window.scrollTo(0, 0); }
  });

  loadSample().catch(err);
})();
