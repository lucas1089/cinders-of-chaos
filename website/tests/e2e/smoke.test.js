// Browser smoke test of the website: the key flows, one after the other, in headless Chromium (Playwright).
// Run it with website/tests/e2e/run.sh (a throwaway local site, or E2E_BASE_URL for staging); README "Smoke test".
//
//   E2E_BASE_URL   the site to test, e.g. http://127.0.0.1:8099/ (required)
//   E2E_SHOTS      folder for the screenshots of each flow (default: no screenshots)
//   E2E_PAY_MOCK   1 = the donation providers are "mock": also start a Pix donation and cancel it
//
// Needs Node 18+ and the npm package playwright (Apache 2.0), installed outside the repository; see run.sh.
// Every request to another host is blocked, so nothing reaches an external service (fonts, captcha, PSPs).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const BASE = (process.env.E2E_BASE_URL || '').replace(/\/?$/, '/');
const SHOTS = process.env.E2E_SHOTS || '';
const PAY_MOCK = process.env.E2E_PAY_MOCK === '1';
if (BASE === '/') {
  throw new Error('Set E2E_BASE_URL (run.sh does it for the local site).');
}
const ORIGIN = new URL(BASE).origin;

// one fresh account and character per run, so the suite can run again on the same site (names: letters only)
const stamp = Date.now().toString(36);
const letters = (s) => s.replace(/[0-9]/g, (d) => 'abcdefghij'[d]);
const ACCOUNT = 'smoke' + stamp;
const PASSWORD = 'Smoke-' + stamp + '-Pass';
const CHARACTER = 'Smoke ' + letters(stamp).replace(/^./, (c) => c.toUpperCase());

let browser, page;
const problems = [];      // page errors and PHP notices, checked after every flow
const blocked = new Set(); // other hosts the pages asked for

async function shot(name) {
  if (!SHOTS) return;
  fs.mkdirSync(SHOTS, { recursive: true });
  await page.screenshot({ path: path.join(SHOTS, name + '.png'), fullPage: true });
}

async function go(url) {
  const res = await page.goto(BASE + url, { waitUntil: 'load' });
  assert.ok(res, 'no response for ' + url);
  assert.ok(res.status() < 400, url + ' answered ' + res.status());
  await noPhpErrors(url);
  return res;
}

async function submit(locator) {
  await Promise.all([page.waitForNavigation({ waitUntil: 'load' }), locator.click()]);
  await noPhpErrors(page.url());
}

async function noPhpErrors(where) {
  const body = await page.innerText('body');
  const m = body.match(/(Fatal error|Parse error|Warning|Notice|Deprecated|Uncaught \w+):\s[^\n]{0,160}/);
  if (m) problems.push(where + ': ' + m[0]);
}

function noProblems() {
  const p = problems.splice(0);
  assert.deepEqual(p, [], 'page errors:\n' + p.join('\n'));
}

async function text() {
  return (await page.innerText('body')).replace(/\s+/g, ' ');
}

test.before(async () => {
  browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, locale: 'en-US' });
  await context.route('**/*', (route) => {
    const u = new URL(route.request().url());
    if (u.origin === ORIGIN || u.protocol === 'data:') return route.continue();
    blocked.add(u.host);
    return route.abort();
  });
  page = await context.newPage();
  page.on('pageerror', (e) => problems.push('JS: ' + e.message));
});

test.after(async () => {
  if (blocked.size) console.log('# other hosts blocked: ' + [...blocked].sort().join(', '));
  if (browser) await browser.close();
});

test('1. home page', async () => {
  await go('');
  assert.match(await page.title(), /Cinders of Chaos/);
  const t = await text();
  for (const s of ['WIKI', 'DONATE', 'REGISTER']) assert.ok(t.toUpperCase().includes(s), 'menu entry ' + s);
  assert.ok(await page.locator('form.loginForm input[name=username]').count(), 'login box');
  await shot('01-home');
  noProblems();
});

test('2. account creation', async () => {
  await go('register');
  const f = page.locator('form:has(input[name=password_again])');
  await f.locator('input[name=username]').fill(ACCOUNT);
  await f.locator('input[name=password]').fill(PASSWORD);
  await f.locator('input[name=password_again]').fill(PASSWORD);
  await f.locator('input[name=email]').fill(ACCOUNT + '@example.invalid');
  await f.locator('select[name=flag]').selectOption('br');
  if (await f.locator('select[name=selected]').count()) await f.locator('select[name=selected]').selectOption('1');
  if (await f.locator('input[name=chaos_accept_terms]').count()) await f.locator('input[name=chaos_accept_terms]').check();
  await shot('02-register-form');
  await submit(f.locator('[type=submit]'));
  assert.match(page.url(), /\/register\?success/, 'account created: ' + (await text()).slice(0, 400));
  assert.match(await text(), /account has been created/i);
  await shot('02-register-done');
  noProblems();
});

test('3. login', async () => {
  await go('');
  await page.fill('form.loginForm input[name=username]', ACCOUNT);
  await page.fill('form.loginForm input[name=password]', PASSWORD);
  await submit(page.locator('form.loginForm [type=submit]'));
  if (await page.locator('input[name=chaos_accept_terms]').count()) {   // the Terms gate, if the site asks again
    await page.locator('input[name=chaos_accept_terms]').check();
    await submit(page.locator('form:has(input[name=chaos_accept_terms]) [type=submit]'));
  }
  assert.match(page.url(), /\/myaccount(\?|$)/, 'lands on My Account');
  assert.ok((await text()).includes(ACCOUNT), 'the account name is shown');
  await shot('03-login-myaccount');
  noProblems();
});

test('4. character creation, character list and character page', async () => {
  await go('createcharacter');
  const f = page.locator('form:has(input[name=selected_vocation])');
  assert.ok(await f.locator('input[name=selected_vocation]').count() >= 1, 'class choice');
  await f.locator('input[name=name]').fill(CHARACTER);
  await f.locator('input[name=selected_vocation]').first().check({ force: true });
  await shot('04-create-character-form');
  await submit(f.locator('[type=submit]'));
  assert.match(page.url(), /\/createcharacter\?success/, 'character created: ' + (await text()).slice(0, 400));

  await go('myaccount');
  assert.ok((await text()).includes(CHARACTER), 'the character list has the new character');
  await shot('04-character-list');

  await go('characterprofile?name=' + encodeURIComponent(CHARACTER));
  const t = await text();
  assert.ok(t.includes(CHARACTER), 'character page: name');
  assert.match(t, /Level\s*1\b/i, 'character page: level');
  await shot('04-character-page');
  noProblems();
});

test('5. donation page: voluntary donation label and payment buttons', async () => {
  for (const [lang, label, button] of [
    ['en', 'Voluntary donation', /^\s*Donate\b/i],
    ['pt-BR', 'Doação voluntária', /^\s*Doar\b/i],
  ]) {
    await go('page?plugin=chaos&p=coins&l=' + lang);
    const t = await text();
    assert.ok(t.includes(label), lang + ': the voluntary donation label');
    assert.ok(t.includes('Nobody is required to donate') && t.includes('Ninguém é obrigado a doar'), lang + ': both texts');
    if (lang === 'pt-BR') assert.ok(!/\bup to \d+ extra\b|\bdouble Chaos Coins\b/.test(t), 'pt-BR: the first donation bonus is translated');
    const pix = page.locator('form:has(input[name=chaos_pay_method][value=pix]) [type=submit]');
    const paypal = page.locator('form:has(input[name=chaos_pay_method][value=paypal]) [type=submit]');
    if (PAY_MOCK) {
      assert.ok(await pix.count() >= 1 && await paypal.count() >= 1, lang + ': Pix and PayPal buttons');
      assert.match(await pix.first().innerText(), button, lang + ': the button says donate');
    }
    await shot('05-donate-' + lang);
  }
  if (PAY_MOCK) {   // a Pix donation with the mock provider: the order page, then cancel it (nothing leaves the site)
    await go('page?plugin=chaos&p=coins&l=en');
    await submit(page.locator('form:has(input[name=chaos_pay_method][value=pix]) [type=submit]').first());
    assert.match(await text(), /Pix copy and paste/i, 'the order: the Pix copy-and-paste code');
    await shot('05-donate-pix-order');
    const cancel = page.locator('a:has-text("Cancel this donation")');
    if (await cancel.count()) {
      await submit(cancel.first());
      const yes = page.locator('form [type=submit]:has-text("Yes, cancel it")');
      if (await yes.count()) await submit(yes.first());
    }
  }
  noProblems();
});

test('6. wiki and the language switch pt-BR / en', async () => {
  await go('page?plugin=chaos&p=wiki&l=pt-BR');
  assert.ok((await text()).includes('Guias'), 'pt-BR index');
  await shot('06-wiki-pt-BR');
  await submit(page.locator('a.chaos-wiki-lang[lang=en]'));
  assert.match(page.url(), /l=en/);
  assert.ok((await text()).includes('Guides'), 'English index');
  await shot('06-wiki-en');
  await submit(page.locator('a[href*="t=guide%3Astart"]').first());
  assert.ok((await text()).includes('Getting started'), 'a guide page');
  await submit(page.locator('a.chaos-wiki-lang[lang="pt-BR"]'));   // Portuguese is the default: no l= in the link
  assert.ok((await text()).includes('Primeiros passos'), 'the same guide in Portuguese');
  await shot('06-wiki-guide-pt-BR');
  await go('page?plugin=chaos&p=wiki&l=en&q=' + encodeURIComponent('rift'));
  assert.ok(await page.locator('mark').count() >= 1, 'search marks its hits');
  noProblems();
});

test('7. Character Bazaar list', async () => {
  await go('page?plugin=chaos&p=bazaar&l=en');
  let t = await text();
  assert.ok(t.toUpperCase().includes('CHARACTER BAZAAR'), 'title');
  assert.ok(/Open auctions/i.test(t), 'the auctions tab');
  assert.ok(/No auctions right now|BUYOUT/i.test(t), 'the list or its empty state');
  await shot('07-bazaar-en');
  await submit(page.locator('a.chaos-lang-switch').first());
  t = await text();
  assert.ok(/Leilões abertos/.test(t), 'Portuguese');
  await shot('07-bazaar-pt-BR');
  noProblems();
});
