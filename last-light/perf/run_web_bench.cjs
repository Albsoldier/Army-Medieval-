// Opens the exported web build in Chromium, runs ?bench, and prints the results.
const { chromium } = require('playwright');
(async () => {
  const url = process.argv[2];
  const out = process.argv[3];
  const extra = (process.argv[4] || '').split(' ').filter(Boolean);
  const browser = await chromium.launch({ headless: process.env.HEADFUL ? false : true, args: ['--ignore-gpu-blocklist', '--enable-unsafe-swiftshader', ...extra] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1 });
  const lines = [];
  page.on('console', m => { const t = m.text(); if (t.startsWith('PERF_') || /error/i.test(t)) { lines.push(t); console.log(t.slice(0, 300)); } });
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  const t0 = Date.now();
  await page.goto(url);
  const gl = await page.evaluate(() => { const c = document.createElement('canvas'); const g = c.getContext('webgl2'); if (!g) return 'no webgl2'; const d = g.getExtension('WEBGL_debug_renderer_info'); return d ? g.getParameter(d.UNMASKED_RENDERER_WEBGL) : g.getParameter(g.RENDERER); });
  console.log('WEBGL2 renderer:', gl, '| UA:', await page.evaluate(() => navigator.userAgent));
  // Wait for the game to load: time to first PERF line is the load time.
  await page.waitForFunction(() => window.perfResults && window.perfResults.length > 0, null, { timeout: 180000 });
  const loadMs = Date.now() - t0; console.log('LOAD_MS', loadMs);
  await page.waitForTimeout(2500);
  try { await page.screenshot({ path: out + '-overlay-start.png', timeout: 120000 }); } catch (e) { console.log('screenshot skipped'); }
  await page.waitForFunction(() => window.perfDone === true, null, { timeout: 600000, polling: 1000 });
  const results = await page.evaluate(() => window.perfResults);
  require('fs').writeFileSync(out + '.json', JSON.stringify({ webgl: gl, load_ms: loadMs, results }, null, 1));
  try { await page.screenshot({ path: out + '-end.png', timeout: 120000 }); } catch (e) { console.log('screenshot skipped'); }
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
