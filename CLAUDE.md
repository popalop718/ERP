# CLAUDE.md — Auth & Audit Hub

Project context and working rules for Claude Code. For full background, file map,
and onboarding steps, read **HANDOFF.md**.

## What this is
A **static, dependency-free** security dashboard (vanilla HTML/CSS/JS + hand-rolled
SVG charts) for Microsoft Entra ID / M365 / Defender sign-in, audit, governance,
and threat data. **No build step, no npm dependencies, no framework.** Each JS file
is an IIFE attaching one global (`Charts`, `Parsers`, `Analytics`, `Governance`,
`LogAnalytics`); load order is defined in `index.html`.

## Run & verify
- Run locally: `npm start` (→ http://localhost:8080) or `python3 -m http.server 8080`.
  Never test via `file://` — `fetch()` of the JSON is blocked there.
- Regenerate sample data: `npm run generate-data`.
- After editing any JS: `node --check assets/js/<file>.js`.
- Verify in a headless browser (Playwright) and confirm **zero `console.error` /
  `pageerror`** before committing. Screenshot key views for visual checks.

## Rules (do these every time)
1. **Bump the cache-busting version after ANY change to a CSS/JS file.** Asset URLs
   in `index.html` use `?v=YYYYMMDD<letter>` (currently `?v=20260605d`). Bump it on
   all asset links or deployed changes won't show:
   `sed -i 's/v=OLD/v=NEW/g' index.html`
2. **Escape all data** rendered into HTML via the `esc()` helper (everything is
   HTML-string rendering — XSS risk otherwise).
3. **Read ranged data, not raw:** views/drills/alerts use `sigCache.*`
   (date-range-filtered), set by `recomputeRanged()` at the top of `render()`.
   `state.*` is the unfiltered source.
4. **Drill-downs:** make something clickable with `data-drill="<type>"` (+ `data-k`
   on chart segments/rows); add a case in `dispatchDrill()` and a `COLS.*` column
   set in `app.js`.
5. **Parsers stay format-agnostic:** add field aliases in `parsers.js` so Entra
   JSON, CSV headers, and Log Analytics column names all work.

## Don't revert these fixes
- `charts.js` donut radius = `size/2 - strokeWidth/2 - 1` (prevents ring clipping).
- Chart `<text>`/`<title>` are `pointer-events:none` (so segments receive clicks).
- `.stat-label { min-height: 2.6em }` (keeps one/two-line card counts aligned).

## Git / deploy
- Work on branch **`claude/show-back-dashboard-365-azure-ipb9O`**.
- Commit + push there; pushing auto-deploys to GitHub Pages
  (`.github/workflows/pages.yml`). Repo: `popalop718/ERP`. Live:
  `https://popalop718.github.io/ERP/`.
- Pages requires a **public repo** + Settings → Pages → Source = **GitHub Actions**
  (one-time, per repo/fork). Do not create PRs unless asked.

## Sensitive data
Bundled `data/*.json` is **synthetic**. Real Log Analytics credentials are entered
at runtime in the browser and never committed — keep it that way.
