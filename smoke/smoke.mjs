// Real-browser smoke test against production (2026-10-17: login, connect
// and Copilot failures were found by people). Signs in as a test user and
// opens the main pages in Chromium; fails on a page error, a console error,
// a 5xx from the API, or a page that never shows its heading. Never sends a
// Copilot message, so it spends no AI credits. Without credentials it checks
// only that the app and its health endpoint answer.
//
//   SMOKE_BASE_URL=https://... SMOKE_EMAIL=... SMOKE_PASSWORD=... node smoke.mjs
import { chromium } from 'playwright';

const base = process.env.SMOKE_BASE_URL;
const email = process.env.SMOKE_EMAIL;
const password = process.env.SMOKE_PASSWORD;
if (!base) {
  console.error('smoke: set SMOKE_BASE_URL');
  process.exit(2);
}

// Each page and something on it that only renders once its data loaded.
const PAGES = [
  { path: '/dashboard', expect: { role: 'heading' } },
  { path: '/organizations/list', expect: { role: 'heading' } },
  { path: '/work?queue=mine', expect: { text: 'Mine' } },
  { path: '/communications', expect: { role: 'heading', name: 'Inbox' } },
  { path: '/settings/connections', expect: { role: 'heading', name: 'Connections' } },
  { path: '/copilot', expect: { role: 'textbox' } },
];

const failures = [];
const browser = await chromium.launch(process.env.SMOKE_CHANNEL ? { channel: process.env.SMOKE_CHANNEL } : {});
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
let current = '';
page.on('pageerror', (error) => failures.push(`${current}: page error: ${error.message}`));
page.on('console', (message) => {
  if (message.type() === 'error') failures.push(`${current}: console error: ${message.text().slice(0, 200)}`);
});
page.on('response', (response) => {
  if (response.url().includes('/api/') && response.status() >= 500) {
    failures.push(`${current}: ${response.status()} from ${new URL(response.url()).pathname}`);
  }
});

try {
  current = 'health';
  const health = await page.request.get(`${base}/api/v1/health/`);
  if (health.status() !== 200) failures.push(`health: ${health.status()}`);

  current = '/login';
  await page.goto(`${base}/login`, { waitUntil: 'networkidle' });

  if (email && password) {
    const toggle = page.getByRole('button', { name: 'Sign in with email' });
    if (await toggle.isVisible().catch(() => false)) await toggle.click();
    await page.fill('#auth-email', email);
    await page.fill('#auth-password', password);
    await page.locator('form#auth-email-form button[type="submit"]').click();
    await page.waitForURL((url) => !url.pathname.startsWith('/login'), { timeout: 30000 });

    for (const { path, expect } of PAGES) {
      current = path;
      await page.goto(`${base}${path}`, { waitUntil: 'networkidle', timeout: 45000 });
      const target = expect.text
        ? page.getByText(expect.text, { exact: true }).first()
        : page.getByRole(expect.role, expect.name ? { name: expect.name } : {}).first();
      try {
        await target.waitFor({ state: 'visible', timeout: 20000 });
        console.log(`ok ${path}`);
      } catch {
        failures.push(`${path}: never showed ${JSON.stringify(expect)}`);
      }
    }
  } else {
    console.log('smoke: no SMOKE_EMAIL/SMOKE_PASSWORD; checked the app and health only');
  }
} catch (error) {
  failures.push(`${current}: ${error.message}`);
} finally {
  await browser.close();
}

if (failures.length) {
  console.error(`smoke: ${failures.length} problem(s):\n${failures.map((f) => `  ${f}`).join('\n')}`);
  process.exit(1);
}
console.log('smoke: all good');
