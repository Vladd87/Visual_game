// Smoke test of the real game flow on the web build (not capture mode):
// title -> BEGIN -> drag steering -> fold (resize) -> soft pause -> resume ->
// triple-tap perf overlay -> unfold. Screenshots each step into <outDir>.
// Usage: node tools/capture/smoke.js <outDir>
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '../../app/build/web');
function serve(port) {
  return new Promise((resolve) => {
    const s = http.createServer((req, res) => {
      const url = decodeURIComponent(req.url.split('?')[0]);
      let f = path.join(root, url === '/' ? 'index.html' : url);
      if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) f = path.join(root, 'index.html');
      const ext = path.extname(f);
      res.writeHead(200, { 'Content-Type': ext === '.js' || ext === '.mjs' ? 'text/javascript' : ext === '.wasm' ? 'application/wasm' : ext === '.html' ? 'text/html' : 'application/octet-stream' });
      fs.createReadStream(f).pipe(res);
    });
    s.listen(port, '127.0.0.1', () => resolve(s));
  });
}

(async () => {
  const out = path.resolve(process.argv[2] || 'smoke');
  fs.mkdirSync(out, { recursive: true });
  const port = 8900 + Math.floor(Math.random() * 90);
  const server = await serve(port);
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 432, height: 1008 }, deviceScaleFactor: 1 });
  const logs = [];
  page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
  const shot = async (name) => { await page.screenshot({ path: path.join(out, `${name}.png`) }); console.log('shot', name); };
  const label = (text) => page.getByRole('button', { name: text, exact: true }).first();
  await page.goto(`http://127.0.0.1:${port}/?semantics=1`);
  await label('BEGIN').waitFor({ timeout: 300000 });
  await page.waitForTimeout(4000);
  await shot('01_title');
  await label('BEGIN').click();
  await page.waitForTimeout(6000);
  await shot('02_playing');
  // Drag steering: hold a drag to the right for a few seconds.
  await page.mouse.move(216, 700);
  await page.mouse.down();
  for (let i = 0; i < 20; i++) { await page.mouse.move(216 + i * 4, 700); await page.waitForTimeout(150); }
  await shot('03_dragging');
  await page.mouse.up();
  await page.waitForTimeout(3000);
  // Unfold: cover -> inner-screen proportions (no reload).
  await page.setViewportSize({ width: 902, height: 1001 });
  await page.waitForTimeout(6000);
  await shot('04_unfolded_softpause');
  await label('CONTINUE').click();
  await page.waitForTimeout(5000);
  await shot('05_resumed_inner');
  // Triple tap: perf overlay.
  for (let i = 0; i < 3; i++) { await page.mouse.click(600, 600); await page.waitForTimeout(120); }
  await page.waitForTimeout(2500);
  await shot('06_perf_overlay');
  // Fold back to the cover screen.
  await page.setViewportSize({ width: 432, height: 1008 });
  await page.waitForTimeout(6000);
  await shot('07_folded_again');
  fs.writeFileSync(path.join(out, 'console.txt'), logs.join('\n'));
  const errors = logs.filter((l) => l.includes('pageerror') || l.includes('[error]'));
  console.log(`console errors: ${errors.length}`);
  errors.slice(0, 10).forEach((e) => console.log('  ', e.slice(0, 300)));
  await browser.close();
  server.close();
})();
