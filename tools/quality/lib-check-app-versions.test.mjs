#!/usr/bin/env node
/**
 * Unit tests for lib-check-app-versions.mjs (idea#543).
 * Network calls are mocked; run via tools/quality/check-app-versions.test.sh
 * or: (cd tools/quality && npm test)
 */
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cmpVersion,
  versionNewer,
  newestMatching,
  parseVersionFields,
  parseLinkNext,
  resolveLinkNext,
  parseImageRef,
  parseDockerfileFrom,
  readComposeAppVersion,
  resolveCurrent,
  runCheck,
} from './lib-check-app-versions.mjs';

test('parseVersionFields is numeric per dotted field', () => {
  assert.deepEqual(parseVersionFields('24.04.13.2'), [24, 4, 13, 2]);
  assert.deepEqual(parseVersionFields('6.4.14.3'), [6, 4, 14, 3]);
  assert.deepEqual(parseVersionFields('31-apache'), [31]);
  assert.deepEqual(parseVersionFields('v0.19.5'), [0, 19, 5]);
  assert.deepEqual(parseVersionFields('22-alpine'), [22]);
});

test('cmpVersion: 24.04.13.2 is greater than 6.4.14.3 (collabora false latest)', () => {
  assert.equal(cmpVersion('24.04.13.2', '6.4.14.3'), 1);
  assert.equal(cmpVersion('6.4.14.3', '24.04.13.2'), -1);
  assert.equal(cmpVersion('11.8', '11.7'), 1);
  assert.equal(cmpVersion('35-apache', '31-apache'), 1);
  assert.equal(cmpVersion('v0.19.5', '0.19.5'), 0);
  assert.equal(cmpVersion('22-alpine', '22-alpine'), 0);
});

test('versionNewer flags only when latest > current', () => {
  assert.equal(versionNewer('24.04.13.2', '6.4.14.3'), true);
  assert.equal(versionNewer('6.4.14.3', '24.04.13.2'), false);
  assert.equal(versionNewer('22-alpine', '22-alpine'), false);
  // Equal numeric fields, different spelling (v prefix) must not flag
  assert.equal(versionNewer('v0.19.5', '0.19.5'), false);
  assert.equal(versionNewer('11.8', '11.7'), true);
  assert.equal(versionNewer(null, '11.7'), false);
});

test('newestMatching picks the numeric max, not string or list order', () => {
  const tags = [
    'latest',
    '6.4.14.3',
    '6.4.16.1',
    '24.04.10.4',
    '24.04.13.2',
    'sha256-deadbeef.sig',
  ];
  assert.equal(newestMatching(tags, '^\\d+\\.\\d+\\.\\d+\\.\\d+$'), '24.04.13.2');
  assert.equal(newestMatching(['31-apache', '35-apache', 'latest'], '^\\d+-apache$'), '35-apache');
  assert.equal(newestMatching(['10.6', '10.11', '11.7', '11.8'], '^11\\.\\d+$'), '11.8');
  // Collabora CODE tags since 21.11 are five-part (24.04.13.2.1, 26.04.6.1.1)
  assert.equal(
    newestMatching(
      ['6.4.14.3', '24.04.13.2.1', '24.04.13.3.1', '26.04.6.1.1', 'latest'],
      '^\\d+\\.\\d+\\.\\d+\\.\\d+(\\.\\d+)?$',
    ),
    '26.04.6.1.1',
  );
});

test('parseLinkNext reads rel=next from a Link header', () => {
  const link = '<https://ghcr.io/v2/kiwix/kiwix-serve/tags/list?n=1000&last=3.8.0>; rel="next", <https://ghcr.io/v2/kiwix/kiwix-serve/tags/list?n=1000>; rel="first"';
  assert.equal(
    parseLinkNext(link),
    'https://ghcr.io/v2/kiwix/kiwix-serve/tags/list?n=1000&last=3.8.0',
  );
  assert.equal(parseLinkNext(null), null);
  assert.equal(parseLinkNext(''), null);
  // Docker Hub registry returns a relative next path
  assert.equal(
    resolveLinkNext(
      '</v2/library/node/tags/list?last=12.14.1-slim&n=1000>; rel="next"',
      'https://registry-1.docker.io/v2/library/node/tags/list',
    ),
    'https://registry-1.docker.io/v2/library/node/tags/list?last=12.14.1-slim&n=1000',
  );
});

test('parseImageRef and Dockerfile FROM', () => {
  assert.deepEqual(parseImageRef('node:22-alpine'), {
    image: 'node', tag: '22-alpine', digest: null,
  });
  assert.deepEqual(parseImageRef('node:22-alpine@sha256:abc'), {
    image: 'node', tag: '22-alpine', digest: 'sha256:abc',
  });
  const from = parseDockerfileFrom(
    '# comment\nFROM node:22-alpine AS runner\nWORKDIR /app\n',
  );
  assert.deepEqual(from, { image: 'node', tag: '22-alpine', digest: null });
});

test('resolveCurrent uses base_image / upstream_tag, not App current_version, for dockerhub', () => {
  const milk = resolveCurrent(
    { current_version: '1.0.65', base_image: 'node:22-alpine' },
    { kind: 'dockerhub', repo: 'library/node', tag_pattern: '^22-alpine$' },
    null,
  );
  assert.equal(milk.current, '22-alpine');
  assert.equal(milk.source, 'base_image');

  const nc = resolveCurrent(
    { current_version: '1.0-24.04.13.2', upstream_tag: '24.04.13.2' },
    { kind: 'dockerhub', repo: 'collabora/code', tag_pattern: '^\\d+\\.\\d+\\.\\d+\\.\\d+$' },
    null,
  );
  assert.equal(nc.current, '24.04.13.2');
  assert.equal(nc.source, 'upstream_tag');

  const missing = resolveCurrent(
    { current_version: '1.0.65' },
    { kind: 'dockerhub', repo: 'library/node', tag_pattern: '^22-alpine$' },
    null,
  );
  assert.equal(missing.current, null);
  assert.equal(missing.source, null);
});

function writeApp(root, name, { appYaml, composeYaml, dockerfile } = {}) {
  const dir = join(root, name);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'app.yaml'), appYaml);
  if (composeYaml) writeFileSync(join(dir, 'compose.yaml'), composeYaml);
  if (dockerfile) {
    mkdirSync(join(dir, 'app'), { recursive: true });
    writeFileSync(join(dir, 'app/Dockerfile'), dockerfile);
  }
}

function composeStub(name, version) {
  return `x-app:\n  name: ${name}\n  version: "${version}"\nservices:\n  ${name}:\n    image: example/${name}\n    labels:\n      x-app-version: "${version}"\n`;
}

function mockFetch(routes) {
  return async (url) => {
    for (const [pattern, body] of routes) {
      if (typeof pattern === 'string' ? url === pattern : pattern.test(url)) {
        const headers = body.headers || {};
        const text = typeof body.text === 'string' ? body.text : JSON.stringify(body.json ?? body);
        const status = body.status ?? 200;
        return { ok: status >= 200 && status < 300, status, text, headers };
      }
    }
    return { ok: false, status: 404, text: 'not found', headers: {} };
  };
}

test('runCheck: milkwise exact base tag is not an update; collabora picks numeric max; ghcr/pypi work; leftover idea_app_version is ignored', async () => {
  const root = mkdtempSync(join(tmpdir(), 'check-app-versions-'));
  try {
    writeApp(root, 'app-milkwise', {
      appYaml: `app: milkwise
idea_app_version: "1.0"
services:
  - name: milkwise
    build: custom
    dockerfile: app/Dockerfile
    base_image: node:22-alpine
    image: koenswings/milkwise
    current_version: "1.0.65"
    monitors:
      - kind: dockerhub
        repo: library/node
        tag_pattern: "^22-alpine$"
`,
      composeYaml: composeStub('milkwise', '1.0'),
      dockerfile: 'FROM node:22-alpine AS runner\n',
    });
    writeApp(root, 'app-nextcloud', {
      appYaml: `app: nextcloud
idea_app_version: "1.0"
services:
  - name: nextcloud-code
    build: retag
    upstream_tag: "24.04.13.2"
    current_version: "1.0-24.04.13.2"
    monitors:
      - kind: dockerhub
        repo: collabora/code
        tag_pattern: "^\\\\d+\\\\.\\\\d+\\\\.\\\\d+\\\\.\\\\d+$"
  - name: nextcloud-app
    build: retag
    upstream_tag: "31-apache"
    current_version: "1.0-31.0.1"
    monitors:
      - kind: dockerhub
        repo: library/nextcloud
        tag_pattern: "^\\\\d+-apache$"
`,
      composeYaml: composeStub('nextcloud', '1.7-31.0.1'),
    });
    writeApp(root, 'app-kiwix', {
      appYaml: `app: kiwix
idea_app_version: "1.0"
services:
  - name: kiwix
    build: retag
    upstream_tag: "3.8.2"
    current_version: "1.0-3.8.2"
    monitors:
      - kind: ghcr
        repo: kiwix/kiwix-serve
        tag_pattern: "^\\\\d+\\\\.\\\\d+\\\\.\\\\d+$"
`,
      composeYaml: composeStub('kiwix', '1.3-3.8.2'),
    });
    writeApp(root, 'app-kolibri', {
      appYaml: `app: kolibri
idea_app_version: "1.0"
services:
  - name: kolibri
    build: retag
    upstream_tag: "0.19.5"
    current_version: "1.3-0.19.5"
    monitors:
      - kind: pypi
        package: kolibri
`,
      composeYaml: composeStub('kolibri', '1.3-0.19.5'),
    });

    const fetchImpl = mockFetch([
      [
        'https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/node:pull',
        { json: { token: 'hub-token' } },
      ],
      [
        'https://registry-1.docker.io/v2/library/node/tags/list',
        { json: { tags: ['22-alpine', '24-alpine', 'latest'] } },
      ],
      [
        'https://auth.docker.io/token?service=registry.docker.io&scope=repository:collabora/code:pull',
        { json: { token: 'hub-token' } },
      ],
      [
        'https://registry-1.docker.io/v2/collabora/code/tags/list',
        { json: { tags: ['latest', '6.4.14.3', '6.4.16.1', '24.04.13.2', 'sha256-abcd.sig'] } },
      ],
      [
        'https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/nextcloud:pull',
        { json: { token: 'hub-token' } },
      ],
      [
        'https://registry-1.docker.io/v2/library/nextcloud/tags/list',
        { json: { tags: ['31-apache', '35-apache', 'latest'] } },
      ],
      [
        'https://ghcr.io/token?scope=repository:kiwix/kiwix-serve:pull',
        { json: { token: 'test-token' } },
      ],
      [
        'https://ghcr.io/v2/kiwix/kiwix-serve/tags/list?n=1000',
        {
          json: { name: 'kiwix/kiwix-serve', tags: ['3.7.0', 'latest'] },
          headers: {
            link: '<https://ghcr.io/v2/kiwix/kiwix-serve/tags/list?n=1000&last=3.7.0>; rel="next"',
          },
        },
      ],
      [
        'https://ghcr.io/v2/kiwix/kiwix-serve/tags/list?n=1000&last=3.7.0',
        { json: { name: 'kiwix/kiwix-serve', tags: ['3.8.2', '3.8.1'] } },
      ],
      [
        'https://pypi.org/pypi/kolibri/json',
        { json: { info: { version: '0.19.5' } } },
      ],
    ]);

    const report = await runCheck({ appsDir: root, fetchImpl, now: new Date('2026-11-15T18:00:00Z') });

    const byApp = Object.fromEntries(report.apps.map((a) => [a.app, a]));
    assert.equal(report.app_count, 4);

    const milkMon = byApp.milkwise.services[0].monitors[0];
    assert.equal(milkMon.current, '22-alpine');
    assert.equal(milkMon.latest, '22-alpine');
    assert.equal(milkMon.update_available, false);
    assert.equal(milkMon.error, null);
    assert.equal(byApp.milkwise.warnings.length, 0);
    assert.equal(byApp.milkwise.compose_app_version, '1.0');

    const codeMon = byApp.nextcloud.services.find((s) => s.name === 'nextcloud-code').monitors[0];
    assert.equal(codeMon.latest, '24.04.13.2');
    assert.equal(codeMon.current, '24.04.13.2');
    assert.equal(codeMon.update_available, false);

    const ncAppMon = byApp.nextcloud.services.find((s) => s.name === 'nextcloud-app').monitors[0];
    assert.equal(ncAppMon.latest, '35-apache');
    assert.equal(ncAppMon.update_available, true);

    const kiwixMon = byApp.kiwix.services[0].monitors[0];
    assert.equal(kiwixMon.kind, 'ghcr');
    assert.equal(kiwixMon.error, null);
    assert.equal(kiwixMon.latest, '3.8.2');
    assert.equal(kiwixMon.update_available, false);

    const kolibriMon = byApp.kolibri.services[0].monitors[0];
    assert.equal(kolibriMon.kind, 'pypi');
    assert.equal(kolibriMon.error, null);
    assert.equal(kolibriMon.latest, '0.19.5');
    assert.equal(kolibriMon.current, '0.19.5');
    assert.equal(kolibriMon.update_available, false);

    // leftover app.yaml idea_app_version is ignored (compose x-app.version is the only App version)
    for (const app of ['nextcloud', 'kiwix', 'kolibri', 'milkwise']) {
      assert.equal('idea_app_version' in byApp[app], false);
      assert.ok(!(byApp[app].warnings || []).some((w) => w.code === 'idea_app_version_mismatch'));
    }
    assert.equal(byApp.nextcloud.compose_app_version, '1.7-31.0.1');
    assert.equal(byApp.kiwix.compose_app_version, '1.3-3.8.2');
    assert.equal(byApp.kolibri.compose_app_version, '1.3-0.19.5');
    assert.deepEqual(report.updates.map((u) => `${u.app}:${u.service}:${u.latest}`), [
      'nextcloud:nextcloud-app:35-apache',
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('runCheck: github-release and a newer pypi version report an update', async () => {
  const root = mkdtempSync(join(tmpdir(), 'check-app-versions-gh-'));
  try {
    writeApp(root, 'app-kolibri', {
      appYaml: `app: kolibri
idea_app_version: "1.3-0.19.5"
services:
  - name: kolibri
    upstream_tag: "0.19.5"
    monitors:
      - kind: github-release
        repo: learningequality/kolibri
      - kind: pypi
        package: kolibri
`,
      composeYaml: composeStub('kolibri', '1.3-0.19.5'),
    });
    const fetchImpl = mockFetch([
      [
        'https://api.github.com/repos/learningequality/kolibri/releases/latest',
        { json: { tag_name: 'v0.19.5' } },
      ],
      [
        'https://pypi.org/pypi/kolibri/json',
        { json: { info: { version: '0.20.0' } } },
      ],
    ]);
    const report = await runCheck({ appsDir: root, fetchImpl });
    const mons = report.apps[0].services[0].monitors;
    assert.equal(mons[0].kind, 'github-release');
    assert.equal(mons[0].latest, 'v0.19.5');
    assert.equal(mons[0].update_available, false);
    assert.equal(mons[1].latest, '0.20.0');
    assert.equal(mons[1].update_available, true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('readComposeAppVersion reads x-app.version and labels', () => {
  const root = mkdtempSync(join(tmpdir(), 'compose-ver-'));
  try {
    writeFileSync(join(root, 'compose.yaml'), composeStub('kiwix', '1.3-3.8.2'));
    const got = readComposeAppVersion(root);
    assert.equal(got.file, 'compose.yaml');
    assert.equal(got.xAppVersion, '1.3-3.8.2');
    assert.deepEqual(got.labelVersions, ['1.3-3.8.2']);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
