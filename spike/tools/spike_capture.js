// Spike capture: load a Flutter web build, wait, screenshot, resize (fold/unfold),
// wait, screenshot again. Usage: node spike_capture.js <url> <outPrefix> [waitMs]
const { chromium } = require('playwright');
(async () => {
  const [url, out, waitArg] = process.argv.slice(2);
  const wait = parseInt(waitArg || '25000', 10);
  const browser = await chromium.launch({
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
  });
  const page = await browser.newPage({ viewport: { width: 564, height: 626 }, deviceScaleFactor: 1 });
  const logs = [];
  page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
  await page.goto(url);
  await page.waitForTimeout(wait);
  await page.screenshot({ path: `${out}_inner.png` });
  // Fold: switch to the tall cover-screen aspect without reloading.
  await page.setViewportSize({ width: 300, height: 700 });
  await page.waitForTimeout(wait / 2);
  await page.screenshot({ path: `${out}_cover.png` });
  // Unfold again.
  await page.setViewportSize({ width: 564, height: 626 });
  await page.waitForTimeout(wait / 2);
  await page.screenshot({ path: `${out}_inner2.png` });
  const gl = await page.evaluate(() => {
    const c = document.createElement('canvas');
    const g = c.getContext('webgl2');
    if (!g) return 'no webgl2';
    const e = g.getExtension('WEBGL_debug_renderer_info');
    return e ? g.getParameter(e.UNMASKED_RENDERER_WEBGL) : 'webgl2 (renderer hidden)';
  });
  logs.push(`[harness] renderer: ${gl}`);
  require('fs').writeFileSync(`${out}_console.txt`, logs.join('\n'));
  await browser.close();
})();
