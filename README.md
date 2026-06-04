# Auth & Audit Hub — Entra ID & M365 Security Dashboard

A self-contained security dashboard that visualises sign-in, audit, identity-
governance and threat data from **Microsoft Entra ID (Azure AD)**, **Microsoft
365** and **Microsoft Defender for Office 365**. It works against a live
**Azure Log Analytics workspace** (where these logs are ingested), uploaded
export files, or bundled sample data.

A **global date-range filter** (24h / 7d / 30d / 90d / custom) sits at the top
of every view and re-renders all widgets in real time.

No build step, no runtime dependencies — plain HTML/CSS/JS with hand-rolled SVG
charts, so it runs anywhere a browser can open a file.

## Quick start

```bash
npm start            # serves on http://localhost:8080 (zero-dependency Node server)
# or, with Python:
python3 -m http.server 8080
```

Then open <http://localhost:8080>. It loads the bundled sample data by default so
every widget is populated immediately.

## What it shows

### Overview
At-a-glance KPI cards (sign-ins, risky users, risky sign-ins, legacy auth,
flagged users, audit events), 30-day sign-in volume trend, success/failure
breakdown, and the top users flagged for unusual activity.

### Sign-in Analytics — the four required widgets
1. **Unusual sign-in activity** — per-user behavioural anomaly scoring with
   explainable reasons. Heuristics include *impossible travel*, *password
   spray / brute force*, *failure→success from a new country* (takeover),
   *multiple countries*, *off-hours bursts*, *legacy auth*, *many source IPs*,
   and existing Identity Protection signals. Each flagged user shows a 0–100
   score, severity, and the specific reasons.
2. **Risky users** — Identity Protection aggregate risk per user (level, state,
   last updated) with a risk-level breakdown.
3. **Risky sign-ins** — sign-ins flagged at-risk, with detection type and time.
4. **Legacy authentication attempts** — legacy-protocol traffic (IMAP/POP/SMTP/
   ActiveSync/MAPI and legacy user agents) broken down by protocol, top users,
   and daily trend. These bypass modern auth/MFA and should be blocked via
   Conditional Access.

Every widget also has its own filter controls (severity, risk level, protocol,
detection type, free-text search) that refine just that widget.

### Governance & Threats
Nine components covering privileged access, tenant-configuration drift and email
threats — all respecting the global date range, each with its own search box:

1. **Global Admin count** — standing Global Administrator membership with a
   ≤5 recommendation, member list, recent role changes and a privileged-role
   inventory chart.
2. **New privileged role assignments** — members added to privileged directory roles.
3. **Conditional Access changes** — CA policies added, updated or deleted.
4. **SharePoint sharing policy changes** — tenant external-sharing configuration.
5. **New external users** — B2B guest invitations / `#EXT#` accounts.
6. **Anonymous sharing links created** — anyone-with-the-link files (SharePoint/OneDrive).
7. **Mail forwarding rules** — inbox rules & mailbox forwarding, flagged internal vs external.
8. **OAuth app consents** — delegated & application permission grants, with risky
   permissions highlighted.
9. **Defender phishing/malware trends** — daily volume, breakdown by threat type,
   most-targeted users and a blocked-vs-delivered table.

### Audit Logs
A searchable, sortable, paginated interface over directory & M365 audit events.
Free-text search across activity, user, target, IP, category and reason; filter
by service and result; click any row to expand structured details and the raw
event JSON.

## Data sources

Open the **Data Source** tab to switch between:

| Source | How |
| --- | --- |
| **Sample data** | Bundled, anonymised data in `data/*.json` with seeded anomalies. |
| **Upload exports** | Drag & drop Entra/M365 exports — JSON ("Download JSON"), CSV ("Download CSV"), or a raw Log Analytics query result. Type is auto-detected from filename & schema. |
| **Azure Log Analytics** | Query the workspace live via the Log Analytics REST API. |

### Connecting to Azure Log Analytics

The four datasets typically live in these workspace tables:

| Dataset | Table(s) |
| --- | --- |
| Sign-ins | `SigninLogs`, `AADNonInteractiveUserSignInLogs` |
| Risky sign-ins | `SigninLogs` (filtered on risk) |
| Risky users | `AADRiskyUsers` |
| Audit / governance | `AuditLogs` (and `OfficeActivity` for M365 — sharing, anonymous links, forwarding) |
| Privileged roles | `IdentityInfo` (Sentinel UEBA) or Microsoft Graph `directoryRoles` |
| Defender threats | `EmailEvents` (Defender for O365 advanced hunting) |

The exact KQL for each is shown on the **Data Source → Reference** tab.

Enter your **Workspace ID** and a **bearer token** scoped to the Log Analytics
API. Get a token with:

```bash
az account get-access-token --resource https://api.loganalytics.io
```

The dashboard runs the KQL shown on the **Data Source → Reference** tab and
calls `https://api.loganalytics.io/v1/workspaces/{id}/query` directly from the
browser. (The token stays in the page; nothing is sent anywhere else.)

## Supported export shapes

The parser normalises all of the following into one internal schema:

- **Entra ID JSON export** — rows wrapped in `{ "value": [ ... ] }`.
- **Entra ID / M365 CSV export** — column headers like `Date (UTC)`, `User`,
  `IP address`, `Client app`, `Risk level during sign-in`, etc.
- **Log Analytics query result** — `{ "tables": [{ "columns", "rows" }] }`,
  including `dynamic` columns (`LocationDetails`, `Status`, `InitiatedBy`,
  `TargetResources`) and the `TimeGenerated` / `ResultType` schema.

## Project layout

```
index.html                     app shell
assets/css/styles.css          dark security-console theme
assets/js/charts.js            dependency-free SVG charts (bar / column / donut)
assets/js/parsers.js           ingest & normalize Entra/M365/Defender/Log Analytics data
assets/js/analytics.js         behavioural anomaly detection & aggregations
assets/js/governance.js        governance/threat classification over audit logs
assets/js/loganalytics.js      Log Analytics REST client + canonical KQL
assets/js/app.js               views, routing, widgets, global date range, search
data/*.json                    bundled sample data (sign-ins, audit, risky users/
                               sign-ins, privileged roles, Defender events)
scripts/generate-sample-data.mjs   regenerate sample data
scripts/serve.mjs              zero-dependency static server
```

Regenerate the sample data with `npm run generate-data`.
