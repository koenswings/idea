// Headless tests for files/idea/start.html (proposal idea#203 §2) with mocked Engines.
// Run: cd tools/client-image/tests && npm i && npm test   (CHROME=/path/to/chrome to override the browser)
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { chromium } from "playwright-core";
import fs from "node:fs"; import os from "node:os"; import path from "node:path";

const SRC = new URL("../files/idea/start.html", import.meta.url);
const CHROME = process.env.CHROME || ["/usr/bin/google-chrome", "/usr/bin/google-chrome-stable", "/usr/bin/chromium"].find(fs.existsSync);
let browser, dir;
before(async () => { dir = fs.mkdtempSync(path.join(os.tmpdir(), "idea-start-")); browser = await chromium.launch({ executablePath: CHROME, args: ["--no-sandbox"] }); });
after(async () => { await browser?.close(); fs.rmSync(dir, { recursive: true, force: true }); });

// up: hosts that answer; hang: hosts that never answer (exercise the timeout); everything else: connection refused
async function load({ home = "", up = [], hang = [], last = null, auto = true, stubNav = false }) {
  const id = Math.random().toString(36).slice(2);
  fs.writeFileSync(path.join(dir, `home-${id}.js`), `window.IDEA_HOME_ENGINE = ${JSON.stringify(home)};`);
  const html = fs.readFileSync(SRC, "utf8").replace("file:///etc/idea/home-engine.js", `home-${id}.js`);
  const file = path.join(dir, `start-${id}.html`); fs.writeFileSync(file, html);
  const ctx = await browser.newContext(); const page = await ctx.newPage();
  const requests = [];
  await page.addInitScript(([last, auto, stubNav]) => {
    window.IDEA_START_CONFIG = { timeoutMs: 300 }; if (stubNav) window.IDEA_START_CONFIG.navigate = u => { window.__nav = u; }; if (!auto) window.IDEA_START_NO_AUTO = true;
    if (last === null) localStorage.removeItem("idea.lastEngine"); else localStorage.setItem("idea.lastEngine", last);
  }, [last, auto, stubNav]);
  await page.route(/^http:\/\/[^/]*\.local\//, async route => {
    const host = new URL(route.request().url()).hostname; requests.push(host);
    if (up.includes(host)) return route.fulfill({ status: 200, contentType: "text/html", body: `<title>Console ${host}</title>` });
    if (hang.includes(host)) return; // never answers
    return route.abort("connectionrefused");
  });
  await page.goto("file://" + file);
  return { page, ctx, requests };
}
const consoleOf = page => page.waitForURL(/^http:\/\/.*\.local\/$/, { timeout: 5000 }).then(() => new URL(page.url()).hostname);

test("home Engine up: opens the home Engine's Console", async () => {
  const { page, ctx, requests } = await load({ home: "brave-otter", up: ["brave-otter.local", "idea.local"] });
  assert.equal(await consoleOf(page), "brave-otter.local");
  assert.deepEqual(requests.filter(h => h !== "brave-otter.local"), []);
  await ctx.close();
});

test("home Engine down (no answer within timeout): falls back to idea.local", async () => {
  const { page, ctx, requests } = await load({ home: "brave-otter", hang: ["brave-otter.local"], up: ["idea.local"] });
  assert.equal(await consoleOf(page), "idea.local");
  assert.deepEqual(requests.slice(0, 1), ["brave-otter.local"]);
  await ctx.close();
});

test("order is home -> last worked -> idea.local; success is remembered", async () => {
  const { page, ctx, requests } = await load({ home: "brave-otter", last: "calm-heron", up: ["calm-heron.local", "idea.local"] });
  assert.equal(await consoleOf(page), "calm-heron.local");
  assert.deepEqual(requests.slice(0, 2), ["brave-otter.local", "calm-heron.local"]);
  await ctx.close();
});

test("remembers the Engine it opened, never idea.local or invalid names", async () => {
  const run = async (opts, typed) => {
    const r = await load({ ...opts, stubNav: true, auto: !typed });
    if (typed) { await r.page.fill("#name", typed); await r.page.click("button[type=submit]"); }
    await r.page.waitForFunction(() => window.__nav, null, { timeout: 5000 });
    const out = await r.page.evaluate(() => [window.__nav, localStorage.getItem("idea.lastEngine")]);
    await r.ctx.close(); return out;
  };
  assert.deepEqual(await run({ up: ["calm-heron.local"] }, "Calm-Heron.local"), ["http://calm-heron.local/", "calm-heron"]);
  assert.deepEqual(await run({ home: "brave-otter", up: ["brave-otter.local"] }), ["http://brave-otter.local/", "brave-otter"]);
  assert.deepEqual(await run({ home: "brave-otter", last: "calm-heron", up: ["idea.local"] }), ["http://idea.local/", "calm-heron"]);
  assert.deepEqual(await run({ last: null, up: ["idea.local"] }), ["http://idea.local/", null]);
  assert.deepEqual(await run({ last: "bad_name!", up: ["idea.local"] }), ["http://idea.local/", "bad_name!"]); // invalid stored value ignored, not probed
});

test("no home Engine on the card: goes straight to idea.local", async () => {
  const { page, ctx, requests } = await load({ home: "", up: ["idea.local"] });
  assert.equal(await consoleOf(page), "idea.local"); assert.equal(requests[0], "idea.local");
  await ctx.close();
});

test("both down: friendly message, prominent sticker field, no error page", async () => {
  const { page, ctx, requests } = await load({ home: "brave-otter" });
  await page.waitForSelector("body.failed", { timeout: 5000 });
  assert.ok(page.url().startsWith("file://"));
  assert.match(await page.textContent("#notfound"), /No school server was found/);
  assert.ok(await page.isVisible("#name"));
  assert.ok(await page.evaluate(() => document.activeElement.id === "name"));
  assert.deepEqual(requests, ["brave-otter.local", "idea.local"]);
  await ctx.close();
});

test("sticker name typed: opens that Engine (case and .local normalised)", async () => {
  const { page, ctx } = await load({ up: ["calm-heron.local"], auto: false });
  await page.fill("#name", "  Calm-Heron.local "); await page.click("button[type=submit]");
  assert.equal(await consoleOf(page), "calm-heron.local");
  await ctx.close();
});

test("unknown sticker name: friendly not-found message naming it", async () => {
  const { page, ctx } = await load({ auto: false });
  await page.fill("#name", "brave-otter"); await page.click("button[type=submit]");
  await page.waitForSelector("body.failed");
  assert.match(await page.textContent("#notfound"), /No server called brave-otter was found/);
  await ctx.close();
});

test("bad input is rejected and makes no request", async () => {
  const { page, ctx, requests } = await load({ auto: false, up: ["idea.local"] });
  const bad = ["", "-otter", "otter-", "brave_otter", "brave.otter", "a".repeat(64), "évian", "x/../y", "http://idea.local", "1.2.3.4", "<b>"];
  for (const v of bad) {
    await page.fill("#name", v); await page.click("button[type=submit]");
    assert.match(await page.textContent("#fielderr"), /not a server name/, `accepted: ${JSON.stringify(v)}`);
  }
  await page.waitForTimeout(200); assert.deepEqual(requests, []); assert.ok(page.url().startsWith("file://"));
  await ctx.close();
});

test("normalise(): accepts 1-63 char labels", async () => {
  const { page, ctx } = await load({ auto: false });
  const r = await page.evaluate(() => ["a", "brave-otter", "A1-b2", "x".repeat(63), "brave-otter.local", "a--b"].map(IDEA_START.normalise));
  assert.deepEqual(r, ["a", "brave-otter", "a1-b2", "x".repeat(63), "brave-otter", "a--b"]);
  await ctx.close();
});
