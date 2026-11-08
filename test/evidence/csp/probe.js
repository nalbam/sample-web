// CSP probe for src/index.html. Not part of the image or of CI.
//
// Usage (from the repository root, Playwright installed outside the repository):
//   NODE_PATH=/path/to/node_modules node test/evidence/csp/probe.js
//
// Serves src/ on 127.0.0.1 with the security headers read from
// nginx/templates/default.conf.template (not a copy of the policy), opens / in
// headless Chromium and checks that the page has no CSP violations and that
// Bootstrap, the Font Awesome font, the logo, jQuery and /favicon.ico load.
// Writes console.log, result.json and screenshot.png next to this file.
// Exits non-zero when a check fails.

'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '../../..');
const out = __dirname;
const template = fs.readFileSync(path.join(root, 'nginx/templates/default.conf.template'), 'utf8');

// Every `add_header NAME "VALUE" always;` directive in the template.
const headers = {};
for (const m of template.matchAll(/^\s*add_header\s+(\S+)\s+"([^"]*)"\s+always;\s*$/gm)) {
  headers[m[1]] = m[2];
}
for (const name of ['X-Content-Type-Options', 'Referrer-Policy', 'X-Frame-Options', 'Content-Security-Policy']) {
  if (!headers[name]) {
    console.error(`FAIL: ${name} is not in the template`);
    process.exit(1);
  }
}

const files = {
  '/': ['index.html', 'text/html'],
  '/index.html': ['index.html', 'text/html'],
  '/favicon.ico': ['favicon.ico', 'image/x-icon'],
};

const server = http.createServer((req, res) => {
  const file = files[req.url.split('?')[0]];
  for (const [name, value] of Object.entries(headers)) res.setHeader(name, value);
  if (!file) {
    res.writeHead(404, { 'Content-Type': 'text/html' });
    res.end('<h1>404 Not Found</h1>');
    return;
  }
  res.writeHead(200, { 'Content-Type': file[1] });
  res.end(fs.readFileSync(path.join(root, 'src', file[0])));
});

async function main() {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const log = [];
  const responses = [];
  const failedRequests = [];

  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1024, height: 600 } });
  await page.addInitScript(() => {
    window.__cspViolations = [];
    document.addEventListener('securitypolicyviolation', (e) => {
      window.__cspViolations.push({ directive: e.effectiveDirective, blocked: e.blockedURI, source: e.sourceFile });
    });
  });
  page.on('console', (msg) => log.push(`[console.${msg.type()}] ${msg.text()}`));
  page.on('pageerror', (err) => log.push(`[pageerror] ${err.message}`));
  page.on('response', (r) => responses.push({ url: r.url(), status: r.status() }));
  page.on('requestfailed', (r) => failedRequests.push({ url: r.url(), error: r.failure() && r.failure().errorText }));

  const main = await page.goto(`${base}/`, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);

  const state = await page.evaluate(async () => {
    const before = getComputedStyle(document.querySelector('.fa-thumbs-up'), '::before');
    const logo = document.querySelector('h1 img');
    const favicon = await fetch('/favicon.ico');
    const faFonts = [...document.fonts].filter((f) => /Font Awesome/.test(f.family)).map((f) => ({ family: f.family, weight: f.weight, status: f.status }));
    return {
      violations: window.__cspViolations,
      bootstrapPrimaryBackground: getComputedStyle(document.querySelector('.btn-primary')).backgroundColor,
      thumbsUpBeforeFontFamily: before.fontFamily,
      thumbsUpBeforeContent: before.content,
      fontAwesomeFonts: faFonts,
      logoNaturalWidth: logo.naturalWidth,
      jQuery: window.jQuery ? window.jQuery.fn.jquery : null,
      faviconStatus: favicon.status,
    };
  });
  await page.screenshot({ path: path.join(out, 'screenshot.png'), fullPage: true });
  await browser.close();
  server.close();

  const cspConsole = log.filter((l) => /Content Security Policy/i.test(l));
  // Chromium can block the counter.js 404 page (HTML) before a response event (ORB).
  const counter = responses.find((r) => r.url.endsWith('/static/sample/counter.js')) ||
    failedRequests.find((r) => r.url.endsWith('/static/sample/counter.js'));
  const woff2 = responses.filter((r) => r.url.includes('use.fontawesome.com') && r.url.endsWith('.woff2'));
  const checks = {
    'page HTTP 200 with the template CSP': main.status() === 200 && main.headers()['content-security-policy'] === headers['Content-Security-Policy'],
    'no securitypolicyviolation events': state.violations.length === 0,
    'no CSP console messages': cspConsole.length === 0,
    'Bootstrap .btn-primary background is rgb(13, 110, 253)': state.bootstrapPrimaryBackground === 'rgb(13, 110, 253)',
    'Font Awesome font on .fa-thumbs-up::before': /Font Awesome/.test(state.thumbsUpBeforeFontFamily) && state.fontAwesomeFonts.some((f) => f.status === 'loaded'),
    'Font Awesome woff2 HTTP 200': woff2.length > 0 && woff2.every((r) => r.status === 200),
    'logo loaded (naturalWidth > 0)': state.logoNaturalWidth > 0,
    'jQuery loaded': Boolean(state.jQuery),
    '/favicon.ico HTTP 200': state.faviconStatus === 200,
  };

  const result = {
    date: new Date().toISOString(),
    chromium: chromium.name(),
    headers,
    checks,
    state,
    cspConsoleMessages: cspConsole,
    knownExternalConstraint: {
      note: 'counter.js is outside this repository. Its HTTP status is recorded and is not a CSP violation.',
      counterJs: counter || null,
    },
    fontAwesomeWoff2: woff2,
    failedRequests,
    responses,
  };
  fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify(result, null, 2) + '\n');
  fs.writeFileSync(path.join(out, 'console.log'), (log.length ? log.join('\n') : '(no console messages)') + '\n');

  let failed = 0;
  const summary = [`CSP probe ${result.date}`, `Content-Security-Policy: ${headers['Content-Security-Policy']}`];
  for (const [name, passed] of Object.entries(checks)) {
    summary.push(`${passed ? 'ok' : 'FAIL'}: ${name}`);
    if (!passed) failed++;
  }
  summary.push(`known external constraint, not a CSP violation: counter.js ${counter ? (counter.status ? 'HTTP ' + counter.status : counter.error) : 'not requested'}`);
  summary.push(failed ? `${failed} check(s) failed` : 'all checks passed');
  fs.writeFileSync(path.join(out, 'summary.txt'), summary.join('\n') + '\n');
  console.log(summary.join('\n'));
  process.exit(failed ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
