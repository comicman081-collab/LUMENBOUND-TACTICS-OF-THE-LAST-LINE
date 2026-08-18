#!/usr/bin/env node
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const [portText, pagePrefix, screenshotPath, reportPath] = process.argv.slice(2);
const port = Number(portText);
if (!port || !pagePrefix || !screenshotPath || !reportPath) throw new Error('missing arguments');

const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const target = targets.find(item => item.type === 'page' && item.url.startsWith(pagePrefix));
if (!target) throw new Error(`game page target missing on CDP port ${port}`);

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
    const entry = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) entry.reject(new Error(JSON.stringify(message.error)));
    else entry.resolve(message.result);
  } else if (message.method === 'Runtime.consoleAPICalled' && message.params.type === 'error') {
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
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    socket.send(JSON.stringify({ id, method, params }));
  });
}

await Promise.all([send('Runtime.enable'), send('Page.enable'), send('Network.enable'), send('Log.enable')]);
let state = null;
const start = Date.now();
const deadline = start + 180000;
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
        canvasCssHeight: canvas ? canvas.getBoundingClientRect().height : 0
      };
    })()`,
    returnByValue: true,
  });
  state = evaluated.result.value;
  if (!state.statusPresent && state.canvasWidth > 0 && state.canvasHeight > 0) {
    await new Promise(resolve => setTimeout(resolve, 2000));
    break;
  }
  if (state.notice) break;
  await new Promise(resolve => setTimeout(resolve, 1000));
}

const ready = !!state && !state.statusPresent && state.canvasWidth > 0 && state.canvasHeight > 0;
const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
await mkdir(path.dirname(screenshotPath), { recursive: true });
await mkdir(path.dirname(reportPath), { recursive: true });
await writeFile(screenshotPath, Buffer.from(shot.data, 'base64'));
const report = {
  kind: 'GODOT_WEB_RUNNING_BROWSER_QA', port, pagePrefix, ready,
  elapsedMs: Date.now() - start, state, consoleErrors, exceptions, networkErrors, screenshotPath,
};
await writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
socket.close();
console.log(JSON.stringify(report));
if (!ready || consoleErrors.length || exceptions.length || networkErrors.length) process.exitCode = 1;
