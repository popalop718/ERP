# HANDOFF — Auth & Audit Hub

This document is everything a new Claude (running in **Claude Code desktop**)
needs to pick up and continue this project. Read it top to bottom once, then
keep it open as a reference.

---

## 1. What this project is

**Auth & Audit Hub** is a self-contained security dashboard that visualises
sign-in, audit, identity-governance and threat data from **Microsoft Entra ID
(Azure AD)**, **Microsoft 365**, and **Microsoft Defender for Office 365**.

It is a **static, dependency-free web app** — plain HTML + CSS + vanilla JS with
hand-rolled SVG charts. **No build step, no npm dependencies, no framework.** It
runs by serving the folder statically and opening it in a browser.

Data comes from three interchangeable sources:
1. **Bundled sample data** (`data/*.json`) — loads by default, has seeded anomalies.
2. **Uploaded exports** — Entra/M365 JSON or CSV, or a raw Log Analytics result.
3. **Live Azure Log Analytics** — queried in-browser via the REST API + KQL.

### Features already built
- **Overview** — KPI stat cards + sign-in volume / outcome / threat charts.
- **Sign-in Analytics** — four widgets, each with its own filters:
  unusual sign-in activity (behavioural anomaly scoring), risky users,
  risky sign-ins, legacy authentication attempts.
- **Governance & Threats** — nine components: Global Admin count, new privileged
  role assignments, Conditional Access changes, SharePoint sharing policy
  changes, new external users, anonymous sharing links, mail forwarding rules,
  OAuth app consents, Defender phishing/malware trends.
- **Audit Logs** — searchable / sortable / paginated table with row drill-in.
- **Global date-range filter** (24h / 7d / 30d / 90d / custom) in a sticky top
  bar — re-renders every view in real time.
- **Click-through drill-downs** — clicking any chart segment, KPI card, or row
  opens a filtered detail modal with **per-column sort + filter**, global
  search, and CSV export.
- **Alerts bell** (top-right) — coalesces high-risk events (CA changes, sharing
  policy changes, privileged assignments, high-risk sign-ins) with a count
  badge, grouped panel, "mark all read", and click-to-drill.

---

## 2. Repository & branch

- **GitHub repo:** `https://github.com/popalop718/ERP` (public)
- **Active branch:** `claude/show-back-dashboard-365-azure-ipb9O`
  (all work has been done here; `main` may be empty/behind)
- **Live site (GitHub Pages):** `https://popalop718.github.io/ERP/`

> ⚠️ The new Claude account's GitHub identity must have **write access** to
> `popalop718/ERP` to push. If it doesn't, either (a) have the repo owner add it
> as a collaborator, or (b) **fork** the repo and work/deploy from the fork
> (its Pages URL becomes `https://<your-user>.github.io/ERP/`).

---

## 3. Tech stack & architecture

- **Runtime in browser:** vanilla ES (no modules/imports; each JS file is an
  IIFE that attaches one global, e.g. `window.Charts`, `window.Parsers`).
- **Load order matters** (see `index.html`): charts → parsers → analytics →
  governance → loganalytics → app.
- **Local tooling:** Node 22 (only for the sample-data generator and the
  zero-dependency dev server) and Python 3 (optional alternative dev server).
- **Charts:** `assets/js/charts.js` emits SVG strings (bar / column / donut).
  No chart library.

### Data flow
```
raw export / KQL result
   → Parsers.normalize*()        (parsers.js: one stable internal schema)
   → state.{signins,audit,riskyUsers,riskySignins,privRoles,defender}
   → recomputeRanged()           (app.js: filters by global date range → sigCache.*)
   → Analytics / Governance      (analytics.js, governance.js: detections & aggregations)
   → view renderers              (app.js: build HTML strings)
   → drill-downs / alerts        (app.js: read sigCache + Governance)
```

---

## 4. File map

| File | Purpose |
| --- | --- |
| `index.html` | Shell: sidebar, `#topbar`, `#view`, `#drill`, script/style includes (with `?v=` cache-busting). |
| `assets/css/styles.css` | All styling (dark security-console theme). |
| `assets/js/charts.js` | `window.Charts` — `hbar`, `vbar`, `donut` (SVG). Segments carry `data-k` for drill clicks. |
| `assets/js/parsers.js` | `window.Parsers` — normalize sign-ins, audit, risky users/sign-ins, privileged roles, Defender; CSV parser; `fromLogAnalytics()`; `detectType()`. |
| `assets/js/analytics.js` | `window.Analytics` — `unusualActivity()` (anomaly scoring), `dailySeries()`, `topBy()`, helpers. |
| `assets/js/governance.js` | `window.Governance` — classify audit events into the 8 governance components + extract details. |
| `assets/js/loganalytics.js` | `window.LogAnalytics` — canonical KQL per dataset + `query()`/`loadAll()` REST client. |
| `assets/js/app.js` | The app: state, date range, views, widgets, filters, drill-downs, alerts, routing. **Largest file (~1300 lines).** |
| `data/*.json` | Bundled sample data (Entra-style `{ "value": [...] }` wrappers; Defender uses EmailEvents fields). |
| `scripts/generate-sample-data.mjs` | Deterministic sample-data generator (seeded PRNG). |
| `scripts/serve.mjs` | Zero-dependency Node static server (`npm start`). |
| `.github/workflows/pages.yml` | GitHub Pages deploy (Actions). |
| `README.md` | User-facing docs. |

---

## 5. Run it locally

From the repo root, **any** of:

```bash
npm start                    # Node zero-dep server → http://localhost:8080
# or
python3 -m http.server 8080  # → http://localhost:8080
```

Then open the URL. It auto-loads the bundled sample data. (Opening `index.html`
directly via `file://` will NOT load the JSON — browsers block `fetch()` over
`file://`. Always use a local server.)

Regenerate sample data after changing the generator:
```bash
npm run generate-data        # = node scripts/generate-sample-data.mjs
```

---

## 6. Develop & verify (the workflow used so far)

There is **no test framework**. Verification has been done by:

1. **Syntax check** every JS file you touch:
   ```bash
   node --check assets/js/app.js
   ```
2. **Headless browser smoke test** with Playwright (already installed globally in
   the previous cloud env; on desktop install it once: `npm i -D playwright &&
   npx playwright install chromium`). Pattern: start the static server, launch
   chromium, drive the page, assert counts, capture screenshots, and **fail on
   any `console.error`/`pageerror`**. Example skeleton:
   ```js
   import { chromium } from 'playwright';
   const errors = [];
   const b = await chromium.launch(); const p = await b.newPage();
   p.on('console', m => { if (m.type()==='error') errors.push(m.text()); });
   p.on('pageerror', e => errors.push(e.message));
   await p.goto('http://localhost:8080/', { waitUntil:'networkidle' });
   // ...click things, read text, screenshot...
   console.log('JS ERRORS:', errors.length ? errors : 'NONE');
   await b.close();
   ```
   Always confirm **zero JS errors** before committing.

3. **Visual check** — screenshot full page and key views.

---

## 7. Conventions & gotchas (read before editing)

- **Cache-busting (IMPORTANT):** asset URLs in `index.html` carry `?v=YYYYMMDD<letter>`
  (currently `?v=20260605d`). **Every time you change a CSS/JS file, bump this
  version on ALL asset links** (one `sed` does it), otherwise browsers/GitHub
  Pages serve stale files and "the change won't show". E.g.:
  ```bash
  sed -i 's/v=20260605d/v=20260605e/g' index.html
  ```
- **Everything is HTML-string rendering.** Always pass user/data text through the
  `esc()` helper (XSS-safe) in `app.js` / module-local equivalents.
- **Ranged data:** views and drills read **`sigCache.*`** (date-filtered), not
  `state.*` (raw). `recomputeRanged()` runs at the start of every `render()`.
- **Drill-downs:** make something clickable by adding `data-drill="<type>"` and,
  for chart segments/rows, `data-k="<key>"`. A delegated handler in `app.js`
  dispatches to `dispatchDrill(type, key)`; add new cases + a `COLS.*` column set
  there.
- **Charts:** `donut` radius is `size/2 - strokeWidth/2 - 1` so the ring never
  clips the viewBox — don't revert that. Chart `<text>`/`<title>` are
  `pointer-events:none` so segments receive clicks.
- **Stat cards:** `.stat-label` has `min-height: 2.6em` so one- and two-line
  titles keep their counts aligned. Keep it.
- **Alerts** are derived live from `sigCache` + `Governance`; acknowledged IDs
  live in an in-memory `Set` (reset on reload).
- **Field robustness:** parsers use case-insensitive multi-key lookups so they
  handle Entra JSON, CSV headers, and Log Analytics column names. When adding a
  field, add its aliases in `parsers.js`.

---

## 8. Connecting real data (no code change needed)

In the running app → **Data Source** tab:
- **Upload** Entra/M365 JSON or CSV, or a raw Log Analytics query result
  (auto-detected by filename + schema).
- **Azure Log Analytics:** paste a Workspace ID + bearer token
  (`az account get-access-token --resource https://api.loganalytics.io`). The
  canonical KQL it runs is shown on the **Reference** tab and lives in
  `loganalytics.js`. Tables used: `SigninLogs`,
  `AADNonInteractiveUserSignInLogs`, `AADRiskyUsers`, `AuditLogs`,
  `IdentityInfo` (privileged roles / UEBA), `EmailEvents` (Defender).

---

## 9. Deployment (GitHub Pages via Actions)

- Workflow: `.github/workflows/pages.yml`. It runs on push to
  `claude/show-back-dashboard-365-azure-ipb9O` and `main`, uploads the repo root
  (no build), and deploys.
- **One-time setup per repo** (already done for `popalop718/ERP`; redo if you
  fork): the repo must be **public** (Pages on private repos needs a paid plan),
  and **Settings → Pages → Build and deployment → Source = GitHub Actions** must
  be enabled once by a human (the Actions token can't bootstrap it).
- After that, every push to the branch redeploys automatically (~1 min). First
  publish can take a couple of minutes to appear on the CDN.
- To verify a run from Claude Code, use the GitHub MCP `actions_*` tools (or the
  Actions tab in the browser).

---

## 10. Step-by-step: set up in Claude Code desktop (new account)

1. **Install / open Claude Code desktop** and sign in with the new Claude account.
2. **Authenticate GitHub** so you can push:
   - Easiest: `gh auth login` (GitHub CLI) with an account that can write to the
     repo, **or** create a Personal Access Token and use it when git prompts.
   - If the new GitHub user lacks write access to `popalop718/ERP`, **fork** it
     first and use your fork's URL below.
3. **Clone the repo** (in a terminal or via Claude Code):
   ```bash
   git clone https://github.com/popalop718/ERP.git
   cd ERP
   git checkout claude/show-back-dashboard-365-azure-ipb9O
   ```
4. **Open the folder in Claude Code desktop** (Open Project → select the `ERP`
   folder). Claude Code will read this `HANDOFF.md` and `README.md`.
5. **Run it locally to confirm it works:**
   ```bash
   npm start        # → open http://localhost:8080
   ```
   You should see the dashboard with sample data, the date bar, and the alerts
   bell.
6. **(Optional) install the test tooling** for headless verification:
   ```bash
   npm i -D playwright && npx playwright install chromium
   ```
7. **Make changes** with Claude Code as normal. After edits:
   - `node --check assets/js/<file>.js`
   - bump the `?v=` cache version in `index.html` (see §7)
   - re-run the local server / headless smoke test
8. **Commit & push:**
   ```bash
   git add -A
   git commit -m "…"
   git push origin claude/show-back-dashboard-365-azure-ipb9O
   ```
   (Or push to `main`/your fork as appropriate.)
9. **Deploy:** the push triggers the Pages workflow automatically. If you forked,
   do the one-time Pages enablement in your fork's Settings (see §9).

---

## 11. Suggested next steps / backlog

- Optionally make the alerts badge count **only high-severity** items (and tuck
  mediums under a "more" divider) — currently it counts all qualifying events.
- Bring the drill-down column sort/filter UX to the in-page Audit and governance
  tables for consistency.
- Add a small Microsoft Graph export script for accurate Global Admin / role
  membership (alternative to `IdentityInfo`).
- Consider merging the feature branch into `main` and pointing Pages at `main`.
- Optional: a live auto-refresh toggle when connected to Log Analytics.

---

## 12. Quick reference

```bash
npm start                 # run locally (http://localhost:8080)
npm run generate-data     # regenerate data/*.json
node --check assets/js/app.js          # syntax check
sed -i 's/v=OLD/v=NEW/g' index.html    # bump cache-busting version
git push origin claude/show-back-dashboard-365-azure-ipb9O   # push + auto-deploy
```

- Repo: https://github.com/popalop718/ERP
- Branch: `claude/show-back-dashboard-365-azure-ipb9O`
- Live: https://popalop718.github.io/ERP/
