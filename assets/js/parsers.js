/* =========================================================================
 * parsers.js — ingest & normalize Microsoft Entra ID (Azure AD) / M365 exports.
 *
 * Supports both JSON (Entra "Download JSON", wraps rows in { value: [...] })
 * and CSV ("Download CSV") exports, and normalizes each record type to a
 * stable internal schema the rest of the app relies on.
 * ========================================================================= */
(function (global) {
  'use strict';

  /* ---- Legacy authentication detection ---------------------------------- */
  const LEGACY_CLIENTS = [
    'exchange activesync', 'imap', 'imap4', 'pop', 'pop3', 'smtp',
    'authenticated smtp', 'mapi', 'mapi over http', 'offline address book',
    'exchange web services', 'exchange online powershell', 'other clients',
    'autodiscover', 'outlook anywhere',
  ];
  const LEGACY_UA = ['bav2ropc', 'ciscoanyconnect', 'python-requests', 'curl', 'wininet'];

  function isLegacyClient(clientApp, userAgent) {
    const c = String(clientApp || '').toLowerCase().trim();
    if (LEGACY_CLIENTS.some((l) => c === l || c.includes(l))) return true;
    const ua = String(userAgent || '').toLowerCase();
    return LEGACY_UA.some((l) => ua.includes(l));
  }

  /* ---- Minimal RFC-4180-ish CSV parser ---------------------------------- */
  function parseCSV(text) {
    const rows = [];
    let row = [], field = '', q = false;
    for (let i = 0; i < text.length; i++) {
      const ch = text[i], next = text[i + 1];
      if (q) {
        if (ch === '"' && next === '"') { field += '"'; i++; }
        else if (ch === '"') q = false;
        else field += ch;
      } else if (ch === '"') q = true;
      else if (ch === ',') { row.push(field); field = ''; }
      else if (ch === '\r') { /* skip */ }
      else if (ch === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
      else field += ch;
    }
    if (field.length || row.length) { row.push(field); rows.push(row); }
    if (!rows.length) return [];
    const header = rows[0].map((h) => h.trim());
    return rows.slice(1).filter((r) => r.length > 1 || (r.length === 1 && r[0] !== ''))
      .map((r) => { const o = {}; header.forEach((h, i) => { o[h] = r[i] ?? ''; }); return o; });
  }

  /* Pull rows out of whatever wrapper the export uses. */
  function rowsFrom(raw) {
    if (Array.isArray(raw)) return raw;
    if (raw && Array.isArray(raw.value)) return raw.value;     // Entra JSON
    if (raw && Array.isArray(raw.records)) return raw.records;  // some M365 exports
    if (typeof raw === 'string') return parseCSV(raw);
    return [];
  }

  /* Case-insensitive multi-key getter for CSV/JSON field variants. */
  function get(o, keys, dflt = '') {
    for (const k of keys) {
      if (o[k] !== undefined && o[k] !== null && o[k] !== '') return o[k];
      const found = Object.keys(o).find((x) => x.toLowerCase() === k.toLowerCase());
      if (found && o[found] !== '' && o[found] != null) return o[found];
    }
    return dflt;
  }

  function locStr(loc) {
    if (!loc) return '';
    if (typeof loc === 'string') return loc;
    return [loc.city, loc.state, loc.countryOrRegion || loc.country].filter(Boolean).join(', ');
  }

  /* ---- Sign-in normalization -------------------------------------------- */
  function normalizeSignIns(raw) {
    return rowsFrom(raw).map((r, idx) => {
      const status = r.status && typeof r.status === 'object' ? r.status : null;
      const errorCode = Number(
        status ? status.errorCode : get(r, ['Sign-in error code', 'errorCode', 'Status'], 0)
      );
      const failureReason = status ? status.failureReason
        : get(r, ['Failure reason', 'failureReason'], '');
      // success if errorCode 0; also handle textual "Success"/"Failure"
      const statusText = String(get(r, ['Status'], '')).toLowerCase();
      const success = status ? errorCode === 0
        : (statusText ? statusText.includes('success') : errorCode === 0);

      const clientApp = get(r, ['clientAppUsed', 'Client app', 'clientApp']);
      const userAgent = get(r, ['userAgent', 'User agent']);
      const loc = r.location || locStr({
        city: get(r, ['City']), state: get(r, ['State/province', 'State']),
        country: get(r, ['Country/region', 'Country']),
      });
      const dt = get(r, ['createdDateTime', 'Date (UTC)', 'Date', 'createdDateTime']);

      return {
        id: get(r, ['id', 'Request ID', 'correlationId'], 's' + idx),
        dateTime: new Date(dt),
        user: get(r, ['userDisplayName', 'User']),
        upn: get(r, ['userPrincipalName', 'Username', 'User principal name']),
        app: get(r, ['appDisplayName', 'Application']),
        ip: get(r, ['ipAddress', 'IP address']),
        location: locStr(loc),
        country: (r.location && (r.location.countryOrRegion || r.location.country)) ||
          get(r, ['Country/region', 'Country']) || lastPart(locStr(loc)),
        clientApp,
        isLegacy: isLegacyClient(clientApp, userAgent),
        userAgent,
        success,
        errorCode,
        failureReason: failureReason || '',
        riskLevel: norm(get(r, ['riskLevelDuringSignIn', 'Risk level during sign-in', 'riskLevelAggregated', 'Risk level'], 'none')),
        riskState: get(r, ['riskState', 'Risk state'], 'none'),
        riskDetail: get(r, ['riskDetail', 'Risk detail'], 'none'),
        device: r.deviceDetail ? (r.deviceDetail.operatingSystem || '') : get(r, ['Operating System']),
        raw: r,
      };
    }).filter((s) => !isNaN(s.dateTime));
  }

  /* ---- Risky users normalization ---------------------------------------- */
  function normalizeRiskyUsers(raw) {
    return rowsFrom(raw).map((r, idx) => ({
      id: get(r, ['id'], 'ru' + idx),
      user: get(r, ['userDisplayName', 'User', 'Risky user']),
      upn: get(r, ['userPrincipalName', 'Username', 'User principal name']),
      riskLevel: norm(get(r, ['riskLevel', 'Risk level'], 'none')),
      riskState: get(r, ['riskState', 'Risk state'], 'atRisk'),
      riskDetail: get(r, ['riskDetail', 'Risk detail'], 'none'),
      lastUpdated: new Date(get(r, ['riskLastUpdatedDateTime', 'Risk last updated', 'Last updated'])),
      raw: r,
    }));
  }

  /* ---- Risky sign-ins normalization (same shape as sign-ins) ------------ */
  function normalizeRiskySignIns(raw) {
    return normalizeSignIns(raw).map((s) => ({ ...s, isRisky: true }));
  }

  /* ---- Audit log normalization ------------------------------------------ */
  function normalizeAudit(raw) {
    return rowsFrom(raw).map((r, idx) => {
      const initiator = r.initiatedBy && (r.initiatedBy.user || r.initiatedBy.app);
      const target = Array.isArray(r.targetResources) ? r.targetResources[0] : null;
      const dt = get(r, ['activityDateTime', 'CreationDate', 'Date', 'Date (UTC)']);
      return {
        id: get(r, ['id', 'Id', 'correlationId'], 'a' + idx),
        dateTime: new Date(dt),
        activity: get(r, ['activityDisplayName', 'Activity', 'Operation', 'Operations']),
        category: get(r, ['category', 'Category']),
        service: get(r, ['loggedByService', 'Service', 'Workload']),
        result: String(get(r, ['result', 'Result', 'ResultStatus', 'Status'], 'success')).toLowerCase(),
        resultReason: get(r, ['resultReason', 'Result reason']),
        actor: initiator ? (initiator.displayName || initiator.userPrincipalName)
          : get(r, ['initiatedBy', 'Initiated by (actor)', 'UserId', 'UserIds', 'User']),
        actorUpn: initiator ? initiator.userPrincipalName : get(r, ['UserId', 'UserIds']),
        ip: initiator ? initiator.ipAddress : get(r, ['ipAddress', 'IP address', 'ClientIP']),
        target: target ? (target.displayName || target.userPrincipalName)
          : get(r, ['Target', 'Target(s)', 'targetResources']),
        targetType: target ? target.type : '',
        correlationId: get(r, ['correlationId']),
        raw: r,
      };
    }).filter((a) => !isNaN(a.dateTime));
  }

  /* ---- Privileged role membership (point-in-time) ----------------------- */
  function normalizePrivilegedRoles(raw) {
    return rowsFrom(raw).map((r, idx) => ({
      id: get(r, ['id'], 'pr' + idx),
      role: get(r, ['roleDisplayName', 'AdditionalProperties.RoleName', 'Role', 'roleName', 'DisplayName']),
      member: get(r, ['principalDisplayName', 'PrincipalDisplayName', 'User', 'AccountDisplayName']),
      upn: get(r, ['principalUserPrincipalName', 'PrincipalUPN', 'AccountUPN', 'userPrincipalName']),
      principalType: get(r, ['principalType', 'PrincipalType'], 'User'),
      assignmentType: get(r, ['assignmentType', 'AssignmentType', 'MemberType'], 'Assigned'),
      created: new Date(get(r, ['createdDateTime', 'CreatedDateTime', 'AssignedDateTime'])),
      raw: r,
    }));
  }

  /* ---- Defender for Office 365 email threats (EmailEvents schema) -------- */
  function normalizeDefender(raw) {
    return rowsFrom(raw).map((r, idx) => {
      const threatRaw = String(get(r, ['ThreatTypes', 'threatType', 'Verdict', 'ThreatType'], '')).toLowerCase();
      const threat = threatRaw.includes('mal') ? 'Malware'
        : threatRaw.includes('phish') ? 'Phish'
        : threatRaw.includes('spam') ? 'Spam' : (threatRaw ? 'Phish' : 'Phish');
      const delivery = get(r, ['DeliveryAction', 'deliveryAction', 'LatestDeliveryAction'], '');
      const sender = get(r, ['SenderFromAddress', 'SenderMailFromAddress', 'sender', 'P1Sender'], '');
      return {
        id: get(r, ['NetworkMessageId', 'id'], 'd' + idx),
        dateTime: new Date(get(r, ['Timestamp', 'TimeGenerated', 'ReceivedTime', 'dateTime'])),
        recipient: get(r, ['RecipientEmailAddress', 'recipient', 'RecipientObjectId']),
        recipientName: get(r, ['RecipientDisplayName', 'recipientName']),
        sender,
        senderDomain: get(r, ['SenderFromDomain', 'senderDomain']) || (sender.split('@')[1] || ''),
        subject: get(r, ['Subject', 'subject']),
        threat,
        malwareFamily: get(r, ['MalwareFamily', 'malwareFamily']),
        detection: get(r, ['DetectionMethods', 'DetectionMethod', 'detection']),
        delivery,
        delivered: /deliver/i.test(delivery),
        severity: norm(get(r, ['Severity', 'severity'], 'medium')) === 'none' ? 'medium' : norm(get(r, ['Severity', 'severity'], 'medium')),
        url: get(r, ['Url', 'Urls', 'url']),
        raw: r,
      };
    }).filter((d) => !isNaN(d.dateTime));
  }

  function norm(v) {
    const s = String(v || 'none').toLowerCase();
    if (s.includes('high')) return 'high';
    if (s.includes('medium')) return 'medium';
    if (s.includes('low')) return 'low';
    if (s.includes('hidden')) return 'hidden';
    return 'none';
  }
  function lastPart(s) { const p = String(s).split(',').map((x) => x.trim()); return p[p.length - 1] || ''; }

  /* ---- Azure Log Analytics (KQL) result conversion ----------------------
   * The Log Analytics REST API returns { tables: [{ name, columns:[{name,type}],
   * rows:[[...]] }] }. We flatten the first table into row objects, parse any
   * `dynamic` columns (JSON strings), then map Log Analytics column names onto
   * the same camelCase keys used by the Entra JSON export so the existing
   * normalizers work unchanged across all three sources.
   */
  const LA_MAP = {
    // shared
    TimeGenerated: { signins: 'createdDateTime', audit: 'activityDateTime', riskyUsers: 'riskLastUpdatedDateTime' },
    // sign-ins (SigninLogs / AADNonInteractiveUserSignInLogs / AADRiskySignIns)
    UserDisplayName: 'userDisplayName', UserPrincipalName: 'userPrincipalName',
    AppDisplayName: 'appDisplayName', IPAddress: 'ipAddress', ClientAppUsed: 'clientAppUsed',
    UserAgent: 'userAgent', LocationDetails: 'location', RiskLevelDuringSignIn: 'riskLevelDuringSignIn',
    RiskLevelAggregated: 'riskLevelAggregated', RiskState: 'riskState', RiskDetail: 'riskDetail',
    CorrelationId: 'correlationId', Id: 'id', DeviceDetail: 'deviceDetail',
    // audit (AuditLogs)
    OperationName: 'activityDisplayName', Category: 'category', LoggedByService: 'loggedByService',
    Result: 'result', ResultReason: 'resultReason', InitiatedBy: 'initiatedBy', TargetResources: 'targetResources',
    OperationType: 'operationType',
    // risky users (AADRiskyUsers)
    RiskLevel: 'riskLevel',
  };

  function fromLogAnalytics(response, kind) {
    const tables = response && (response.tables || (response.Tables));
    if (!tables || !tables.length) return [];
    const t = tables.find((x) => /primaryresult|^table_0$/i.test(x.name || '')) || tables[0];
    const cols = (t.columns || t.Columns).map((c) => c.name || c.ColumnName);
    const rows = t.rows || t.Rows || [];
    return rows.map((row) => {
      const o = {};
      cols.forEach((col, i) => {
        let v = row[i];
        if (typeof v === 'string' && (v.startsWith('{') || v.startsWith('['))) {
          try { v = JSON.parse(v); } catch (_) { /* leave as string */ }
        }
        const mapped = LA_MAP[col];
        const key = typeof mapped === 'object' ? (mapped[kind] || col) : (mapped || col);
        o[key] = v;
      });
      // ResultType is the sign-in error code in Log Analytics (0 = success)
      if (o.ResultType !== undefined && !o.status) {
        o.status = { errorCode: Number(o.ResultType), failureReason: o.ResultDescription || null };
      }
      return o;
    });
  }

  /* Detect record type from a parsed JSON/CSV blob (best-effort). */
  function detectType(raw, filename = '') {
    const f = filename.toLowerCase();
    if (f.includes('defender') || f.includes('email') || f.includes('phish') || f.includes('malware')) return 'defender';
    if (f.includes('priv') || f.includes('role') || f.includes('admin')) return 'privRoles';
    if (f.includes('audit')) return 'audit';
    if (f.includes('risky') && f.includes('user')) return 'riskyUsers';
    if ((f.includes('risky') && f.includes('sign')) || f.includes('risk-sign')) return 'riskySignins';
    if (f.includes('signin') || f.includes('sign-in') || f.includes('sign in')) return 'signins';
    const sample = rowsFrom(raw)[0] || {};
    const keys = Object.keys(sample).map((k) => k.toLowerCase());
    if (keys.some((k) => k.includes('threattypes') || k === 'malwarefamily' || k.includes('deliveryaction'))) return 'defender';
    if (keys.some((k) => k.includes('roledisplayname') || k.includes('principaldisplayname'))) return 'privRoles';
    if (keys.some((k) => k.includes('activitydisplayname') || k === 'operation' || k.includes('loggedbyservice'))) return 'audit';
    if (keys.includes('risklevel') && !keys.some((k) => k.includes('signin') || k.includes('ipaddress'))) return 'riskyUsers';
    if (keys.some((k) => k.includes('signin') || k.includes('clientappused') || k.includes('ipaddress'))) return 'signins';
    return 'signins';
  }

  global.Parsers = {
    parseCSV, rowsFrom, isLegacyClient, fromLogAnalytics,
    normalizeSignIns, normalizeRiskyUsers, normalizeRiskySignIns, normalizeAudit,
    normalizePrivilegedRoles, normalizeDefender,
    detectType,
  };
})(window);
