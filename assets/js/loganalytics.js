/* =========================================================================
 * loganalytics.js — Azure Monitor / Log Analytics connector.
 *
 * The four datasets are ingested into a Log Analytics workspace and live in
 * these tables (Entra ID diagnostic settings + M365 connectors):
 *
 *   SigninLogs                         -> interactive sign-ins
 *   AADNonInteractiveUserSignInLogs    -> non-interactive / legacy sign-ins
 *   AADRiskyUsers                      -> Identity Protection risky users
 *   AADRiskySignInEvents / risk        -> risky sign-ins
 *   AuditLogs / OfficeActivity         -> directory & M365 audit
 *
 * This module holds the canonical KQL for each widget and a thin REST client
 * for the Log Analytics query API (https://api.loganalytics.io). The browser
 * can call this API directly with an AAD bearer token scoped to
 * https://api.loganalytics.io/.default — get one with:
 *
 *   az account get-access-token --resource https://api.loganalytics.io
 * ========================================================================= */
(function (global) {
  'use strict';

  const API = 'https://api.loganalytics.io/v1/workspaces';

  /* KQL builders. `range` is a KQL timespan literal e.g. 30d, 7d, 24h. */
  const KQL = {
    signins: (range = '30d') => `
SigninLogs
| where TimeGenerated > ago(${range})
| project TimeGenerated, UserDisplayName, UserPrincipalName, AppDisplayName,
          IPAddress, ClientAppUsed, UserAgent, LocationDetails,
          ResultType, ResultDescription, Status,
          RiskLevelDuringSignIn, RiskState, RiskDetail, CorrelationId, Id
| order by TimeGenerated desc
| take 50000`,

    // Includes non-interactive table where most legacy-auth traffic shows up.
    nonInteractive: (range = '30d') => `
AADNonInteractiveUserSignInLogs
| where TimeGenerated > ago(${range})
| project TimeGenerated, UserDisplayName, UserPrincipalName, AppDisplayName,
          IPAddress, ClientAppUsed, UserAgent, LocationDetails,
          ResultType, ResultDescription, Status,
          RiskLevelDuringSignIn, RiskState, RiskDetail, CorrelationId, Id
| order by TimeGenerated desc
| take 50000`,

    riskySignins: (range = '30d') => `
SigninLogs
| where TimeGenerated > ago(${range})
| where RiskLevelDuringSignIn in ('low','medium','high') or RiskState == 'atRisk'
| project TimeGenerated, UserDisplayName, UserPrincipalName, AppDisplayName,
          IPAddress, ClientAppUsed, LocationDetails,
          RiskLevelDuringSignIn, RiskLevelAggregated, RiskState, RiskDetail,
          ResultType, ResultDescription, Status, Id
| order by TimeGenerated desc`,

    riskyUsers: (range = '90d') => `
AADRiskyUsers
| where TimeGenerated > ago(${range})
| summarize arg_max(TimeGenerated, *) by UserPrincipalName
| where RiskState !in ('remediated','dismissed','none')
| project TimeGenerated, UserDisplayName, UserPrincipalName,
          RiskLevel, RiskState, RiskDetail, RiskLastUpdatedDateTime
| order by RiskLevel asc`,

    audit: (range = '30d') => `
AuditLogs
| where TimeGenerated > ago(${range})
| project TimeGenerated, OperationName, Category, LoggedByService,
          Result, ResultReason, InitiatedBy, TargetResources, CorrelationId, Id
| order by TimeGenerated desc
| take 50000`,

    // Privileged role membership (point-in-time). Requires Sentinel UEBA
    // (IdentityInfo). Alternatively source this from Microsoft Graph
    // (/directoryRoles/{id}/members) and upload as JSON.
    privRoles: () => `
IdentityInfo
| summarize arg_max(TimeGenerated, *) by AccountUPN
| mv-expand AssignedRole = AssignedRoles to typeof(string)
| where isnotempty(AssignedRole)
| project roleDisplayName = AssignedRole,
          principalDisplayName = AccountDisplayName,
          principalUserPrincipalName = AccountUPN,
          assignmentType = "Assigned", createdDateTime = TimeGenerated`,

    // Microsoft Defender for Office 365 email threats (advanced hunting).
    defender: (range = '30d') => `
EmailEvents
| where Timestamp > ago(${range})
| where ThreatTypes has_any ('Phish', 'Malware', 'Spam')
| project Timestamp, NetworkMessageId, RecipientEmailAddress, SenderFromAddress,
          SenderDisplayName, Subject, ThreatTypes, DetectionMethods,
          DeliveryAction, DeliveryLocation
| order by Timestamp desc
| take 50000`,
  };

  /* Run one KQL query against the workspace. Returns the raw API response. */
  async function query(workspaceId, token, kql) {
    const res = await fetch(`${API}/${encodeURIComponent(workspaceId)}/query`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query: kql }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new Error(`Log Analytics query failed (${res.status}): ${text.slice(0, 300)}`);
    }
    return res.json();
  }

  /* Fetch + normalize all datasets. Returns the same shape app.js expects. */
  async function loadAll({ workspaceId, token, range = '30d' }) {
    const run = (kql, kind) => query(workspaceId, token, kql)
      .then((r) => Parsers.fromLogAnalytics(r, kind));

    const [si, ni, rs, ru, au, pr, df] = await Promise.all([
      run(KQL.signins(range), 'signins'),
      run(KQL.nonInteractive(range), 'signins').catch(() => []), // table may be absent
      run(KQL.riskySignins(range), 'signins'),
      run(KQL.riskyUsers('90d'), 'riskyUsers'),
      run(KQL.audit(range), 'audit'),
      run(KQL.privRoles(), 'privRoles').catch(() => []),   // requires UEBA / IdentityInfo
      run(KQL.defender(range), 'defender').catch(() => []), // requires Defender for O365
    ]);

    const signinRows = si.concat(ni);
    return {
      signins: Parsers.normalizeSignIns(signinRows),
      riskySignins: Parsers.normalizeRiskySignIns(rs),
      riskyUsers: Parsers.normalizeRiskyUsers(ru),
      audit: Parsers.normalizeAudit(au),
      privRoles: Parsers.normalizePrivilegedRoles(pr),
      defender: Parsers.normalizeDefender(df),
    };
  }

  global.LogAnalytics = { API, KQL, query, loadAll };
})(window);
