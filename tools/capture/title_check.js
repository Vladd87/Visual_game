// LANTERN title-screen check: opens the game the way a player does (no
// capture mode, so every overlay and the diagnostics panel are present),
// waits for the title screen and fails if the frame is one flat colour.
//
// The capture harness (capture.js) runs in capture mode, which leaves the
// overlays out. That hid a layout bug that showed only the page background
// on the phone (test builds 3-9). Run this before every APK.
//
// Usage: node tools/capture/title_check.js [webRoot] [out.png]
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const root = path.resolve(process.argv[2] || 'app/build/web');
const out = path.resolve(process.argv[3] || 'captures/latest_title.png');
const port = 8720 + Math.floor(Math.random() * 50);
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  let file = path.join(root, url === '/' ? 'index.html' : url);
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(root, 'index.html');
  res.writeHead(200); fs.createReadStream(file).pipe(res);
}).listen(port, '127.0.0.1');
(async () => {
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 540, height: 1260 } });
  const steps = [];
  page.on('console', (m) => { const t = m.text(); if (t.includes('LANTERN_STEP') || t.includes('LANTERN_ERROR')) steps.push(t); });
  await page.goto(`http://127.0.0.1:${port}/`);
  const t0 = Date.now();
  while (Date.now() - t0 < 420000 && !steps.some((l) => l.includes('LANTERN_STEP frames'))) {
    await new Promise((r) => setTimeout(r, 3000));
  }
  await new Promise((r) => setTimeout(r, 20000));
  fs.mkdirSync(path.dirname(out), { recursive: true });
  await page.screenshot({ path: out, timeout: 240000 });
  // Flat-frame test on the decoded screenshot.
  const png = await page.evaluate(async (b64) => {
    const img = new Image(); img.src = 'data:image/png;base64,' + b64; await img.decode();
    const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
    const g = c.getContext('2d'); g.drawImage(img, 0, 0);
    const d = g.getImageData(0, 0, c.width, c.height).data;
    let min = 255, max = 0;
    for (let i = 0; i < d.length; i += 4 * 37) { const l = (d[i] * 2 + d[i + 1] * 5 + d[i + 2]) >> 3; min = Math.min(min, l); max = Math.max(max, l); }
    return { min, max };
  }, fs.readFileSync(out).toString('base64'));
  const errors = steps.filter((s) => s.includes('LANTERN_ERROR'));
  const flat = png.max - png.min < 12;
  console.log(`title screen: luma ${png.min}..${png.max}${flat ? '  FLAT (fail)' : '  ok'}; last step: ${steps.slice(-1)[0] || 'none'}${errors.length ? '; errors: ' + errors.join(' | ') : ''}`);
  await browser.close(); server.close();
  process.exit(flat || errors.length ? 1 : 0);
})();
