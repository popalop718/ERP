/* =========================================================================
 * governance.js — identity-governance & threat classification over audit logs.
 *
 * Classifies normalized audit records into the dashboard's governance
 * components and extracts the salient detail for each (role, app permissions,
 * forwarding target, sharing policy, etc). Classification keys off the
 * operation name + service (stable across Entra JSON, CSV and Log Analytics);
 * detail extraction reads the raw event with several fallbacks.
 * ========================================================================= */
(function (global) {
  'use strict';

  const lc = (s) => String(s || '').toLowerCase();

  const PRIVILEGED_ROLES = new Set([
    'global administrator', 'privileged role administrator', 'privileged authentication administrator',
    'security administrator', 'exchange administrator', 'sharepoint administrator',
    'user administrator', 'conditional access administrator', 'application administrator',
    'cloud application administrator', 'helpdesk administrator', 'authentication administrator',
    'intune administrator', 'billing administrator', 'teams administrator', 'global reader',
  ]);

  /* ---- raw-event extraction helpers ------------------------------------- */
  const targets = (a) => (a.raw && Array.isArray(a.raw.targetResources) ? a.raw.targetResources : []);
  const detailVal = (a, re) => {
    const det = (a.raw && (a.raw.additionalDetails || a.raw.AdditionalDetails)) || [];
    const hit = Array.isArray(det) ? det.find((d) => re.test(d.key || d.Key || '')) : null;
    return hit ? (hit.value || hit.Value || '') : '';
  };

  function roleOf(a) {
    if (a.raw && a.raw.role) return a.raw.role;
    const r = targets(a).find((x) => x && x.type === 'Role');
    if (r) return r.displayName;
    const mp = targets(a).flatMap((x) => x.modifiedProperties || []);
    const rn = mp.find((p) => /role\.displayname/i.test(p.displayName || ''));
    return rn ? String(rn.newValue || '').replace(/"/g, '') : '';
  }
  function memberOf(a) {
    if (a.raw && a.raw.member) return a.raw.member;
    const u = targets(a).find((x) => x && x.type === 'User');
    return u ? (u.displayName || u.userPrincipalName) : a.target;
  }
  function policyOf(a) {
    return (a.raw && a.raw.policyName) || (targets(a)[0] && targets(a)[0].displayName) || a.target || '';
  }
  function appOf(a) {
    return (a.raw && a.raw.appName) || (targets(a)[0] && targets(a)[0].displayName) || a.target || '';
  }
  function permsOf(a) {
    if (a.raw && Array.isArray(a.raw.permissions)) return a.raw.permissions;
    const v = detailVal(a, /permission|scope|role/i);
    return v ? String(v).split(/[,;]\s*/).filter(Boolean) : [];
  }
  function forwardOf(a) {
    if (a.raw && a.raw.forwardTo) return { to: a.raw.forwardTo, external: !!a.raw.forwardExternal };
    const params = detailVal(a, /parameter/i);
    const m = /(ForwardTo|RedirectTo|ForwardingSmtpAddress|ForwardAsAttachmentTo)\s*[:=]\s*([^;]+)/i.exec(params || '');
    if (!m) return null;
    const to = m[2].trim();
    const actorDom = lc((a.actorUpn || '').split('@')[1] || '');
    const toDom = lc((to.split('@')[1] || ''));
    return { to, external: !!toDom && toDom !== actorDom };
  }
  function externalEmailOf(a) {
    if (a.raw && a.raw.externalEmail) return a.raw.externalEmail;
    const u = targets(a)[0] || {};
    return u.displayName || u.userPrincipalName || a.target || '';
  }

  /* ---- classifiers ------------------------------------------------------- */
  const isAddRole = (a) => lc(a.activity) === 'add member to role';
  const isPrivAssignment = (a) => isAddRole(a) && PRIVILEGED_ROLES.has(lc(roleOf(a)));
  const isGAChange = (a) => {
    const act = lc(a.activity);
    return (act === 'add member to role' || act === 'remove member from role') && lc(roleOf(a)) === 'global administrator';
  };
  const isCAChange = (a) => lc(a.activity).includes('conditional access policy') || lc(a.service).includes('conditional access');
  const SP_POLICY = new Set(['sharingpolicychanged', 'set-spotenant', 'sharing policy changed', 'sharingset']);
  const isSharingPolicy = (a) => SP_POLICY.has(lc(a.activity)) || lc(a.activity).includes('sharing policy');
  const isExternalUser = (a) => {
    if (a.raw && a.raw.external) return true;
    const act = lc(a.activity);
    if (act.includes('invite') && act.includes('external')) return true;
    const upn = lc((targets(a)[0] || {}).userPrincipalName || '');
    return act === 'add user' && upn.includes('#ext#');
  };
  const isAnonLink = (a) => { const act = lc(a.activity); return act.includes('anonymouslink') && act.includes('creat'); };
  const isForwardingRule = (a) => {
    const act = lc(a.activity);
    if (!(act === 'new-inboxrule' || act === 'set-inboxrule' || act === 'set-mailbox')) return false;
    return !!forwardOf(a);
  };
  const OAUTH_OPS = new Set(['consent to application', 'add oauth2permissiongrant', 'add app role assignment to service principal', 'add delegated permission grant']);
  const isOAuthConsent = (a) => OAUTH_OPS.has(lc(a.activity));
  const isRiskyConsent = (a) => {
    if (a.raw && a.raw.riskyConsent != null) return !!a.raw.riskyConsent;
    return permsOf(a).map(lc).some((p) => /readwrite|\.all|full_access|directory|mail\.|files\.|sites\./.test(p));
  };

  /* Filter + enrich an audit array for a component, newest first. */
  const pickEvents = (audit, pred, enrich) =>
    audit.filter(pred).map((a) => Object.assign({}, a, enrich ? enrich(a) : {}))
      .sort((x, y) => y.dateTime - x.dateTime);

  const Governance = {
    PRIVILEGED_ROLES,
    roleOf, memberOf, policyOf, appOf, permsOf, forwardOf, externalEmailOf, isRiskyConsent,

    /* 1 — Global Admins (from privileged-role membership) */
    globalAdmins: (privRoles) => privRoles.filter((r) => lc(r.role) === 'global administrator'),
    roleInventory: (privRoles) => {
      const m = new Map();
      privRoles.forEach((r) => m.set(r.role, (m.get(r.role) || 0) + 1));
      return [...m.entries()].map(([label, value]) => ({ label, value })).sort((a, b) => b.value - a.value);
    },
    globalAdminChanges: (audit) => pickEvents(audit, isGAChange, (a) => ({ role: roleOf(a), member: memberOf(a) })),

    /* 2 — New privileged role assignments */
    privilegedAssignments: (audit) => pickEvents(audit, isPrivAssignment, (a) => ({ role: roleOf(a), member: memberOf(a) })),

    /* 3 — Conditional Access changes */
    caChanges: (audit) => pickEvents(audit, isCAChange, (a) => ({ policy: policyOf(a), change: (a.raw && a.raw.change) || '' })),

    /* 4 — SharePoint sharing policy changes */
    sharingPolicyChanges: (audit) => pickEvents(audit, isSharingPolicy, (a) => ({ change: (a.raw && a.raw.policyChange) || a.target || '' })),

    /* 5 — New external users */
    externalUsers: (audit) => pickEvents(audit, isExternalUser, (a) => ({ email: externalEmailOf(a) })),

    /* 6 — Anonymous sharing links created */
    anonymousLinks: (audit) => pickEvents(audit, isAnonLink, (a) => ({
      resource: (a.raw && a.raw.resource) || a.target || '', linkType: (a.raw && a.raw.linkType) || '',
    })),

    /* 7 — Mail forwarding rules */
    forwardingRules: (audit) => pickEvents(audit, isForwardingRule, (a) => {
      const f = forwardOf(a) || {}; return { forwardTo: f.to, external: !!f.external };
    }),

    /* 8 — OAuth app consents */
    oauthConsents: (audit) => pickEvents(audit, isOAuthConsent, (a) => ({
      app: appOf(a), permissions: permsOf(a), risky: isRiskyConsent(a),
      consentType: (a.raw && a.raw.consentType) || '',
    })),
  };

  global.Governance = Governance;
})(window);
