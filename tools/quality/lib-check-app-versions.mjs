#!/usr/bin/env node
/**
 * lib-check-app-versions.mjs — compare App monitors to upstream (idea#88, idea#543).
 * Invoked by check-app-versions.sh. Exportable for unit tests (mocked fetch).
 *
 * Monitor kinds:
 *   dockerhub       — Hub tags API; filter tag_pattern; newest matching tag vs pin
 *   ghcr            — GHCR v2 tags/list (anonymous pull token + Link pagination)
 *   http-scrape     — GET url; apply pattern (named group "version" or group 1)
 *   pypi            — PyPI JSON (https://pypi.org/pypi/<package>/json)
 *   github-release  — GitHub Releases API (releases/latest, or releases + tag_pattern)
 *
 * Current pin (in order): monitor.current, service.upstream_tag, service.base_image
 * tag, Dockerfile FROM (when service.dockerfile is set). App current_version is
 * not used for registry / base-image monitors — that caused milkwise 1.0.65 vs
 * 22-alpine false positives (idea#543).
 *
 * App version in the report comes from compose.yaml x-app.version (Engine bundle
 * name is <x-app.name>-<x-app.version>). app.yaml idea_app_version is not read
 * (dropped; compose is the only App version).
 *
 * stdout: JSON report. exit 0 when the scan ran; exit 2 on usage error.
 */
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, resolve as resolvePath } from 'node:path';
import { pathToFileURL } from 'node:url';
import yaml from 'js-yaml';

export const USER_AGENT = 'idea-check-app-versions/1.1 (koenswings/idea#543)';
export const DOCKERHUB_MAX_PAGES = 40;

const DEFAULT_TIMEOUT_MS = 15000;

/** Numeric fields of a version-ish tag, split on dots. "24.04.13.2" → [24,4,13,2]. */
export function parseVersionFields(value) {
  const s = String(value ?? '').trim().replace(/^v/i, '');
  if (!s) return [];
  return s.split('.').map((field) => {
    const m = String(field).match(/(\d+)/);
    return m ? parseInt(m[1], 10) : 0;
  });
}

/** Compare two version-ish tags: 1 if a>b, -1 if a<b, 0 if equal numeric fields. */
export function cmpVersion(a, b) {
  const pa = parseVersionFields(a);
  const pb = parseVersionFields(b);
  const n = Math.max(pa.length, pb.length);
  for (let i = 0; i < n; i++) {
    const da = pa[i] || 0;
    const db = pb[i] || 0;
    if (da > db) return 1;
    if (da < db) return -1;
  }
  return 0;
}

/** True only when latest is numerically greater than current (idea#543). */
export function versionNewer(latest, current) {
  if (latest == null || current == null) return false;
  if (String(latest) === String(current)) return false;
  return cmpVersion(latest, current) > 0;
}

export function newestMatching(tags, pattern) {
  const re = new RegExp(pattern);
  const matched = (tags || []).filter((t) => re.test(t));
  if (matched.length === 0) return null;
  return matched.reduce((best, t) => (cmpVersion(t, best) > 0 ? t : best));
}

/** Parse RFC 5988 Link header and return the rel=next URL, if any. */
export function parseLinkNext(linkHeader) {
  if (!linkHeader) return null;
  for (const part of String(linkHeader).split(',')) {
    const m = part.match(/<([^>]+)>\s*;\s*rel="?next"?/i);
    if (m) return m[1];
  }
  return null;
}

/** Resolve a Link rel=next target (may be a relative path) against the current request URL. */
export function resolveLinkNext(linkHeader, currentUrl) {
  const next = parseLinkNext(linkHeader);
  if (!next) return null;
  try {
    return new URL(next, currentUrl).href;
  } catch {
    return next;
  }
}

/**
 * Parse an image reference into { image, tag, digest }.
 * "node:22-alpine@sha256:abc" → { image: "node", tag: "22-alpine", digest: "sha256:abc" }
 */
export function parseImageRef(ref) {
  if (!ref) return { image: null, tag: null, digest: null };
  let rest = String(ref).trim();
  let digest = null;
  const at = rest.indexOf('@');
  if (at >= 0) {
    digest = rest.slice(at + 1) || null;
    rest = rest.slice(0, at);
  }
  const slash = rest.lastIndexOf('/');
  const colon = rest.lastIndexOf(':');
  let tag = null;
  let image = rest;
  if (colon > slash) {
    tag = rest.slice(colon + 1) || null;
    image = rest.slice(0, colon);
  }
  return { image, tag, digest };
}

/** First FROM in a Dockerfile (skips FROM scratch / empty). */
export function parseDockerfileFrom(contents) {
  for (const raw of String(contents).split(/\r?\n/)) {
    const line = raw.replace(/#.*$/, '').trim();
    const m = line.match(/^FROM\s+(?:--platform=\S+\s+)?(\S+)/i);
    if (!m) continue;
    const ref = m[1];
    if (!ref || /^scratch$/i.test(ref)) continue;
    return parseImageRef(ref);
  }
  return { image: null, tag: null, digest: null };
}

function readDockerfileFrom(appRoot, relPath) {
  if (!relPath) return null;
  const p = join(appRoot, relPath);
  if (!existsSync(p) || !statSync(p).isFile()) return null;
  return parseDockerfileFrom(readFileSync(p, 'utf8'));
}

function labelValue(labels, key) {
  if (!labels) return null;
  if (Array.isArray(labels)) {
    const prefix = `${key}=`;
    for (const item of labels) {
      const s = String(item);
      if (s.startsWith(prefix)) return s.slice(prefix.length);
    }
    return null;
  }
  if (typeof labels === 'object') {
    if (labels[key] != null) return String(labels[key]);
  }
  return null;
}

/**
 * Read compose.yaml x-app.version and any x-app-version labels.
 * Returns { file, xAppVersion, labelVersions } or null when no compose file exists.
 */
export function readComposeAppVersion(appRoot, yamlLoad = yaml.load) {
  const names = ['compose.yaml', 'compose.yml', 'docker-compose.yaml', 'docker-compose.yml'];
  for (const name of names) {
    const p = join(appRoot, name);
    if (!existsSync(p) || !statSync(p).isFile()) continue;
    let doc;
    try {
      doc = yamlLoad(readFileSync(p, 'utf8'));
    } catch (e) {
      return { file: name, xAppVersion: null, labelVersions: [], error: String(e.message || e) };
    }
    const xAppVersion = doc?.['x-app']?.version != null ? String(doc['x-app'].version) : null;
    const labelVersions = [];
    for (const svc of Object.values(doc?.services || {})) {
      const v = labelValue(svc?.labels, 'x-app-version');
      if (v != null) labelVersions.push(v);
    }
    return { file: name, xAppVersion, labelVersions, error: null };
  }
  return null;
}

/**
 * Pin used for an upstream/base comparison. Never falls back to the App's
 * current_version for dockerhub/ghcr (those monitors watch an upstream tag
 * or a base image, not the IDEA App version).
 */
export function resolveCurrent(service, monitor, appRoot) {
  if (monitor?.current) {
    return { current: String(monitor.current), digest: monitor.current_digest ?? null, source: 'monitor.current' };
  }
  const kind = monitor?.kind;
  const registryKind = kind === 'dockerhub' || kind === 'ghcr';
  if (service?.upstream_tag) {
    return { current: String(service.upstream_tag), digest: null, source: 'upstream_tag' };
  }
  if (service?.base_image) {
    const parsed = parseImageRef(service.base_image);
    return {
      current: parsed.tag || String(service.base_image),
      digest: parsed.digest,
      source: 'base_image',
    };
  }
  if (registryKind && service?.dockerfile && appRoot) {
    const parsed = readDockerfileFrom(appRoot, service.dockerfile);
    if (parsed?.tag || parsed?.digest) {
      return { current: parsed.tag, digest: parsed.digest, source: 'dockerfile' };
    }
  }
  if (registryKind) {
    return { current: null, digest: null, source: null };
  }
  if (service?.current_version) {
    return { current: String(service.current_version), digest: null, source: 'current_version' };
  }
  return { current: null, digest: null, source: null };
}

export function defaultFetchImpl(url, opts = {}, timeoutMs = DEFAULT_TIMEOUT_MS) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  const headers = { 'User-Agent': USER_AGENT, ...(opts.headers || {}) };
  return fetch(url, { ...opts, headers, signal: ctrl.signal })
    .then(async (res) => {
      const text = await res.text();
      const headerObj = {};
      res.headers.forEach((v, k) => { headerObj[k.toLowerCase()] = v; });
      return { ok: res.ok, status: res.status, text, headers: headerObj };
    })
    .finally(() => clearTimeout(t));
}

function sleep(ms, sleepImpl) {
  const fn = sleepImpl || ((n) => new Promise((r) => setTimeout(r, n)));
  return fn(ms);
}

const RETRY_STATUSES = new Set([403, 408, 429, 500, 502, 503, 504]);

async function request(ctx, url, opts = {}) {
  const fn = ctx.fetchImpl || defaultFetchImpl;
  const retries = ctx.retries ?? 3;
  let lastErr;
  for (let i = 0; i <= retries; i++) {
    try {
      const res = await fn(url, opts, ctx.timeoutMs ?? DEFAULT_TIMEOUT_MS);
      if (res.ok) return res;
      lastErr = new Error(`HTTP ${res.status}`);
      if (!RETRY_STATUSES.has(res.status) || i === retries) throw lastErr;
    } catch (e) {
      lastErr = e;
      const msg = String(e.message || e);
      const retryable = /HTTP (403|408|429|500|502|503|504)/.test(msg) || /aborted|timeout|ECONNRESET|ETIMEDOUT/i.test(msg);
      if (!retryable || i === retries) throw e;
    }
    await sleep(250 * (i + 1), ctx.sleepImpl);
  }
  throw lastErr;
}

async function requestJson(ctx, url, opts = {}) {
  const res = await request(ctx, url, opts);
  try {
    return { data: JSON.parse(res.text), headers: res.headers || {} };
  } catch (e) {
    throw new Error(`invalid JSON: ${e.message || e}`);
  }
}

async function registryTags(ctx, { tokenUrl, listUrl }) {
  const { data: tokenBody } = await requestJson(ctx, tokenUrl);
  const token = tokenBody.token || tokenBody.access_token;
  if (!token) throw new Error('registry token response missing token');
  const auth = { Authorization: `Bearer ${token}` };
  const tags = [];
  let url = listUrl;
  let pages = 0;
  while (url && pages < 40) {
    pages += 1;
    const { data, headers } = await requestJson(ctx, url, { headers: auth });
    for (const t of data.tags ?? []) tags.push(t);
    url = resolveLinkNext(headers.link || headers.Link, url);
  }
  return { tags, digests: {}, truncated: Boolean(url) };
}

async function dockerhubTagsViaHub(ctx, repo) {
  const tags = [];
  const digests = {};
  let url = `https://hub.docker.com/v2/repositories/${repo}/tags?page_size=100&ordering=last_updated`;
  for (let page = 0; page < DOCKERHUB_MAX_PAGES && url; page++) {
    const { data } = await requestJson(ctx, url);
    for (const r of data.results ?? []) {
      if (!r.name) continue;
      tags.push(r.name);
      const digest = r.digest || r.images?.[0]?.digest || null;
      if (digest) digests[r.name] = digest;
    }
    url = data.next || null;
  }
  return { tags, digests, truncated: Boolean(url) };
}

/** List Docker Hub tags via the registry v2 API (one shot, avoids Hub 403s on large official repos). */
export async function dockerhubTags(ctx, repo) {
  try {
    return await registryTags(ctx, {
      tokenUrl: `https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull`,
      listUrl: `https://registry-1.docker.io/v2/${repo}/tags/list`,
    });
  } catch {
    return await dockerhubTagsViaHub(ctx, repo);
  }
}

export async function ghcrTags(ctx, repo) {
  const clean = String(repo).replace(/^ghcr\.io\//, '');
  return registryTags(ctx, {
    tokenUrl: `https://ghcr.io/token?scope=repository:${clean}:pull`,
    listUrl: `https://ghcr.io/v2/${clean}/tags/list?n=1000`,
  });
}

async function checkRegistry(ctx, service, monitor, appRoot, kind) {
  const repo = monitor.repo;
  const pattern = monitor.tag_pattern || '.*';
  const pin = resolveCurrent(service, monitor, appRoot);
  const current = pin.current;
  try {
    if (!repo) throw new Error(`${kind} monitor missing repo`);
    const listed = kind === 'ghcr'
      ? await ghcrTags(ctx, repo)
      : await dockerhubTags(ctx, repo);
    const latest = newestMatching(listed.tags, pattern);
    let update = latest != null && current != null && versionNewer(latest, current);
    let digestUpdate = false;
    const latestDigest = listed.digests?.[latest] || null;
    if (!update && latest != null && current != null && cmpVersion(latest, current) === 0 && pin.digest && latestDigest) {
      digestUpdate = pin.digest !== latestDigest;
      update = digestUpdate;
    }
    const error = latest == null
      ? 'no tags matched pattern'
      : (listed.truncated ? 'tag list truncated; latest is max among fetched pages' : null);
    return {
      kind,
      repo,
      tag_pattern: pattern,
      current,
      current_source: pin.source,
      latest,
      latest_digest: latestDigest,
      current_digest: pin.digest,
      update_available: !!update,
      digest_update: digestUpdate || undefined,
      error,
    };
  } catch (e) {
    return {
      kind,
      repo,
      tag_pattern: pattern,
      current,
      current_source: pin.source,
      latest: null,
      update_available: false,
      error: String(e.message || e),
    };
  }
}

async function checkHttpScrape(ctx, service, monitor, appRoot) {
  const pin = resolveCurrent(service, monitor, appRoot);
  const current = pin.current;
  try {
    const res = await request(ctx, monitor.url);
    const re = new RegExp(monitor.pattern);
    const m = res.text.match(re);
    let latest = null;
    if (m) latest = m.groups?.version ?? m[1] ?? m[0];
    const update = latest != null && current != null && versionNewer(latest, current);
    return {
      kind: 'http-scrape',
      url: monitor.url,
      current,
      current_source: pin.source,
      latest,
      update_available: !!update,
      error: latest == null ? 'pattern did not match' : null,
    };
  } catch (e) {
    return {
      kind: 'http-scrape',
      url: monitor.url,
      current,
      current_source: pin.source,
      latest: null,
      update_available: false,
      error: String(e.message || e),
    };
  }
}

async function checkPypi(ctx, service, monitor, appRoot) {
  const pkg = monitor.package || monitor.project || monitor.name;
  const pin = resolveCurrent(service, monitor, appRoot);
  const current = pin.current;
  try {
    if (!pkg) throw new Error('pypi monitor missing package');
    const url = monitor.url || `https://pypi.org/pypi/${encodeURIComponent(pkg)}/json`;
    const { data } = await requestJson(ctx, url);
    const latest = data?.info?.version ?? null;
    const update = latest != null && current != null && versionNewer(latest, current);
    return {
      kind: 'pypi',
      package: pkg,
      current,
      current_source: pin.source,
      latest,
      update_available: !!update,
      error: latest == null ? 'PyPI response missing info.version' : null,
    };
  } catch (e) {
    return {
      kind: 'pypi',
      package: pkg ?? null,
      current,
      current_source: pin.source,
      latest: null,
      update_available: false,
      error: String(e.message || e),
    };
  }
}

async function checkGithubRelease(ctx, service, monitor, appRoot) {
  const repo = monitor.repo;
  const pin = resolveCurrent(service, monitor, appRoot);
  const current = pin.current;
  const pattern = monitor.tag_pattern;
  try {
    if (!repo) throw new Error('github-release monitor missing repo');
    let latest = null;
    if (pattern) {
      const tags = [];
      let url = `https://api.github.com/repos/${repo}/releases?per_page=100`;
      for (let page = 0; page < 5 && url; page++) {
        const { data, headers } = await requestJson(ctx, url);
        const list = Array.isArray(data) ? data : [];
        for (const r of list) {
          if (r?.tag_name) tags.push(r.tag_name);
        }
        url = resolveLinkNext(headers.link || headers.Link, url);
      }
      latest = newestMatching(tags, pattern);
    } else {
      const url = `https://api.github.com/repos/${repo}/releases/latest`;
      const { data } = await requestJson(ctx, url);
      latest = data?.tag_name ?? data?.name ?? null;
    }
    const update = latest != null && current != null && versionNewer(latest, current);
    return {
      kind: 'github-release',
      repo,
      tag_pattern: pattern || null,
      current,
      current_source: pin.source,
      latest,
      update_available: !!update,
      error: latest == null ? 'no GitHub release tag found' : null,
    };
  } catch (e) {
    return {
      kind: 'github-release',
      repo: repo ?? null,
      tag_pattern: pattern || null,
      current,
      current_source: pin.source,
      latest: null,
      update_available: false,
      error: String(e.message || e),
    };
  }
}

export async function checkMonitor(ctx, service, monitor, appRoot) {
  switch (monitor.kind) {
    case 'dockerhub':
      return checkRegistry(ctx, service, monitor, appRoot, 'dockerhub');
    case 'ghcr':
      return checkRegistry(ctx, service, monitor, appRoot, 'ghcr');
    case 'http-scrape':
      return checkHttpScrape(ctx, service, monitor, appRoot);
    case 'pypi':
      return checkPypi(ctx, service, monitor, appRoot);
    case 'github-release':
      return checkGithubRelease(ctx, service, monitor, appRoot);
    default:
      return {
        kind: monitor.kind || 'unknown',
        update_available: false,
        error: `unsupported monitor kind: ${monitor.kind}`,
        current: resolveCurrent(service, monitor, appRoot).current,
        latest: null,
      };
  }
}

function listAppYamls(dir) {
  const out = [];
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir).sort()) {
    if (!name.startsWith('app-')) continue;
    const p = join(dir, name, 'app.yaml');
    if (existsSync(p) && statSync(p).isFile()) out.push({ appDir: name, path: p, root: join(dir, name) });
  }
  return out;
}

function composeWarnings(compose) {
  const warnings = [];
  if (!compose) return warnings;
  if (compose.error) {
    warnings.push({
      code: 'compose_parse_error',
      message: `Failed to parse ${compose.file}: ${compose.error}`,
    });
    return warnings;
  }
  const uniqueLabels = [...new Set(compose.labelVersions)];
  if (compose.xAppVersion && uniqueLabels.length && uniqueLabels.some((v) => v !== compose.xAppVersion)) {
    warnings.push({
      code: 'compose_label_mismatch',
      message: `${compose.file} x-app.version is ${compose.xAppVersion} but x-app-version label(s) are ${uniqueLabels.join(', ')}`,
    });
  }
  return warnings;
}

export async function runCheck({ appsDir, fetchImpl, timeoutMs, now } = {}) {
  if (!appsDir) throw new Error('--apps-dir required');
  const ctx = { fetchImpl, timeoutMs: timeoutMs ?? DEFAULT_TIMEOUT_MS };
  const apps = [];
  const updates = [];
  const warnings = [];
  for (const { appDir, path, root } of listAppYamls(appsDir)) {
    let doc;
    try {
      doc = yaml.load(readFileSync(path, 'utf8'));
    } catch (e) {
      apps.push({ app: appDir, path, error: String(e.message || e), services: [] });
      continue;
    }
    const appName = doc.app || appDir.replace(/^app-/, '');
    const compose = readComposeAppVersion(root);
    const appWarnings = composeWarnings(compose);
    const serviceResults = [];
    for (const svc of doc.services || []) {
      const results = [];
      for (const mon of svc.monitors || []) {
        const r = await checkMonitor(ctx, svc, mon, root);
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
        base_image: svc.base_image ?? null,
        monitors: results,
      });
    }
    const appEntry = {
      app: appName,
      path,
      compose_app_version: compose?.xAppVersion ?? null,
      compose_file: compose?.file ?? null,
      x_app_version_label: compose?.labelVersions?.[0] ?? null,
      warnings: appWarnings,
      services: serviceResults,
    };
    apps.push(appEntry);
    for (const w of appWarnings) {
      warnings.push({ app: appName, path, ...w });
    }
  }

  return {
    generated_at: (now || new Date()).toISOString?.() || new Date(now).toISOString(),
    apps_dir: appsDir,
    app_count: apps.length,
    update_count: updates.length,
    warning_count: warnings.length,
    updates,
    warnings,
    apps,
  };
}

function parseArgs(argv) {
  const args = argv.slice(2);
  let appsDir = null;
  let timeoutMs = DEFAULT_TIMEOUT_MS;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--apps-dir') appsDir = args[++i];
    else if (args[i] === '--timeout-ms') timeoutMs = parseInt(args[++i], 10);
    else if (args[i] === '-h' || args[i] === '--help') {
      return { help: true };
    } else {
      return { error: `unknown argument: ${args[i]}` };
    }
  }
  return { appsDir, timeoutMs };
}

export function isExecutedDirectly(metaUrl = import.meta.url, argv1 = process.argv[1]) {
  if (!argv1) return false;
  try {
    return metaUrl === pathToFileURL(resolvePath(argv1)).href;
  } catch {
    return false;
  }
}

export async function main(argv = process.argv) {
  const opts = parseArgs(argv);
  if (opts.help) {
    console.log('Usage: lib-check-app-versions.mjs --apps-dir <dir> [--timeout-ms N]');
    return 0;
  }
  if (opts.error) {
    console.error(`ERROR: ${opts.error}`);
    return 2;
  }
  if (!opts.appsDir) {
    console.error('ERROR: --apps-dir required');
    return 2;
  }
  const report = await runCheck({ appsDir: opts.appsDir, timeoutMs: opts.timeoutMs });
  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
  return 0;
}

if (isExecutedDirectly()) {
  main().then((code) => process.exit(code)).catch((e) => {
    console.error(`ERROR: ${e.message || e}`);
    process.exit(2);
  });
}
