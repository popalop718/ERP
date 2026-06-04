/* =========================================================================
 * charts.js — tiny dependency-free SVG charting primitives.
 * Every function returns an SVG string so charts can be dropped into innerHTML.
 * ========================================================================= */
(function (global) {
  'use strict';

  const NS = 'http://www.w3.org/2000/svg';
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const fmt = (n) => (n >= 1000 ? (n / 1000).toFixed(n % 1000 === 0 ? 0 : 1) + 'k' : String(n));

  const PALETTE = ['#5b8def', '#9b6dff', '#ff7ab6', '#ffb454', '#3ecf8e', '#36c5f0', '#f25c54', '#a0a8c0'];
  const RISK = { high: '#f25c54', medium: '#ffb454', low: '#5b8def', none: '#3a4156' };

  /* Horizontal bar chart. data: [{label, value, color?, meta?}] */
  function hbar(data, opts = {}) {
    if (!data.length) return empty();
    const max = Math.max(...data.map((d) => d.value), 1);
    const rowH = opts.rowH || 30;
    const h = data.length * rowH + 8;
    const labelW = opts.labelW || 150;
    const barX = labelW + 8;
    const W = 460;
    const barW = W - barX - 44;
    let rows = '';
    data.forEach((d, i) => {
      const y = i * rowH + 4;
      const w = Math.max(2, (d.value / max) * barW);
      const color = d.color || PALETTE[i % PALETTE.length];
      rows += `
        <text x="${labelW}" y="${y + rowH / 2}" text-anchor="end" class="ch-label" dominant-baseline="middle">${esc(trunc(d.label, 22))}</text>
        <rect x="${barX}" y="${y + 5}" width="${w}" height="${rowH - 14}" rx="3" fill="${color}">
          <title>${esc(d.label)}: ${d.value}${d.meta ? ' — ' + esc(d.meta) : ''}</title>
        </rect>
        <text x="${barX + w + 6}" y="${y + rowH / 2}" class="ch-val" dominant-baseline="middle">${fmt(d.value)}</text>`;
    });
    return svg(W, h, rows);
  }

  /* Vertical bar / column chart for time series. data:[{label,value}] */
  function vbar(data, opts = {}) {
    if (!data.length) return empty();
    const W = opts.width || 760, H = opts.height || 220;
    const padB = 26, padT = 10, padL = 30;
    const max = Math.max(...data.map((d) => d.value), 1);
    const plotH = H - padB - padT, plotW = W - padL - 8;
    const bw = plotW / data.length;
    let bars = '', labels = '';
    const step = Math.ceil(data.length / 12);
    data.forEach((d, i) => {
      const h = (d.value / max) * plotH;
      const x = padL + i * bw;
      const y = padT + plotH - h;
      const color = d.color || (d.alert ? RISK.high : '#5b8def');
      bars += `<rect x="${x + 1}" y="${y}" width="${Math.max(1, bw - 2)}" height="${Math.max(0, h)}" rx="2" fill="${color}"><title>${esc(d.label)}: ${d.value}</title></rect>`;
      if (i % step === 0) labels += `<text x="${x + bw / 2}" y="${H - 8}" text-anchor="middle" class="ch-axis">${esc(d.short || d.label)}</text>`;
    });
    // y gridlines
    let grid = '';
    for (let g = 0; g <= 2; g++) {
      const v = Math.round((max / 2) * g);
      const y = padT + plotH - (v / max) * plotH;
      grid += `<line x1="${padL}" y1="${y}" x2="${W - 8}" y2="${y}" class="ch-grid"/><text x="${padL - 6}" y="${y + 3}" text-anchor="end" class="ch-axis">${fmt(v)}</text>`;
    }
    return svg(W, H, grid + bars + labels);
  }

  /* Donut chart. data:[{label,value,color?}] */
  function donut(data, opts = {}) {
    const total = data.reduce((a, d) => a + d.value, 0);
    if (!total) return empty();
    const size = opts.size || 170, r = size / 2 - 6, cx = size / 2, cy = size / 2, sw = opts.thickness || 22;
    let a0 = -Math.PI / 2, segs = '';
    data.forEach((d, i) => {
      const frac = d.value / total;
      const a1 = a0 + frac * Math.PI * 2;
      const large = frac > 0.5 ? 1 : 0;
      const x0 = cx + r * Math.cos(a0), y0 = cy + r * Math.sin(a0);
      const x1 = cx + r * Math.cos(a1), y1 = cy + r * Math.sin(a1);
      const color = d.color || PALETTE[i % PALETTE.length];
      if (frac > 0.999) {
        segs += `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${color}" stroke-width="${sw}"><title>${esc(d.label)}: ${d.value}</title></circle>`;
      } else {
        segs += `<path d="M ${x0} ${y0} A ${r} ${r} 0 ${large} 1 ${x1} ${y1}" fill="none" stroke="${color}" stroke-width="${sw}" stroke-linecap="butt"><title>${esc(d.label)}: ${d.value} (${Math.round(frac * 100)}%)</title></path>`;
      }
      a0 = a1;
    });
    const center = `<text x="${cx}" y="${cy - 2}" text-anchor="middle" class="ch-donut-num">${fmt(total)}</text>
                    <text x="${cx}" y="${cy + 16}" text-anchor="middle" class="ch-axis">${esc(opts.centerLabel || 'total')}</text>`;
    const legend = data.map((d, i) =>
      `<div class="ch-leg-row"><span class="ch-dot" style="background:${d.color || PALETTE[i % PALETTE.length]}"></span>${esc(d.label)}<b>${fmt(d.value)}</b></div>`).join('');
    return `<div class="ch-donut-wrap"><svg viewBox="0 0 ${size} ${size}" width="${size}" height="${size}">${segs}${center}</svg><div class="ch-legend">${legend}</div></div>`;
  }

  function empty() { return '<div class="ch-empty">No data</div>'; }
  function trunc(s, n) { s = String(s); return s.length > n ? s.slice(0, n - 1) + '…' : s; }
  function svg(w, h, body) { return `<svg viewBox="0 0 ${w} ${h}" width="100%" preserveAspectRatio="xMinYMin meet" style="max-height:${h}px">${body}</svg>`; }

  global.Charts = { hbar, vbar, donut, PALETTE, RISK };
})(window);
