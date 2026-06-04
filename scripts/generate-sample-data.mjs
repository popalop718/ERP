#!/usr/bin/env node
/**
 * Generates realistic sample data that mirrors the export schemas produced by
 * Microsoft Entra ID (Azure AD) and Microsoft 365:
 *
 *   - Sign-in logs        (Entra ID > Sign-in logs > Download JSON)
 *   - Audit logs          (Entra ID / M365 unified audit log)
 *   - Risky users         (Entra ID Protection > Risky users)
 *   - Risky sign-ins      (Entra ID Protection > Risky sign-ins)
 *
 * The generated data deliberately contains anomalies (impossible travel,
 * password spray, legacy-auth bursts, risky users) so every widget on the
 * dashboard has something meaningful to show out of the box.
 *
 * Run:  node scripts/generate-sample-data.mjs
 */
import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, '..', 'data');
mkdirSync(OUT, { recursive: true });

// ---------------------------------------------------------------------------
// Deterministic PRNG so regenerating produces stable, review-friendly diffs.
// ---------------------------------------------------------------------------
let seed = 1337;
const rng = () => {
  seed = (seed * 1664525 + 1013904223) % 4294967296;
  return seed / 4294967296;
};
const pick = (arr) => arr[Math.floor(rng() * arr.length)];
const int = (min, max) => Math.floor(rng() * (max - min + 1)) + min;
const chance = (p) => rng() < p;

// ---------------------------------------------------------------------------
// Reference data
// ---------------------------------------------------------------------------
const DOMAIN = 'contoso.com';
const USERS = [
  'Amelia Hughes', 'Noah Patterson', 'Olivia Chen', 'Liam Okafor',
  'Sophia Rossi', 'Mason Delgado', 'Isabella Novak', 'Ethan Brooks',
  'Mia Andersson', 'Lucas Fernandez', 'Charlotte Kim', 'Henry Walsh',
  'Evelyn Tanaka', 'Jack Morrison', 'Harper Singh', 'Daniel Costa',
  'Grace O\'Brien', 'Samuel Adeyemi', 'Chloe Dubois', 'Benjamin Ivanov',
];
const upn = (name) =>
  name.toLowerCase().replace(/[^a-z]/g, '.').replace(/\.+/g, '.').replace(/^\.|\.$/g, '') + '@' + DOMAIN;

const GEO = [
  { city: 'Seattle', state: 'Washington', country: 'US', cc: 'US', ipPrefix: '13.64', tz: -8 },
  { city: 'New York', state: 'New York', country: 'US', cc: 'US', ipPrefix: '20.42', tz: -5 },
  { city: 'London', state: 'England', country: 'GB', cc: 'GB', ipPrefix: '51.140', tz: 0 },
  { city: 'Dublin', state: 'Leinster', country: 'IE', cc: 'IE', ipPrefix: '40.115', tz: 0 },
  { city: 'Amsterdam', state: 'North Holland', country: 'NL', cc: 'NL', ipPrefix: '20.86', tz: 1 },
];
// "Threat" geos used for impossible travel / risky sign-ins
const THREAT_GEO = [
  { city: 'Lagos', state: 'Lagos', country: 'NG', cc: 'NG', ipPrefix: '197.210', tz: 1 },
  { city: 'Moscow', state: 'Moscow', country: 'RU', cc: 'RU', ipPrefix: '95.165', tz: 3 },
  { city: 'Shenzhen', state: 'Guangdong', country: 'CN', cc: 'CN', ipPrefix: '120.234', tz: 8 },
  { city: 'São Paulo', state: 'São Paulo', country: 'BR', cc: 'BR', ipPrefix: '177.135', tz: -3 },
];
const ip = (g) => `${g.ipPrefix}.${int(0, 255)}.${int(1, 254)}`;

const MODERN_CLIENTS = ['Browser', 'Mobile Apps and Desktop clients'];
const LEGACY_CLIENTS = [
  'IMAP4', 'POP3', 'Authenticated SMTP', 'Exchange ActiveSync',
  'MAPI Over HTTP', 'Exchange Web Services', 'Other clients',
];
const APPS = [
  'Microsoft 365', 'Office 365 Exchange Online', 'Microsoft Teams',
  'SharePoint Online', 'Azure Portal', 'OneDrive', 'Power BI',
  'Microsoft Authenticator App',
];
// Modern user agents only — legacy UAs (BAV2ROPC, python-requests) are
// assigned explicitly to legacy/attack traffic so detection stays meaningful.
const USER_AGENTS = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15',
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)',
];

// Sign-in error codes (Entra ID) -> failureReason
const FAILURES = [
  [50126, 'Invalid username or password.'],
  [50053, 'Account is locked because the user tried to sign in too many times with an incorrect ID or password.'],
  [50055, 'The password is expired.'],
  [50074, 'Strong Authentication is required.'],
  [53003, 'Access blocked by Conditional Access policy.'],
  [50058, 'Session information is not sufficient for single-sign-on.'],
];

const iso = (d) => new Date(d).toISOString();
let _id = 0;
const guid = () => {
  _id++;
  const h = (n) => n.toString(16).padStart(2, '0');
  return `${h(_id & 255)}${h((_id >> 8) & 255)}f3a1-7b2c-4d9e-9a1f-${h(_id)}b2c3d4e5f6`.slice(0, 36);
};

// ---------------------------------------------------------------------------
// Sign-in log record (Entra ID JSON schema)
// ---------------------------------------------------------------------------
function signIn({ name, when, geo, client, success, errorCode, failureReason, riskLevel, riskState, ua }) {
  const g = geo;
  return {
    id: guid(),
    createdDateTime: iso(when),
    userDisplayName: name,
    userPrincipalName: upn(name),
    userId: guid(),
    appDisplayName: pick(APPS),
    appId: guid(),
    ipAddress: ip(g),
    clientAppUsed: client,
    isInteractive: client === 'Browser',
    userAgent: ua || pick(USER_AGENTS),
    correlationId: guid(),
    conditionalAccessStatus: success ? 'success' : (errorCode === 53003 ? 'failure' : 'notApplied'),
    location: { city: g.city, state: g.state, countryOrRegion: g.cc },
    deviceDetail: {
      deviceId: chance(0.6) ? guid() : '',
      operatingSystem: pick(['Windows 10', 'Windows 11', 'macOS', 'iOS', 'Android', 'Linux']),
      browser: pick(['Edge 124.0', 'Chrome 125.0', 'Safari 17.4', 'Firefox 126.0', '']),
      isCompliant: chance(0.7),
      isManaged: chance(0.65),
    },
    status: {
      errorCode: success ? 0 : errorCode,
      failureReason: success ? null : failureReason,
      additionalDetails: success ? 'MFA requirement satisfied by claim in the token' : null,
    },
    riskLevelDuringSignIn: riskLevel || 'none',
    riskState: riskState || 'none',
    riskDetail: riskLevel && riskLevel !== 'none' ? pick([
      'unfamiliarFeatures', 'anonymizedIPAddress', 'maliciousIPAddress',
      'unlikelyTravel', 'newCountry', 'impossibleTravel',
    ]) : 'none',
    authenticationRequirement: success && chance(0.8) ? 'multiFactorAuthentication' : 'singleFactorAuthentication',
  };
}

// ---------------------------------------------------------------------------
// Build a 30-day window of sign-ins
// ---------------------------------------------------------------------------
const NOW = new Date('2026-06-04T09:00:00Z').getTime();
const DAY = 86400000;
const signins = [];

// Each user has a "home" geo and normal working pattern.
const home = {};
for (const u of USERS) home[u] = pick(GEO);

// Normal day-to-day traffic
for (let d = 30; d >= 0; d--) {
  const dayStart = NOW - d * DAY;
  for (const name of USERS) {
    const sessions = int(2, 9);
    for (let s = 0; s < sessions; s++) {
      const hour = int(7, 19); // working hours, mostly
      const when = dayStart + hour * 3600000 + int(0, 3599) * 1000;
      const fail = chance(0.06);
      const [ec, fr] = fail ? pick(FAILURES) : [0, null];
      // Identity Protection occasionally flags low/medium risk on normal traffic
      const flagged = chance(0.03);
      signins.push(signIn({
        name, when, geo: home[name], client: pick(MODERN_CLIENTS),
        success: !fail, errorCode: ec, failureReason: fr,
        riskLevel: flagged ? pick(['low', 'low', 'medium']) : 'none',
        riskState: flagged ? 'atRisk' : 'none',
      }));
    }
  }
}

// --- Anomaly 1: Impossible travel for two users -----------------------------
for (const name of ['Olivia Chen', 'Henry Walsh']) {
  const day = NOW - int(1, 6) * DAY;
  signins.push(signIn({ name, when: day + 9 * 3600000, geo: home[name], client: 'Browser', success: true }));
  // Sign-in from a far away threat geo ~40 min later
  signins.push(signIn({
    name, when: day + 9 * 3600000 + 40 * 60000, geo: pick(THREAT_GEO),
    client: 'Browser', success: true, riskLevel: 'high', riskState: 'atRisk',
  }));
}

// --- Anomaly 2: Password spray / brute force against one account ------------
{
  const name = 'Samuel Adeyemi';
  const day = NOW - 2 * DAY;
  for (let i = 0; i < 28; i++) {
    const [ec, fr] = [50126, 'Invalid username or password.'];
    signins.push(signIn({
      name, when: day + 2 * 3600000 + i * 90000, geo: pick(THREAT_GEO),
      client: 'Authenticated SMTP', success: false, errorCode: ec, failureReason: fr,
      ua: 'python-requests/2.31.0',
    }));
  }
  // followed by one success (account takeover)
  signins.push(signIn({
    name, when: day + 2 * 3600000 + 30 * 90000, geo: THREAT_GEO[0],
    client: 'Authenticated SMTP', success: true, riskLevel: 'high', riskState: 'atRisk',
    ua: 'python-requests/2.31.0',
  }));
}

// --- Anomaly 3: Legacy-auth heavy users ------------------------------------
for (const name of ['Mason Delgado', 'Grace O\'Brien', 'Benjamin Ivanov']) {
  for (let d = 14; d >= 0; d--) {
    const day = NOW - d * DAY;
    const attempts = int(4, 12);
    for (let i = 0; i < attempts; i++) {
      const fail = chance(0.4);
      const [ec, fr] = fail ? [50126, 'Invalid username or password.'] : [0, null];
      signins.push(signIn({
        name, when: day + int(0, 23) * 3600000 + int(0, 59) * 60000,
        geo: home[name], client: pick(LEGACY_CLIENTS), success: !fail,
        errorCode: ec, failureReason: fr, ua: 'BAV2ROPC',
      }));
    }
  }
}

// --- Anomaly 4: Off-hours burst for a normal user --------------------------
{
  const name = 'Mia Andersson';
  const day = NOW - 3 * DAY;
  for (let i = 0; i < 12; i++) {
    signins.push(signIn({
      name, when: day + 2 * 3600000 + i * 7 * 60000, geo: pick(THREAT_GEO),
      client: 'Browser', success: chance(0.5) ? true : false,
      errorCode: 50126, failureReason: 'Invalid username or password.',
      riskLevel: chance(0.5) ? 'medium' : 'none',
    }));
  }
}

signins.sort((a, b) => new Date(b.createdDateTime) - new Date(a.createdDateTime));

// ---------------------------------------------------------------------------
// Risky sign-ins  (subset flagged by Identity Protection)
// ---------------------------------------------------------------------------
const riskySignins = signins
  .filter((s) => s.riskLevelDuringSignIn !== 'none' || s.riskState === 'atRisk')
  .map((s) => ({
    id: s.id,
    createdDateTime: s.createdDateTime,
    userDisplayName: s.userDisplayName,
    userPrincipalName: s.userPrincipalName,
    ipAddress: s.ipAddress,
    appDisplayName: s.appDisplayName,
    clientAppUsed: s.clientAppUsed,
    location: s.location,
    riskLevelDuringSignIn: s.riskLevelDuringSignIn,
    riskLevelAggregated: s.riskLevelDuringSignIn,
    riskState: s.riskState === 'none' ? 'atRisk' : s.riskState,
    riskDetail: s.riskDetail,
    riskEventTypes: [s.riskDetail].filter((x) => x && x !== 'none'),
    status: s.status,
  }));

// ---------------------------------------------------------------------------
// Risky users  (Identity Protection aggregate)
// ---------------------------------------------------------------------------
const confirmedCompromised = new Set(['Samuel Adeyemi']);
const riskyUserNames = new Set([
  'Olivia Chen', 'Henry Walsh', 'Samuel Adeyemi', 'Mia Andersson',
  ...riskySignins.map((s) => s.userDisplayName),
]);
const riskyUsers = [...riskyUserNames].map((name) => {
  const userSignins = riskySignins.filter((s) => s.userDisplayName === name);
  const levels = userSignins.map((s) => s.riskLevelDuringSignIn);
  const level = levels.includes('high') ? 'high' : levels.includes('medium') ? 'medium' : 'low';
  return {
    id: guid(),
    userDisplayName: name,
    userPrincipalName: upn(name),
    riskLevel: level,
    riskState: confirmedCompromised.has(name) ? 'confirmedCompromised' : 'atRisk',
    riskDetail: pick(['none', 'userPerformedSecuredPasswordReset', 'adminConfirmedUserCompromised']),
    riskLastUpdatedDateTime: userSignins[0] ? userSignins[0].createdDateTime : iso(NOW),
    isProcessing: false,
    isDeleted: false,
  };
});

// ---------------------------------------------------------------------------
// Audit logs  (Entra ID / M365 unified audit log schema)
// ---------------------------------------------------------------------------
// General background activity for the audit-log view. Governance-specific
// operations (role/CA/consent/forwarding/sharing) are generated separately
// below with proper detail so their widgets show well-formed events.
const AUDIT_ACTIVITIES = [
  ['Add user', 'UserManagement', 'Core Directory'],
  ['Delete user', 'UserManagement', 'Core Directory'],
  ['Update user', 'UserManagement', 'Core Directory'],
  ['Reset user password', 'UserManagement', 'Core Directory'],
  ['Add group', 'GroupManagement', 'Core Directory'],
  ['Update group', 'GroupManagement', 'Core Directory'],
  ['Add service principal', 'ApplicationManagement', 'Core Directory'],
  ['Disable Strong Authentication', 'UserManagement', 'Authentication Methods'],
  ['Register security info', 'UserManagement', 'Authentication Methods'],
  ['FileDownloaded', 'SharePoint', 'SharePoint'],
  ['FileDeleted', 'SharePoint', 'SharePoint'],
  ['MailItemsAccessed', 'Exchange', 'Exchange Online'],
  ['Add-MailboxPermission', 'Exchange', 'Exchange Online'],
  ['UserLoggedIn', 'AzureActiveDirectory', 'AAD'],
];

const audit = [];
for (let i = 0; i < 600; i++) {
  const [activity, category, service] = pick(AUDIT_ACTIVITIES);
  const actor = pick(USERS);
  const target = pick(USERS);
  const when = NOW - int(0, 30) * DAY - int(0, 23) * 3600000 - int(0, 59) * 60000;
  const failed = chance(0.08);
  const g = chance(0.85) ? pick(GEO) : pick(THREAT_GEO);
  audit.push({
    id: guid(),
    activityDateTime: iso(when),
    activityDisplayName: activity,
    category,
    loggedByService: service,
    operationType: activity.startsWith('Add') ? 'Add' : activity.startsWith('Delete') || activity.startsWith('Remove') ? 'Delete' : 'Update',
    result: failed ? 'failure' : 'success',
    resultReason: failed ? 'Insufficient privileges to complete the operation.' : '',
    correlationId: guid(),
    initiatedBy: {
      user: {
        id: guid(),
        displayName: actor,
        userPrincipalName: upn(actor),
        ipAddress: ip(g),
      },
    },
    targetResources: [
      {
        id: guid(),
        displayName: target,
        type: 'User',
        userPrincipalName: upn(target),
      },
    ],
    additionalDetails: [{ key: 'User-Agent', value: pick(USER_AGENTS) }],
  });
}

// A few high-signal audit events tied to the compromised account
{
  const name = 'Samuel Adeyemi';
  const base = NOW - 2 * DAY + 3 * 3600000;
  audit.push({
    id: guid(), activityDateTime: iso(base),
    activityDisplayName: 'New-InboxRule', category: 'Exchange', loggedByService: 'Exchange Online',
    operationType: 'Add', result: 'success', resultReason: '',
    correlationId: guid(),
    initiatedBy: { user: { id: guid(), displayName: name, userPrincipalName: upn(name), ipAddress: ip(THREAT_GEO[0]) } },
    targetResources: [{ id: guid(), displayName: 'Forward all to external', type: 'InboxRule' }],
    additionalDetails: [{ key: 'Parameters', value: 'ForwardTo: attacker@external-mail.io; DeleteMessage: true' }],
  });
  audit.push({
    id: guid(), activityDateTime: iso(base + 600000),
    activityDisplayName: 'Add app role assignment to service principal', category: 'ApplicationManagement',
    loggedByService: 'Core Directory', operationType: 'Add', result: 'success', resultReason: '',
    correlationId: guid(),
    initiatedBy: { user: { id: guid(), displayName: name, userPrincipalName: upn(name), ipAddress: ip(THREAT_GEO[0]) } },
    targetResources: [{ id: guid(), displayName: 'Mail.ReadWrite (Application)', type: 'ServicePrincipal' }],
    additionalDetails: [{ key: 'User-Agent', value: 'python-requests/2.31.0' }],
  });
}

// ===========================================================================
// Governance & threat events (components 1–9)
// ===========================================================================
const recent = () => NOW - int(0, 30) * DAY - int(0, 23) * 3600000 - int(0, 59) * 60000;
let govSeq = 0;
function govAudit({ activity, category, service, when, actor, result = 'success', targetResources = [], extra = {} }) {
  govSeq++;
  const a = actor || pick(USERS);
  const g = chance(0.8) ? pick(GEO) : pick(THREAT_GEO);
  return {
    id: guid(),
    activityDateTime: iso(when != null ? when : recent()),
    activityDisplayName: activity,
    category,
    loggedByService: service,
    operationType: activity.startsWith('Add') || activity.startsWith('Consent') || activity.startsWith('New') || activity.includes('Created') ? 'Add'
      : activity.startsWith('Remove') || activity.startsWith('Delete') ? 'Delete' : 'Update',
    result,
    resultReason: result === 'failure' ? 'Insufficient privileges to complete the operation.' : '',
    correlationId: guid(),
    initiatedBy: { user: { id: guid(), displayName: a, userPrincipalName: upn(a), ipAddress: ip(g) } },
    targetResources,
    additionalDetails: [{ key: 'User-Agent', value: pick(USER_AGENTS) }],
    ...extra,
  };
}

// --- Component 1: Privileged role inventory (point-in-time membership) ------
const PRIV_ROLES = [
  'Global Administrator', 'Privileged Role Administrator', 'Security Administrator',
  'Exchange Administrator', 'SharePoint Administrator', 'User Administrator',
  'Conditional Access Administrator', 'Application Administrator', 'Helpdesk Administrator',
];
const privRoles = [];
const usedForRole = {};
function assignRole(role, n) {
  usedForRole[role] = new Set();
  for (let i = 0; i < n; i++) {
    let m; let guard = 0;
    do { m = pick(USERS); guard++; } while (usedForRole[role].has(m) && guard < 50);
    usedForRole[role].add(m);
    privRoles.push({
      id: guid(), roleDisplayName: role, roleTemplateId: guid(),
      principalDisplayName: m, principalUserPrincipalName: upn(m), principalType: 'User',
      assignmentType: chance(0.65) ? 'Assigned' : 'Eligible',
      directoryScopeId: '/',
      createdDateTime: iso(NOW - int(20, 900) * DAY),
    });
  }
}
assignRole('Global Administrator', 7);      // intentionally high → flag
assignRole('Privileged Role Administrator', 2);
assignRole('Security Administrator', 3);
assignRole('Exchange Administrator', 3);
assignRole('SharePoint Administrator', 2);
assignRole('User Administrator', 4);
assignRole('Conditional Access Administrator', 2);
assignRole('Application Administrator', 2);
assignRole('Helpdesk Administrator', 5);

// --- Component 2: New privileged role assignments (+ Global Admin changes) --
for (let i = 0; i < 16; i++) {
  const role = pick(PRIV_ROLES);
  const member = pick(USERS);
  audit.push(govAudit({
    activity: 'Add member to role', category: 'RoleManagement', service: 'Core Directory',
    targetResources: [
      { id: guid(), displayName: member, type: 'User', userPrincipalName: upn(member) },
      { id: guid(), displayName: role, type: 'Role',
        modifiedProperties: [{ displayName: 'Role.DisplayName', oldValue: null, newValue: `"${role}"` }] },
    ],
    extra: { role, member },
  }));
}
// A couple of Global Administrator elevations, one very recent + tied to attacker
for (let i = 0; i < 2; i++) {
  const member = pick(USERS);
  audit.push(govAudit({
    activity: 'Add member to role', category: 'RoleManagement', service: 'Core Directory',
    when: NOW - int(0, 4) * DAY,
    targetResources: [
      { id: guid(), displayName: member, type: 'User', userPrincipalName: upn(member) },
      { id: guid(), displayName: 'Global Administrator', type: 'Role' },
    ],
    extra: { role: 'Global Administrator', member },
  }));
}
audit.push(govAudit({
  activity: 'Add member to role', category: 'RoleManagement', service: 'Core Directory',
  when: NOW - 2 * DAY + 3.3 * 3600000, actor: 'Samuel Adeyemi',
  targetResources: [
    { id: guid(), displayName: 'Samuel Adeyemi', type: 'User', userPrincipalName: upn('Samuel Adeyemi') },
    { id: guid(), displayName: 'Global Administrator', type: 'Role' },
  ],
  extra: { role: 'Global Administrator', member: 'Samuel Adeyemi' },
}));
// a few removals
for (let i = 0; i < 4; i++) {
  const role = pick(PRIV_ROLES); const member = pick(USERS);
  audit.push(govAudit({
    activity: 'Remove member from role', category: 'RoleManagement', service: 'Core Directory',
    targetResources: [{ id: guid(), displayName: member, type: 'User', userPrincipalName: upn(member) }, { id: guid(), displayName: role, type: 'Role' }],
    extra: { role, member },
  }));
}

// --- Component 3: Conditional Access changes -------------------------------
const CA_POLICIES = ['Require MFA for all users', 'Block legacy authentication', 'Require compliant device',
  'Require MFA for admins', 'Block access from unsupported countries', 'Session controls - SharePoint'];
['Add conditional access policy', 'Update conditional access policy', 'Delete conditional access policy']
  .forEach((act) => {
    const n = act.startsWith('Update') ? 6 : 2;
    for (let i = 0; i < n; i++) {
      const policy = pick(CA_POLICIES);
      audit.push(govAudit({
        activity: act, category: 'Policy', service: 'Conditional Access',
        targetResources: [{ id: guid(), displayName: policy, type: 'Policy' }],
        extra: { policyName: policy },
      }));
    }
  });
// suspicious: attacker weakens a policy
audit.push(govAudit({
  activity: 'Update conditional access policy', category: 'Policy', service: 'Conditional Access',
  when: NOW - 2 * DAY + 3.5 * 3600000, actor: 'Samuel Adeyemi',
  targetResources: [{ id: guid(), displayName: 'Require MFA for all users', type: 'Policy' }],
  extra: { policyName: 'Require MFA for all users', change: 'State: enabled → disabled' },
}));

// --- Component 4: SharePoint sharing policy changes ------------------------
const SHARE_POLICY = [
  ['SharingPolicyChanged', 'External sharing set to "Anyone (anonymous)"'],
  ['Set-SPOTenant', 'DefaultSharingLinkType → AnonymousAccess'],
  ['Sharing policy changed', 'Allow guests to share items they don\'t own = true'],
  ['SharingPolicyChanged', 'Domain allow-list removed'],
];
for (let i = 0; i < 7; i++) {
  const [act, detail] = pick(SHARE_POLICY);
  audit.push(govAudit({
    activity: act, category: 'SharePoint', service: 'SharePoint',
    targetResources: [{ id: guid(), displayName: 'Tenant sharing settings', type: 'Site' }],
    extra: { policyChange: detail },
  }));
}

// --- Component 5: New external (guest) users -------------------------------
const EXT_DOMAINS = ['partner-corp.com', 'gmail.com', 'contractor.io', 'outlook.com', 'acme-vendor.net'];
for (let i = 0; i < 12; i++) {
  const dom = pick(EXT_DOMAINS);
  const first = pick(['alex', 'sam', 'jordan', 'taylor', 'morgan', 'casey', 'riley', 'jamie']);
  const ext = `${first}_${dom.replace(/\./g, '_')}#EXT#@${DOMAIN.replace('.com', '.onmicrosoft.com')}`;
  audit.push(govAudit({
    activity: 'Invite external user', category: 'UserManagement', service: 'Core Directory',
    targetResources: [{ id: guid(), displayName: `${first}@${dom}`, type: 'User', userPrincipalName: ext }],
    extra: { external: true, externalEmail: `${first}@${dom}`, invitedAs: ext },
  }));
}

// --- Component 6: Anonymous sharing links created --------------------------
const FILES = ['Q3-Financials.xlsx', 'Board Deck.pptx', 'Customer List.csv', 'Salaries.xlsx',
  'Roadmap.docx', 'Contract-Acme.pdf', 'Source-Backup.zip', 'Passwords.txt'];
for (let i = 0; i < 17; i++) {
  const file = pick(FILES);
  audit.push(govAudit({
    activity: 'AnonymousLinkCreated', category: 'SharePoint', service: chance(0.5) ? 'SharePoint' : 'OneDrive',
    targetResources: [{ id: guid(), displayName: file, type: 'File' }],
    extra: { resource: file, linkType: chance(0.4) ? 'Edit' : 'View' },
  }));
}

// --- Component 7: Mail forwarding rules ------------------------------------
for (let i = 0; i < 9; i++) {
  const external = chance(0.55);
  const fwd = external ? `${pick(['archive', 'backup', 'copy', 'me'])}@${pick(EXT_DOMAINS)}` : upn(pick(USERS));
  audit.push(govAudit({
    activity: chance(0.7) ? 'New-InboxRule' : 'Set-Mailbox', category: 'Exchange', service: 'Exchange Online',
    targetResources: [{ id: guid(), displayName: external ? 'Forward to external' : 'Forward internal', type: 'InboxRule' }],
    extra: { forwardTo: fwd, forwardExternal: external },
  }));
}

// --- Component 8: OAuth app consents ---------------------------------------
const OAUTH_APPS = [
  ['Mailbox Sync Pro', ['Mail.ReadWrite', 'offline_access'], true],
  ['PDF Converter', ['Files.ReadWrite.All', 'User.Read'], true],
  ['Calendar Buddy', ['Calendars.ReadWrite'], false],
  ['em Client', ['Mail.Read', 'offline_access'], false],
  ['Analytics Connector', ['Directory.Read.All', 'User.Read.All'], true],
  ['Backup Tool', ['full_access_as_app'], true],
  ['Survey App', ['User.Read'], false],
];
for (let i = 0; i < 13; i++) {
  const [app, perms, risky] = pick(OAUTH_APPS);
  const adminConsent = chance(0.4);
  audit.push(govAudit({
    activity: chance(0.6) ? 'Consent to application' : 'Add app role assignment to service principal',
    category: 'ApplicationManagement', service: 'Core Directory',
    targetResources: [{ id: guid(), displayName: app, type: 'ServicePrincipal' }],
    extra: { appName: app, permissions: perms, riskyConsent: risky, consentType: adminConsent ? 'AllPrincipals (admin)' : 'Principal (user)' },
  }));
}

audit.sort((a, b) => new Date(b.activityDateTime) - new Date(a.activityDateTime));

// ===========================================================================
// Component 9: Microsoft Defender for Office 365 — phishing / malware events
// (mirrors the EmailEvents advanced-hunting schema)
// ===========================================================================
const MALWARE_FAMILIES = ['Emotet', 'AgentTesla', 'Qakbot', 'TrickBot', 'IcedID', 'Formbook'];
const PHISH_SUBJECTS = [
  'Action required: verify your account', 'Your password will expire today',
  'Unusual sign-in activity detected', 'Invoice #INV-{n} is overdue',
  'You have a new voicemail', 'Shared document: Q3 Budget', 'DocuSign: please review and sign',
  'Microsoft 365: storage almost full', 'HR: updated payroll information',
];
const SPAM_SUBJECTS = ['You won a $1000 gift card', 'Limited time offer', 'Meet singles in your area', 'Crypto investment opportunity'];
const LOOKALIKE = ['micros0ft-support.com', 'office365-billing.net', 'secure-docusign.co', 'paypaI.com', 'amaz0n-orders.com', 'm365-login.help'];
const DELIVERY = ['Blocked', 'Quarantined', 'Junked', 'Delivered'];
const defender = [];
for (let d = 30; d >= 0; d--) {
  const dayStart = NOW - d * DAY;
  // baseline volume with a phishing-campaign spike 5–7 days ago
  const spike = d >= 5 && d <= 7;
  const count = spike ? int(70, 120) : int(8, 26);
  for (let i = 0; i < count; i++) {
    const r = rng();
    const threat = spike ? (r < 0.8 ? 'Phish' : r < 0.95 ? 'Malware' : 'Spam')
      : (r < 0.45 ? 'Phish' : r < 0.72 ? 'Malware' : 'Spam');
    const recipient = pick(USERS);
    const when = dayStart + int(0, 23) * 3600000 + int(0, 59) * 60000;
    const delivered = chance(threat === 'Spam' ? 0.25 : 0.12);
    const senderDomain = threat === 'Phish' ? pick(LOOKALIKE) : `${pick(['mail', 'smtp', 'mx'])}.${pick(['sendgrid.net', 'mailgun.org', 'unknown-host.ru', 'bulk-sender.cn'])}`;
    defender.push({
      Timestamp: iso(when),
      RecipientEmailAddress: upn(recipient),
      RecipientDisplayName: recipient,
      SenderFromAddress: `${pick(['no-reply', 'support', 'billing', 'admin', 'alert'])}@${senderDomain}`,
      SenderDisplayName: pick(['Microsoft', 'IT Support', 'DocuSign', 'Payroll', 'Account Team', 'HR']),
      Subject: (threat === 'Spam' ? pick(SPAM_SUBJECTS) : pick(PHISH_SUBJECTS)).replace('{n}', String(int(1000, 9999))),
      ThreatTypes: threat,
      MalwareFamily: threat === 'Malware' ? pick(MALWARE_FAMILIES) : '',
      DetectionMethods: threat === 'Phish' ? pick(['URL detonation reputation', 'Spoof intra-org', 'Impersonation domain', 'Anti-phishing policy'])
        : threat === 'Malware' ? pick(['Safe Attachments detonation', 'Anti-malware engine', 'File reputation']) : 'Anti-spam',
      DeliveryAction: delivered ? 'Delivered' : pick(DELIVERY.slice(0, 3)),
      Severity: threat === 'Malware' ? 'High' : threat === 'Phish' ? pick(['High', 'Medium']) : 'Low',
      Url: threat === 'Phish' ? `https://${senderDomain}/login` : '',
    });
  }
}
defender.sort((a, b) => new Date(b.Timestamp) - new Date(a.Timestamp));

// ---------------------------------------------------------------------------
// Write (Entra exports wrap rows in a top-level "value" array)
// ---------------------------------------------------------------------------
const write = (file, value) => {
  writeFileSync(join(OUT, file), JSON.stringify({ value }, null, 2));
  console.log(`  ${file.padEnd(24)} ${value.length} records`);
};

console.log('Generating sample data ->', OUT);
write('signin-logs.json', signins);
write('audit-logs.json', audit);
write('risky-users.json', riskyUsers);
write('risky-signins.json', riskySignins);
write('privileged-roles.json', privRoles);
write('defender-events.json', defender);
console.log('Done.');
