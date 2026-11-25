// Runs the real-GPU validation (index.html?gpuval=1) in Chromium and saves
// the downloaded results. Mainly for checking the test itself; on a laptop,
// just open the URL in Chrome. Usage:
//   node run_gpu_validation.cjs "http://localhost:8794/index.html?gpuval=1[&quick=1]" out.json ["--chromium flags"]
const { chromium } = require('playwright');
(async () => {
  const url = process.argv[2];
  const out = process.argv[3];
  const extra = (process.argv[4] || '').split(' ').filter(Boolean);
  const browser = await chromium.launch({ headless: !process.env.HEADFUL, args: ['--ignore-gpu-blocklist', ...extra] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1, acceptDownloads: true });
  page.on('console', m => { const t = m.text(); if (t.startsWith('GPUVAL') || /error/i.test(t)) console.log(t.slice(0, 400)); });
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  const download = page.waitForEvent('download', { timeout: 0 });
  await page.goto(url);
  const d = await download;
  await d.saveAs(out);
  await page.screenshot({ path: out.replace(/\.json$/, '') + '-summary.png' });
  console.log('SAVED', out);
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
