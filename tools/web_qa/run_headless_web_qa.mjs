#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const [browserPath, url, screenshotPath, reportPath, profilePath, portText = '9227'] = process.argv.slice(2);
if (!browserPath || !url || !screenshotPath || !reportPath || !profilePath) {
  throw new Error('usage: run_headless_web_qa.mjs <browser> <url> <screenshot> <report> <profile> [port]');
}
const port = Number(portText);
const pagePrefix = new URL(url).origin;
await mkdir(path.dirname(screenshotPath), { recursive: true });
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

async function waitForTargets(timeoutMs = 30000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
      const page = targets.find(item => item.type === 'page' && item.url.startsWith(pagePrefix));
      if (page?.webSocketDebuggerUrl) return page;
    } catch {}
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  throw new Error('Chrome DevTools endpoint did not expose the game page');
}

let target;
try {
  target = await waitForTargets();
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
    networkErrors.push({ url: message.params.requestId, errorText: message.params.errorText });
  } else if (message.method === 'Network.responseReceived' && message.params.response.status >= 400) {
    networkErrors.push({ url: message.params.response.url, status: message.params.response.status });
  }
});

function send(method, params = {}) {
  const id = nextId++;
  socket.send(JSON.stringify({ id, method, params }));
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}

await send('Runtime.enable');
await send('Page.enable');
await send('Network.enable');
await send('Log.enable');

const states = [];
let ready = false;
const deadline = Date.now() + 180000;
while (Date.now() < deadline) {
  const evaluated = await send('Runtime.evaluate', {
    expression: `(() => {
      const canvas = document.querySelector('#canvas');
      const status = document.querySelector('#status');
      const notice = document.querySelector('#status-notice');
      return {
        readyState: document.readyState,
        statusPresent: !!status,
        statusVisibility: status ? getComputedStyle(status).visibility : 'removed',
        notice: notice ? notice.innerText.trim() : '',
        canvasWidth: canvas ? canvas.width : 0,
        canvasHeight: canvas ? canvas.height : 0,
        canvasCssWidth: canvas ? canvas.getBoundingClientRect().width : 0,
        canvasCssHeight: canvas ? canvas.getBoundingClientRect().height : 0,
      };
    })()`,
    returnByValue: true,
  });
  const state = evaluated.result.value;
  states.push({ elapsedMs: 180000 - (deadline - Date.now()), ...state });
  if (!state.statusPresent && state.canvasWidth > 0 && state.canvasHeight > 0) {
    ready = true;
    await new Promise(resolve => setTimeout(resolve, 2000));
    break;
  }
  if (state.notice) break;
  await new Promise(resolve => setTimeout(resolve, 1000));
}

const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
await writeFile(screenshotPath, Buffer.from(shot.data, 'base64'));
const report = {
  kind: 'GODOT_WEB_HEADLESS_BROWSER_QA',
  browserPath,
  url,
  ready,
  lastState: states.at(-1) ?? null,
  polls: states.length,
  consoleErrors,
  exceptions,
  networkErrors,
  screenshotPath,
  browserStderrTail: browserStderr.slice(-8000),
};
await writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
try { await send('Browser.close'); } catch {}
socket.close();
setTimeout(() => { if (!browser.killed) browser.kill(); }, 2000).unref();

console.log(JSON.stringify(report));
if (!ready || consoleErrors.length || exceptions.length || networkErrors.length) process.exitCode = 1;
