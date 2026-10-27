// stock-ui.mjs — the committed CDP step of idea-router-flash (idea#277): drives the Cudy STOCK web UI in a headless
// Chromium that idea-router-flash started (it owns the browser and its throwaway profile and removes both on exit).
// No npm dependencies: Chrome DevTools Protocol over the WebSocket built into Node (Node >= 22, or
// Node 20/21 with --experimental-websocket; idea-router-flash passes the flag when needed).
//
//   node stock-ui.mjs backup   (env OUT_DIR)                         save the stock config backup into OUT_DIR
//   node stock-ui.mjs upload   (env IMAGE, EXPECT_MD5, EXPECT_SIZE)  upload the intermediate image, check the MD5
//                                                                     and size the page shows, then click proceed
// Common env: CDP_PORT_FILE (DevToolsActivePort of the browser), STOCK_URL, STOCK_LOGIN_PATH, STOCK_UPGRADE_PATH,
//             STOCK_BACKUP_PATH, STOCK_PASSWORD_FILE (optional; the stock admin password, read here, never printed).
// Exit: 0 ok, 3 usage/env, 5 page/step failed, 6 MISMATCH (MD5/size shown by the page differs; nothing proceeded).
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { basename } from 'node:path';

const env = process.env;
const action = process.argv[2];
const say = (m) => console.log(`stock-ui: ${m}`);
const fail = (rc, m) => { console.error(`stock-ui: FAIL ${m}`); process.exit(rc); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const timeoutMs = Number(env.STOCK_TIMEOUT_MS || 60000);

if (!['backup', 'upload'].includes(action)) fail(3, 'usage: stock-ui.mjs backup|upload');
if (typeof WebSocket !== 'function') fail(3, 'no WebSocket in this Node (need >= 22 or --experimental-websocket)');
const base = (env.STOCK_URL || 'http://192.168.10.1').replace(/\/$/, '');

// ---- minimal CDP client ----
const port = readFileSync(env.CDP_PORT_FILE, 'utf8').split('\n')[0].trim();
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
let page = targets.find((t) => t.type === 'page');
if (!page) page = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json();
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error('CDP connect failed')); });
let nextId = 1; const pending = new Map(); const waiters = [];
ws.onmessage = (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) {
    const { res, rej } = pending.get(msg.id); pending.delete(msg.id);
    msg.error ? rej(new Error(`${msg.error.message}`)) : res(msg.result);
  } else if (msg.method) {
    for (const w of waiters.splice(0)) (w.method === msg.method ? w.res(msg.params) : waiters.push(w));
  }
};
const send = (method, params = {}) => new Promise((res, rej) => {
  const id = nextId++; pending.set(id, { res, rej }); ws.send(JSON.stringify({ id, method, params }));
});
const once = (method, ms = timeoutMs) => new Promise((res, rej) => {
  const w = { method, res }; waiters.push(w);
  setTimeout(() => rej(new Error(`timeout waiting for ${method}`)), ms);
});
const evaluate = async (expression) => {
  const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(`page script failed: ${r.exceptionDetails.text}`);
  return r.result.value;
};
const goto = async (url) => { const l = once('Page.loadEventFired'); await send('Page.navigate', { url }); await l; };
// Click the first button/link whose text or value matches re (a source string), and wait for the next page load.
const clickText = async (re, waitLoad = true) => {
  const l = waitLoad ? once('Page.loadEventFired') : null;
  const ok = await evaluate(`(() => { const re = new RegExp(${JSON.stringify(re)}, 'i');
    const els = [...document.querySelectorAll('button, input[type=submit], input[type=button], a')];
    const el = els.find((e) => re.test((e.innerText || e.value || '').trim()));
    if (!el) return false; el.click(); return true; })()`);
  if (!ok) throw new Error(`no button matching /${re}/ on ${await evaluate('location.pathname')}`);
  if (l) await l;
};

async function login() {
  const hasPw = await evaluate("!!document.querySelector('input[type=password]')");
  if (!hasPw) return;
  if (!env.STOCK_PASSWORD_FILE) throw new Error('stock UI asks for a password; set IDEA_STOCK_PASSWORD_FILE');
  const pw = readFileSync(env.STOCK_PASSWORD_FILE, 'utf8').split('\n')[0];
  const l = once('Page.loadEventFired');
  // The password goes only over the local CDP socket into the page, never to argv, stdout or a log.
  await evaluate(`(() => { const p = document.querySelector('input[type=password]'); p.value = ${JSON.stringify(pw)};
    p.dispatchEvent(new Event('input', { bubbles: true }));
    const f = p.form; const b = f && f.querySelector('button[type=submit], input[type=submit], button');
    if (b) b.click(); else if (f) f.submit(); })()`);
  await l;
  if (await evaluate("!!document.querySelector('input[type=password]')")) throw new Error('stock UI login failed');
  say('logged in to stock UI');
}

async function open(path) {
  await goto(base + path);
  if (await evaluate("!!document.querySelector('input[type=password]')")) { await login(); await goto(base + path); }
}

try {
  await send('Page.enable'); await send('Runtime.enable'); await send('DOM.enable');
  await goto(base + (env.STOCK_LOGIN_PATH || '/'));
  await login();
  if (action === 'backup') {
    const dir = env.OUT_DIR; if (!dir) fail(3, 'OUT_DIR not set');
    await send('Page.setDownloadBehavior', { behavior: 'allow', downloadPath: dir });
    await open(env.STOCK_BACKUP_PATH || '/cgi-bin/luci/admin/system/backup');
    const before = new Set(readdirSync(dir));
    await clickText(env.STOCK_BACKUP_BUTTON || '^(backup|export|download|generate)', false);
    const t0 = Date.now(); let got = null;
    while (Date.now() - t0 < timeoutMs && !got) {
      await sleep(250);
      got = readdirSync(dir).find((f) => !before.has(f) && !f.endsWith('.crdownload') && statSync(`${dir}/${f}`).size > 0);
    }
    if (!got) throw new Error('stock config backup did not download');
    say(`backup saved: ${got}`);
    console.log(`DOWNLOADED=${got}`);
  } else {
    const { IMAGE, EXPECT_MD5, EXPECT_SIZE } = env;
    if (!IMAGE || !EXPECT_MD5 || !EXPECT_SIZE) fail(3, 'IMAGE, EXPECT_MD5 and EXPECT_SIZE must be set');
    await open(env.STOCK_UPGRADE_PATH || '/cgi-bin/luci/admin/setup?active=autoupgrade');
    const { root } = await send('DOM.getDocument', { depth: -1 });
    const { nodeId } = await send('DOM.querySelector', { nodeId: root.nodeId, selector: 'input[type=file]' });
    if (!nodeId) throw new Error('no file input on the upgrade page');
    await send('DOM.setFileInputFiles', { nodeId, files: [IMAGE] });
    say(`file set: ${basename(IMAGE)}`);
    const l = once('Page.loadEventFired');
    await evaluate(`(() => { const i = document.querySelector('input[type=file]'); i.dispatchEvent(new Event('change', { bubbles: true }));
      const f = i.form; const b = f && f.querySelector('button[type=submit], input[type=submit]');
      if (b) b.click(); else if (f) f.submit(); })()`);
    await l;
    // The page must show the same MD5 and size as the file we checked locally, else refuse (nothing is flashed).
    const text = (await evaluate('document.body.innerText')).toLowerCase();
    const digits = text.replace(/(\d)[,.\s](?=\d{3}\b)/g, '$1');
    const md5ok = text.includes(EXPECT_MD5.toLowerCase());
    const sizeok = new RegExp(`\\b${EXPECT_SIZE}\\b`).test(digits);
    if (!md5ok || !sizeok) fail(6, `MISMATCH page shows md5 ${md5ok ? 'ok' : 'DIFFERENT'}, size ${sizeok ? 'ok' : 'DIFFERENT'}; not proceeding`);
    say(`page shows md5 ${EXPECT_MD5} and size ${EXPECT_SIZE}: ok`);
    await clickText(env.STOCK_PROCEED_BUTTON || '^(proceed|continue|confirm|upgrade|ok)', false);
    await sleep(1000);
    say('proceed clicked; router is flashing the intermediate image');
  }
  ws.close(); process.exit(0);
} catch (e) {
  fail(5, e.message);
}
