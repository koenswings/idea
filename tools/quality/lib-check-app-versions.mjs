#!/usr/bin/env node
/**
 * lib-check-app-versions.mjs — compare app.yaml monitors to upstream (idea#88).
 * Invoked by check-app-versions.sh. Reads JSON { apps: [{ path, yaml }] } on stdin
 * (yaml already parsed by the shell helper) OR receives --apps-dir and loads itself.
 *
 * Monitor kinds:
 *   dockerhub   — Hub tags API; filter tag_pattern; newest matching tag vs upstream_tag
 *   http-scrape — GET url; apply pattern (named group "version" or group 1)
 *   github      — (optional) releases/latest or tags — if kind appears later
 *
 * stdout: JSON report. exit 0 always when the scan ran; exit 2 on usage error.
 */
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, basename } from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const yaml = require('js-yaml');

const args = process.argv.slice(2);
let appsDir = null;
let timeoutMs = 15000;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--apps-dir') appsDir = args[++i];
  else if (args[i] === '--timeout-ms') timeoutMs = parseInt(args[++i], 10);
  else if (args[i] === '-h' || args[i] === '--help') {
    console.log('Usage: lib-check-app-versions.mjs --apps-dir <dir> [--timeout-ms N]');
    process.exit(0);
  }
}
if (!appsDir) {
  console.error('ERROR: --apps-dir required');
  process.exit(2);
}

function listAppYamls(dir) {
  const out = [];
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir).sort()) {
    if (!name.startsWith('app-')) continue;
    const p = join(dir, name, 'app.yaml');
    if (existsSync(p) && statSync(p).isFile()) out.push({ appDir: name, path: p });
  }
  return out;
}

async function fetchText(url) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      signal: ctrl.signal,
      headers: { 'User-Agent': 'idea-check-app-versions/1.0 (koenswings/idea#88)' },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.text();
  } finally {
    clearTimeout(t);
  }
}

async function dockerhubTags(repo) {
  // repo: "library/mariadb" or "kiwix/kiwix-serve"
  const tags = [];
  let url = `https://hub.docker.com/v2/repositories/${repo}/tags?page_size=100&ordering=last_updated`;
  // Cap pages to keep Monday scan bounded
  for (let page = 0; page < 5 && url; page++) {
    const body = await fetchText(url);
    const data = JSON.parse(body);
    for (const r of data.results ?? []) {
      if (r.name) tags.push(r.name);
    }
    url = data.next || null;
  }
  return tags;
}

/** Compare two version-ish tags: 1 if a>b, -1 if a<b, 0 if equal numeric parts. */
function cmpVersion(a, b) {
  const pa = String(a).replace(/^v/, '').split(/[^0-9]+/).map((x) => parseInt(x, 10) || 0);
  const pb = String(b).replace(/^v/, '').split(/[^0-9]+/).map((x) => parseInt(x, 10) || 0);
  const n = Math.max(pa.length, pb.length);
  for (let i = 0; i < n; i++) {
    const da = pa[i] || 0, db = pb[i] || 0;
    if (da > db) return 1;
    if (da < db) return -1;
  }
  return 0;
}

function newestMatching(tags, pattern) {
  const re = new RegExp(pattern);
  const matched = tags.filter((t) => re.test(t));
  if (matched.length === 0) return null;
  // Highest semver-ish among matches (Hub last_updated order is not version order —
  // e.g. mariadb:10.6 can be refreshed after 10.11).
  return matched.reduce((best, t) => (cmpVersion(t, best) > 0 ? t : best));
}

function versionNewer(a, b) {
  if (!a || !b) return !!(a && a !== b);
  if (a === b) return false;
  const c = cmpVersion(a, b);
  if (c !== 0) return c > 0;
  // Equal numeric parts but strings differ (suffixes) — report so Kid looks
  return a !== b;
}

async function checkDockerhub(service, monitor) {
  const repo = monitor.repo;
  const pattern = monitor.tag_pattern || '.*';
  const current = service.upstream_tag || service.current_version || null;
  try {
    const tags = await dockerhubTags(repo);
    const latest = newestMatching(tags, pattern);
    const update = latest != null && current != null && versionNewer(latest, current);
    return {
      kind: 'dockerhub',
      repo,
      tag_pattern: pattern,
      current,
      latest,
      update_available: !!update,
      error: latest == null ? 'no tags matched pattern' : null,
    };
  } catch (e) {
    return {
      kind: 'dockerhub',
      repo,
      tag_pattern: pattern,
      current,
      latest: null,
      update_available: false,
      error: String(e.message || e),
    };
  }
}

async function checkHttpScrape(service, monitor) {
  const current = service.current_version || null;
  try {
    const text = await fetchText(monitor.url);
    const re = new RegExp(monitor.pattern);
    const m = text.match(re);
    let latest = null;
    if (m) latest = m.groups?.version ?? m[1] ?? m[0];
    const update = latest != null && current != null && versionNewer(latest, current);
    return {
      kind: 'http-scrape',
      url: monitor.url,
      current,
      latest,
      update_available: !!update,
      error: latest == null ? 'pattern did not match' : null,
    };
  } catch (e) {
    return {
      kind: 'http-scrape',
      url: monitor.url,
      current,
      latest: null,
      update_available: false,
      error: String(e.message || e),
    };
  }
}

async function checkMonitor(service, monitor) {
  switch (monitor.kind) {
    case 'dockerhub':
      return checkDockerhub(service, monitor);
    case 'http-scrape':
      return checkHttpScrape(service, monitor);
    default:
      return {
        kind: monitor.kind || 'unknown',
        update_available: false,
        error: `unsupported monitor kind: ${monitor.kind}`,
        current: service.current_version ?? null,
        latest: null,
      };
  }
}

const apps = [];
const updates = [];
for (const { appDir, path } of listAppYamls(appsDir)) {
  let doc;
  try {
    doc = yaml.load(readFileSync(path, 'utf8'));
  } catch (e) {
    apps.push({ app: appDir, path, error: String(e.message || e), services: [] });
    continue;
  }
  const appName = doc.app || appDir.replace(/^app-/, '');
  const serviceResults = [];
  for (const svc of doc.services || []) {
    const monitors = svc.monitors || [];
    const results = [];
    for (const mon of monitors) {
      const r = await checkMonitor(svc, mon);
      results.push(r);
      if (r.update_available) {
        updates.push({
          app: appName,
          service: svc.name,
          kind: r.kind,
          current: r.current,
          latest: r.latest,
          path,
        });
      }
    }
    serviceResults.push({
      name: svc.name,
      build: svc.build ?? null,
      image: svc.image ?? null,
      current_version: svc.current_version ?? null,
      upstream_tag: svc.upstream_tag ?? null,
      monitors: results,
    });
  }
  apps.push({ app: appName, path, idea_app_version: doc.idea_app_version ?? null, services: serviceResults });
}

const report = {
  generated_at: new Date().toISOString(),
  apps_dir: appsDir,
  app_count: apps.length,
  update_count: updates.length,
  updates,
  apps,
};
process.stdout.write(JSON.stringify(report, null, 2) + '\n');
process.exit(0);
