/* =========================================================================
 * analytics.js — behavioural detections over normalized sign-in records.
 *
 * The "Unusual sign-in activity" widget is driven by a per-user anomaly score
 * built from several independent heuristics. Each heuristic contributes points
 * and a human-readable reason, so analysts can see *why* a user was flagged.
 * ========================================================================= */
(function (global) {
  'use strict';

  const HOUR = 3600000;
  // Rough country centroids (lat, lng) for impossible-travel estimation.
  const CENTROID = {
    US: [39.8, -98.6], GB: [54, -2], IE: [53.4, -8], NL: [52.1, 5.3],
    NG: [9.1, 8.7], RU: [61.5, 105.3], CN: [35.9, 104.2], BR: [-14.2, -51.9],
    DE: [51.2, 10.4], FR: [46.6, 2.2], IN: [20.6, 79], AU: [-25.3, 133.8],
  };
  const KMH_MAX = 900; // commercial flight ceiling; faster ⇒ "impossible travel"

  function haversine(a, b) {
    if (!a || !b) return 0;
    const R = 6371, toR = (d) => (d * Math.PI) / 180;
    const dLat = toR(b[0] - a[0]), dLng = toR(b[1] - a[1]);
    const x = Math.sin(dLat / 2) ** 2 +
      Math.cos(toR(a[0])) * Math.cos(toR(b[0])) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(x));
  }

  /* Group an array by a key function. */
  function groupBy(arr, keyFn) {
    const m = new Map();
    for (const x of arr) {
      const k = keyFn(x);
      if (!m.has(k)) m.set(k, []);
      m.get(k).push(x);
    }
    return m;
  }

  /**
   * Score each user for unusual sign-in behaviour.
   * Returns [{ user, upn, score, severity, reasons[], stats{} }] sorted desc.
   */
  function unusualActivity(signins) {
    const byUser = groupBy(signins, (s) => s.upn || s.user);
    const results = [];

    for (const [upn, events] of byUser) {
      events.sort((a, b) => a.dateTime - b.dateTime);
      const reasons = [];
      let score = 0;

      const fails = events.filter((e) => !e.success);
      const countries = new Set(events.map((e) => e.country).filter(Boolean));
      const ips = new Set(events.map((e) => e.ip).filter(Boolean));
      const legacy = events.filter((e) => e.isLegacy);
      const offHours = events.filter((e) => { const h = e.dateTime.getUTCHours(); return h < 6 || h >= 22; });
      const riskyEvents = events.filter((e) => e.riskLevel === 'high' || e.riskLevel === 'medium');

      // 1) Impossible travel — successful sign-ins from far apart in short time.
      let maxSpeed = 0, travelPair = null;
      for (let i = 1; i < events.length; i++) {
        const a = events[i - 1], b = events[i];
        if (a.country === b.country) continue;
        const dist = haversine(CENTROID[a.country], CENTROID[b.country]);
        const hrs = (b.dateTime - a.dateTime) / HOUR;
        if (dist > 500 && hrs >= 0 && hrs < 12) {
          const speed = dist / Math.max(hrs, 0.1);
          if (speed > maxSpeed) { maxSpeed = speed; travelPair = [a, b, dist, hrs]; }
        }
      }
      if (maxSpeed > KMH_MAX && travelPair) {
        score += 45;
        const [a, b, dist, hrs] = travelPair;
        reasons.push(`Impossible travel: ${a.country}→${b.country} (~${Math.round(dist)} km in ${hrs.toFixed(1)} h)`);
      }

      // 2) Brute-force / password spray — many failures in a tight window.
      const failBurst = maxWindow(fails.map((e) => +e.dateTime), 2 * HOUR);
      if (failBurst >= 10) {
        score += 35;
        reasons.push(`${failBurst} failed sign-ins within 2h (possible brute force / spray)`);
      } else if (fails.length >= 15) {
        score += 15;
        reasons.push(`${fails.length} failed sign-ins overall`);
      }

      // 3) Failure → success from a foreign country (likely account takeover).
      const tookOver = events.some((e, i) =>
        e.success && i > 0 && !events[i - 1].success &&
        e.country !== events[i - 1].country && CENTROID[e.country]);
      if (tookOver && fails.length >= 5) {
        score += 20;
        reasons.push('Successful sign-in immediately after repeated failures from a new country');
      }

      // 4) Multiple distinct countries.
      if (countries.size >= 3) { score += 15; reasons.push(`Sign-ins from ${countries.size} countries`); }
      else if (countries.size === 2) { score += 6; }

      // 5) Legacy authentication usage.
      if (legacy.length >= 5) { score += 12; reasons.push(`${legacy.length} legacy-auth attempts`); }

      // 6) Off-hours concentration.
      if (offHours.length >= 6) { score += 10; reasons.push(`${offHours.length} sign-ins outside 06:00–22:00 UTC`); }

      // 7) Identity Protection already flagged risk.
      if (riskyEvents.length) { score += Math.min(20, riskyEvents.length * 3); reasons.push(`${riskyEvents.length} risk-flagged sign-ins`); }

      // 8) Many distinct source IPs.
      if (ips.size >= 8) { score += 8; reasons.push(`${ips.size} distinct source IPs`); }

      if (score > 0 && reasons.length) {
        results.push({
          user: events[0].user || upn,
          upn,
          score: Math.min(100, score),
          severity: score >= 60 ? 'high' : score >= 30 ? 'medium' : 'low',
          reasons,
          stats: {
            total: events.length, failures: fails.length, countries: countries.size,
            ips: ips.size, legacy: legacy.length,
            lastSeen: events[events.length - 1].dateTime,
          },
        });
      }
    }
    return results.sort((a, b) => b.score - a.score);
  }

  /* Max number of timestamps falling within any sliding window of `span` ms. */
  function maxWindow(times, span) {
    if (!times.length) return 0;
    times.sort((a, b) => a - b);
    let best = 1, j = 0;
    for (let i = 0; i < times.length; i++) {
      while (times[i] - times[j] > span) j++;
      best = Math.max(best, i - j + 1);
    }
    return best;
  }

  /* Daily time-series counts for a metric. predicate optional. */
  function dailySeries(records, days = 30, predicate = () => true, field = 'dateTime') {
    const buckets = new Map();
    const now = Date.now();
    for (let d = days; d >= 0; d--) {
      const day = new Date(now - d * 86400000);
      buckets.set(dayKey(day), 0);
    }
    for (const r of records) {
      if (!predicate(r)) continue;
      const k = dayKey(r[field]);
      if (buckets.has(k)) buckets.set(k, buckets.get(k) + 1);
    }
    return [...buckets.entries()].map(([k, v]) => ({
      label: k, short: k.slice(5), value: v,
    }));
  }

  function dayKey(d) {
    const dt = d instanceof Date ? d : new Date(d);
    return dt.toISOString().slice(0, 10);
  }

  /* Tally counts by a key, returning sorted [{label,value}]. */
  function topBy(records, keyFn, limit = 8) {
    const m = groupBy(records.filter((r) => keyFn(r)), keyFn);
    return [...m.entries()]
      .map(([k, v]) => ({ label: k, value: v.length }))
      .sort((a, b) => b.value - a.value).slice(0, limit);
  }

  global.Analytics = { unusualActivity, dailySeries, topBy, groupBy, haversine };
})(window);
