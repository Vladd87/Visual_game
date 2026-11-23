// LANTERN capture harness (PLAN.md §5).
//
// Serves app/build/web, then for every shot and aspect opens a FRESH page with
// ?capture=<shot>, waits until the app signals the shot has settled (document
// title "LANTERN_READY ..."), screenshots it, and rejects blank or flat frames:
// a blank canvas is a harness bug, never a scene result.
//
// Usage: node tools/capture/capture.js <outDir> [--shots 1,2,..] [--aspects inner,cover]
//                                       [--seed 2026] [--scale 0.5] [--frames 90]
//                                       [--root <web build dir>]   (default app/build/web)
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ASPECTS = {
  // Full device sizes; rendered at --scale (default half) because SwiftShader is slow.
  inner: { width: 2256, height: 2504, hinge: true },
  cover: { width: 1080, height: 2520, hinge: false },
};


// Android only guarantees 16 fragment samplers; this browser (SwiftShader)
// allows 32, so a shader that cannot run on the phone would still render
// here. Count the sampler uniforms of every linked program and flag any
// program over the limit (counts both stages: conservative).
const SAMPLER_GUARD = `(() => {
  const S = new Set([0x8B5E,0x8B5F,0x8B60,0x8B62,0x8DC1,0x8DC4,0x8DC5,0x8DCA,0x8DCB,0x8DCC,0x8DCF,0x8DD2,0x8DD3,0x8DD4,0x8DD7]);
  window.__maxSamplers = 0;
  const link = WebGL2RenderingContext.prototype.linkProgram;
  WebGL2RenderingContext.prototype.linkProgram = function (prog) {
    link.call(this, prog);
    try {
      let n = 0;
      const count = this.getProgramParameter(prog, this.ACTIVE_UNIFORMS) || 0;
      for (let i = 0; i < count; i++) {
        const u = this.getActiveUniform(prog, i);
        if (u && S.has(u.type)) n += u.size;
      }
      window.__maxSamplers = Math.max(window.__maxSamplers, n);
      if (n > 16) console.error('SAMPLER_LIMIT program uses ' + n + ' samplers (Android guarantees 16)');
    } catch (e) {}
  };
})();`;

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : def;
}

function serve(root, port) {
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
    '.wasm': 'application/wasm', '.png': 'image/png', '.frag': 'application/octet-stream', '.otf': 'font/otf', '.ttf': 'font/ttf' };
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const url = decodeURIComponent(req.url.split('?')[0]);
      let file = path.join(root, url === '/' ? 'index.html' : url);
      if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(root, 'index.html');
      res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
      fs.createReadStream(file).pipe(res);
    });
    // A random port can be taken (another harness running): try the next.
    let tries = 0;
    server.on('error', (e) => {
      if (e.code !== 'EADDRINUSE' || ++tries > 20) throw e;
      server.listen(++port, '127.0.0.1');
    });
    server.listen(port, '127.0.0.1', () => resolve(server));
  });
}

async function lumaStats(page, buf) {
  // Decode the screenshot PNG inside the page (no extra deps) and sample luma.
  const b64 = buf.toString('base64');
  return page.evaluate(async (data) => {
    const img = new Image();
    img.src = 'data:image/png;base64,' + data;
    await img.decode();
    const c = document.createElement('canvas');
    c.width = img.width; c.height = img.height;
    const g = c.getContext('2d');
    g.drawImage(img, 0, 0);
    const px = g.getImageData(0, 0, c.width, c.height).data;
    let n = 0, sum = 0, sum2 = 0;
    for (let i = 0; i < px.length; i += 4 * 7) {
      const y = 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2];
      sum += y; sum2 += y * y; n++;
    }
    const mean = sum / n;
    return { mean, std: Math.sqrt(Math.max(0, sum2 / n - mean * mean)) };
  }, b64);
}

(async () => {
  const outDir = path.resolve(process.argv[2] || 'captures/latest');
  const shots = (arg('shots', '1,2,3,4,5,6,7,8')).split(',').map(Number);
  const aspects = (arg('aspects', 'inner,cover')).split(',');
  const seed = arg('seed', '2026');
  const scale = parseFloat(arg('scale', '0.5'));
  const frames = arg('frames', '90');
  const root = path.resolve(arg('root', path.resolve(__dirname, '../../app/build/web')));
  const server = await serve(root, 8700 + Math.floor(Math.random() * 200));
  const port = server.address().port;
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const report = [];
  let failures = 0;
  for (const aspect of aspects) {
    const a = ASPECTS[aspect];
    fs.mkdirSync(path.join(outDir, aspect), { recursive: true });
    for (const shot of shots) {
      const viewport = { width: Math.round(a.width * scale), height: Math.round(a.height * scale) };
      const page = await browser.newPage({ viewport, deviceScaleFactor: 1 });
      await page.addInitScript(SAMPLER_GUARD);
      const logs = [];
      page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
      page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
      const url = `http://127.0.0.1:${port}/?capture=${shot}&seed=${seed}&frames=${frames}${a.hinge ? '&hinge=1' : ''}${arg('extra', '')}`;
      const t0 = Date.now();
      let info = '';
      try {
        await page.goto(url);
        await page.waitForFunction(() => document.title.startsWith('LANTERN_READY'), null, { timeout: 600000, polling: 1000 });
        info = (await page.title()).replace('LANTERN_READY ', '');
      } catch (e) {
        logs.push(`[harness] timeout waiting for ready: ${e.message}`);
      }
      const file = path.join(outDir, aspect, `shot${shot}.png`);
      const buf = await page.screenshot({ path: file });
      const st = await lumaStats(page, buf).catch(() => null);
      const maxSamplers = await page.evaluate(() => window.__maxSamplers).catch(() => -1);
      const overLimit = logs.some((l) => l.includes('SAMPLER_LIMIT'));
      const blank = !st || st.std < 2.0 || overLimit;
      if (blank) failures++;
      const line = `${aspect} shot${shot} ${(Date.now() - t0) / 1000}s ${info} luma=${st ? st.mean.toFixed(1) : '?'}±${st ? st.std.toFixed(1) : '?'} samplers<=${maxSamplers}${overLimit ? '  SAMPLER_LIMIT -> will not run on Android' : ''}${blank && !overLimit ? '  BLANK/FLAT -> harness failure' : ''}`;
      console.log(line);
      report.push(line);
      fs.writeFileSync(path.join(outDir, aspect, `shot${shot}.log`), logs.join('\n'));
      await page.close();
    }
  }
  fs.writeFileSync(path.join(outDir, 'report.txt'), report.join('\n') + '\n');
  await browser.close();
  server.close();
  if (failures) {
    console.error(`${failures} blank/flat capture(s): fix the harness, not the scene.`);
    process.exit(2);
  }
})();
