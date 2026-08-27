#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const [browserPath, url, outputDir, reportPath, profilePath, portText = '9241'] = process.argv.slice(2);
if (!browserPath || !url || !outputDir || !reportPath || !profilePath) {
  throw new Error('usage: run_prologue_flow_qa.mjs <browser> <url> <output-dir> <report> <profile> [port]');
}
const port = Number(portText);
const pagePrefix = new URL(url).origin;
await mkdir(outputDir, { recursive: true });
await mkdir(path.dirname(reportPath), { recursive: true });
await mkdir(profilePath, { recursive: true });

const browser = spawn(browserPath, [
  '--headless=new',
  '--hide-scrollbars',
  '--window-size=1920,1080',
  '--force-device-scale-factor=1',
  '--ignore-gpu-blocklist',
  '--enable-webgl',
  '--disable-background-timer-throttling',
  '--disable-renderer-backgrounding',
  '--no-first-run',
  '--no-default-browser-check',
  '--mute-audio',
  `--remote-debugging-port=${port}`,
  `--user-data-dir=${profilePath}`,
  url,
], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });

let browserStderr = '';
browser.stderr.on('data', chunk => { browserStderr += chunk.toString(); });
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function waitForTarget(timeoutMs = 30000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try {
      const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
      const page = targets.find(item => item.type === 'page' && item.url.startsWith(pagePrefix));
      if (page?.webSocketDebuggerUrl) return page;
    } catch {}
    await sleep(250);
  }
  throw new Error('Chrome DevTools endpoint did not expose the game page');
}

let target;
try {
  target = await waitForTarget();
} catch (error) {
  console.error(browserStderr.slice(-12000));
  if (!browser.killed) browser.kill();
  throw error;
}
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener('open', resolve, { once: true });
  socket.addEventListener('error', reject, { once: true });
});

let nextId = 1;
const pending = new Map();
const consoleErrors = [];
const exceptions = [];
const networkErrors = [];
socket.addEventListener('message', event => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(JSON.stringify(message.error)));
    else resolve(message.result);
    return;
  }
  if (message.method === 'Runtime.consoleAPICalled' && message.params.type === 'error') {
    consoleErrors.push(message.params.args.map(arg => arg.value ?? arg.description ?? '').join(' '));
  } else if (message.method === 'Runtime.exceptionThrown') {
    exceptions.push(message.params.exceptionDetails?.text ?? 'Runtime exception');
  } else if (message.method === 'Network.loadingFailed') {
    networkErrors.push({ requestId: message.params.requestId, errorText: message.params.errorText });
  } else if (message.method === 'Network.responseReceived' && message.params.response.status >= 400) {
    networkErrors.push({ url: message.params.response.url, status: message.params.response.status });
  }
});

function send(method, params = {}) {
  const id = nextId++;
  socket.send(JSON.stringify({ id, method, params }));
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}

async function evaluate(expression) {
  const result = await send('Runtime.evaluate', { expression, returnByValue: true });
  return result.result.value;
}

async function screenshot(name) {
  const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  const destination = path.join(outputDir, name);
  await writeFile(destination, Buffer.from(shot.data, 'base64'));
  return destination;
}

async function clickAt(x, y) {
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
}

await send('Runtime.enable');
await send('Page.enable');
await send('Network.enable');
await send('Log.enable');

let ready = false;
const readyDeadline = Date.now() + 180000;
while (Date.now() < readyDeadline) {
  const state = await evaluate(`(() => {
    const canvas = document.querySelector('#canvas');
    const status = document.querySelector('#status');
    if (!canvas) return { ready: false };
    const rect = canvas.getBoundingClientRect();
    return { ready: !status && canvas.width > 0 && canvas.height > 0, left: rect.left, top: rect.top, width: rect.width, height: rect.height };
  })()`);
  if (state?.ready) {
    ready = true;
    break;
  }
  await sleep(1000);
}
if (!ready) throw new Error('Godot canvas did not become ready');
await sleep(1600);
const canvas = await evaluate(`(() => { const r = document.querySelector('#canvas').getBoundingClientRect(); return { left: r.left, top: r.top, width: r.width, height: r.height }; })()`);
const points = {
  start: { x: canvas.left + canvas.width * 0.5, y: canvas.top + canvas.height * 0.68 },
  dialogue: { x: canvas.left + canvas.width * 0.5, y: canvas.top + canvas.height * 0.84 },
};
const screenshots = [];
screenshots.push(await screenshot('01_title.png'));
await clickAt(points.start.x, points.start.y);
await sleep(850);
screenshots.push(await screenshot('02_prologue_typing.png'));
await clickAt(points.dialogue.x, points.dialogue.y);
await sleep(240);
screenshots.push(await screenshot('03_prologue_line_completed.png'));
await sleep(260);
await clickAt(points.dialogue.x, points.dialogue.y);
await sleep(850);
screenshots.push(await screenshot('04_prologue_next_line.png'));

const report = {
  kind: 'LUMENBOUND_PROLOGUE_WEB_FLOW_QA',
  browserPath,
  url,
  ready,
  canvas,
  points,
  screenshots,
  consoleErrors,
  exceptions,
  networkErrors,
  browserStderrTail: browserStderr.slice(-8000),
};
await writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
try { await send('Browser.close'); } catch {}
socket.close();
setTimeout(() => { if (!browser.killed) browser.kill(); }, 2000).unref();
console.log(JSON.stringify(report));
if (consoleErrors.length || exceptions.length || networkErrors.length) process.exitCode = 1;
