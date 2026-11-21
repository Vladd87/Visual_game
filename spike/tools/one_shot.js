// One screenshot after a wait. Usage: node one_shot.js <url> <out.png> <w> <h> <waitMs>
const { chromium } = require('playwright');
(async () => {
  const [url, out, w, h, waitMs] = process.argv.slice(2);
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: +w, height: +h }, deviceScaleFactor: 1 });
  const logs = [];
  page.on('console', (m) => logs.push(m.text()));
  await page.goto(url);
  await page.waitForTimeout(+waitMs);
  await page.screenshot({ path: out });
  console.log(logs.filter((l) => l.includes('SPIKE') || l.includes('rror')).join('\n'));
  await browser.close();
})();
