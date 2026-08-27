#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { inflateSync } from 'node:zlib';

const [browserPath, url, outputDir, reportPath, profileRoot, portText = '9243'] = process.argv.slice(2);
if (!browserPath || !url || !outputDir || !reportPath || !profileRoot) {
  throw new Error('usage: run_prologue_controls_qa.mjs <browser> <url> <output-dir> <report> <profile-root> [port-base]');
}

const portBase = Number(portText);
if (!Number.isInteger(portBase) || portBase < 1024 || portBase > 65534) {
  throw new Error(`invalid CDP port base: ${portText}`);
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const runToken = `${Date.now()}-${process.pid}`;
await mkdir(outputDir, { recursive: true });
await mkdir(path.dirname(reportPath), { recursive: true });
await mkdir(profileRoot, { recursive: true });

function sandboxUrl(scenario) {
  const scoped = new URL(url);
  scoped.searchParams.set('r15-save-sandbox', '1');
  scoped.searchParams.set('r15-save-sandbox-session', `prologue-controls-${scenario}-${runToken}`);
  return scoped.toString();
}

function sha256(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

function paethPredictor(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

// Chrome's Page.captureScreenshot emits non-interlaced, 8-bit PNGs. Decode
// just that contract so the QA verdict measures actual changed pixels rather
// than treating any compressed-byte difference as a scene transition.
function decodePng(buffer) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (buffer.length < signature.length || !buffer.subarray(0, 8).equals(signature)) {
    throw new Error('capture is not a PNG');
  }

  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = -1;
  let interlace = -1;
  const idat = [];
  let offset = 8;
  while (offset + 12 <= buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('ascii', offset + 4, offset + 8);
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    if (dataEnd + 4 > buffer.length) throw new Error('truncated PNG chunk');
    if (type === 'IHDR') {
      width = buffer.readUInt32BE(dataStart);
      height = buffer.readUInt32BE(dataStart + 4);
      bitDepth = buffer[dataStart + 8];
      colorType = buffer[dataStart + 9];
      interlace = buffer[dataStart + 12];
    } else if (type === 'IDAT') {
      idat.push(buffer.subarray(dataStart, dataEnd));
    } else if (type === 'IEND') {
      break;
    }
    offset = dataEnd + 4;
  }

  const channelsByColorType = new Map([[0, 1], [2, 3], [4, 2], [6, 4]]);
  const channels = channelsByColorType.get(colorType);
  if (!width || !height || bitDepth !== 8 || interlace !== 0 || !channels || !idat.length) {
    throw new Error(`unsupported PNG contract ${width}x${height} depth=${bitDepth} color=${colorType} interlace=${interlace}`);
  }

  const packed = inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const expected = height * (stride + 1);
  if (packed.length !== expected) throw new Error(`unexpected PNG payload length ${packed.length}, expected ${expected}`);
  const pixels = Buffer.alloc(height * stride);
  let source = 0;
  for (let y = 0; y < height; y++) {
    const filter = packed[source++];
    const rowOffset = y * stride;
    const previousOffset = rowOffset - stride;
    for (let x = 0; x < stride; x++) {
      const raw = packed[source++];
      const left = x >= channels ? pixels[rowOffset + x - channels] : 0;
      const up = y > 0 ? pixels[previousOffset + x] : 0;
      const upLeft = y > 0 && x >= channels ? pixels[previousOffset + x - channels] : 0;
      let predictor = 0;
      if (filter === 1) predictor = left;
      else if (filter === 2) predictor = up;
      else if (filter === 3) predictor = Math.floor((left + up) / 2);
      else if (filter === 4) predictor = paethPredictor(left, up, upLeft);
      else if (filter !== 0) throw new Error(`unsupported PNG filter ${filter}`);
      pixels[rowOffset + x] = (raw + predictor) & 0xff;
    }
  }
  return { width, height, channels, pixels };
}

function comparePng(beforeBuffer, afterBuffer, threshold = 12) {
  const before = decodePng(beforeBuffer);
  const after = decodePng(afterBuffer);
  if (before.width !== after.width || before.height !== after.height || before.channels !== after.channels) {
    return {
      sameGeometry: false,
      changedPixelRatio: 1,
      meanAbsoluteDelta: 255,
      before: { width: before.width, height: before.height, channels: before.channels },
      after: { width: after.width, height: after.height, channels: after.channels },
    };
  }

  const comparedChannels = before.channels === 1 ? 1 : Math.min(3, before.channels);
  const pixelCount = before.width * before.height;
  let changedPixels = 0;
  let absoluteDelta = 0;
  for (let pixel = 0; pixel < pixelCount; pixel++) {
    const start = pixel * before.channels;
    let maxDelta = 0;
    for (let channel = 0; channel < comparedChannels; channel++) {
      const delta = Math.abs(before.pixels[start + channel] - after.pixels[start + channel]);
      absoluteDelta += delta;
      maxDelta = Math.max(maxDelta, delta);
    }
    if (maxDelta >= threshold) changedPixels++;
  }
  return {
    sameGeometry: true,
    changedPixelRatio: changedPixels / pixelCount,
    meanAbsoluteDelta: absoluteDelta / (pixelCount * comparedChannels),
    before: { width: before.width, height: before.height, channels: before.channels },
    after: { width: after.width, height: after.height, channels: after.channels },
  };
}

function clipFromCanvas(canvas, { left, top, width, height }) {
  return {
    x: Math.max(0, canvas.left + canvas.width * left),
    y: Math.max(0, canvas.top + canvas.height * top),
    width: Math.max(1, canvas.width * width),
    height: Math.max(1, canvas.height * height),
    scale: 1,
  };
}

async function runScenario(name, port, action) {
  const scenarioUrl = sandboxUrl(name);
  const scenarioDir = path.join(outputDir, name);
  const profilePath = path.join(profileRoot, `${name}-${runToken}`);
  await mkdir(scenarioDir, { recursive: true });
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
    scenarioUrl,
  ], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });

  let browserStderr = '';
  browser.stderr.on('data', chunk => { browserStderr += chunk.toString(); });
  const consoleErrors = [];
  const exceptions = [];
  const networkErrors = [];
  let socket = null;
  let nextId = 1;
  const pending = new Map();

  function send(method, params = {}) {
    if (!socket) return Promise.reject(new Error('CDP socket is not connected'));
    const id = nextId++;
    socket.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
  }

  async function evaluate(expression) {
    const result = await send('Runtime.evaluate', { expression, returnByValue: true });
    return result.result.value;
  }

  async function capture(namePart, clip = null, persist = true) {
    const params = { format: 'png', captureBeyondViewport: false, fromSurface: true };
    if (clip) params.clip = clip;
    const shot = await send('Page.captureScreenshot', params);
    const data = Buffer.from(shot.data, 'base64');
    let destination = null;
    if (persist) {
      destination = path.join(scenarioDir, namePart);
      await writeFile(destination, data);
    }
    return { data, path: destination, sha256: sha256(data) };
  }

  async function clickAt(x, y) {
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
    await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
    await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
  }

  async function moveMouseAway(canvas) {
    await send('Input.dispatchMouseEvent', {
      type: 'mouseMoved',
      x: canvas.left + canvas.width * 0.5,
      y: canvas.top + canvas.height * 0.48,
    });
  }

  async function waitForTarget(timeoutMs = 30000) {
    const pagePrefix = new URL(scenarioUrl).origin;
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

  async function waitForCanvas(timeoutMs = 180000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const state = await evaluate(`(() => {
        const canvas = document.querySelector('#canvas');
        const status = document.querySelector('#status');
        if (!canvas) return { ready: false };
        const rect = canvas.getBoundingClientRect();
        return {
          ready: !status && canvas.width > 0 && canvas.height > 0,
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
        };
      })()`);
      if (state?.ready) return state;
      await sleep(1000);
    }
    throw new Error('Godot canvas did not become ready');
  }

  let ready = false;
  let canvas = null;
  let evidence = null;
  let error = null;
  try {
    const target = await waitForTarget();
    socket = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, { once: true });
      socket.addEventListener('error', reject, { once: true });
    });
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

    await send('Runtime.enable');
    await send('Page.enable');
    await send('Network.enable');
    await send('Log.enable');
    canvas = await waitForCanvas();
    ready = true;
    await sleep(1600);
    await capture('01_title.png');
    await clickAt(canvas.left + canvas.width * 0.5, canvas.top + canvas.height * 0.68);
    await sleep(850);
    await moveMouseAway(canvas);
    evidence = await action({ canvas, capture, clickAt, moveMouseAway });
  } catch (caught) {
    error = caught instanceof Error ? caught.stack ?? caught.message : String(caught);
  } finally {
    if (socket) {
      try { await send('Browser.close'); } catch {}
      socket.close();
    }
    await sleep(100);
    if (browser.exitCode === null) browser.kill();
  }

  const cleanRuntime = consoleErrors.length === 0 && exceptions.length === 0 && networkErrors.length === 0;
  return {
    name,
    browserPath,
    url: scenarioUrl,
    sandboxSession: new URL(scenarioUrl).searchParams.get('r15-save-sandbox-session'),
    profilePath,
    port,
    ready,
    canvas,
    evidence,
    cleanRuntime,
    pass: ready && !error && cleanRuntime && evidence?.pass === true,
    error,
    consoleErrors,
    exceptions,
    networkErrors,
    browserStderrTail: browserStderr.slice(-8000),
  };
}

const autoScenario = await runScenario('auto', portBase, async ({ canvas, capture, clickAt, moveMouseAway }) => {
  const controlsClip = clipFromCanvas(canvas, { left: 0.795, top: 0.015, width: 0.18, height: 0.14 });
  const beforeFull = await capture('02_prologue_before_auto.png');
  const beforeControl = await capture('02_prologue_before_auto_control.png', controlsClip);
  const autoPoint = {
    x: canvas.left + canvas.width * 0.843,
    y: canvas.top + canvas.height * 0.083,
  };
  await clickAt(autoPoint.x, autoPoint.y);
  await moveMouseAway(canvas);
  // AUTO advances after 0.45s. Capture first so the frame proves AUTO ON
  // without conflating it with a subsequent dialogue-line transition.
  await sleep(160);
  const afterFull = await capture('03_auto_on.png');
  const afterControl = await capture('03_auto_on_control.png', controlsClip);
  const controlDelta = comparePng(beforeControl.data, afterControl.data);
  const pass = controlDelta.sameGeometry
    && controlDelta.changedPixelRatio >= 0.002
    && controlDelta.meanAbsoluteDelta >= 0.15;
  return {
    pass,
    assertion: 'AUTO click visibly changes the prologue control to AUTO ON before automatic advance',
    autoPoint,
    controlsClip,
    controlDelta,
    screenshots: [beforeFull.path, beforeControl.path, afterFull.path, afterControl.path],
    hashes: {
      beforeControl: beforeControl.sha256,
      autoOnControl: afterControl.sha256,
    },
  };
});

const skipScenario = await runScenario('skip', portBase + 1, async ({ canvas, capture, clickAt, moveMouseAway }) => {
  const controlsClip = clipFromCanvas(canvas, { left: 0.795, top: 0.015, width: 0.18, height: 0.14 });
  const dialogueClip = clipFromCanvas(canvas, { left: 0.06, top: 0.62, width: 0.86, height: 0.34 });
  const beforeFull = await capture('02_prologue_before_skip.png');
  const beforeControl = await capture('02_prologue_before_skip_control.png', controlsClip);
  const beforeDialogue = await capture('02_prologue_before_skip_dialogue.png', dialogueClip);
  const skipPoint = {
    x: canvas.left + canvas.width * 0.915,
    y: canvas.top + canvas.height * 0.083,
  };
  const transitionStarted = Date.now();
  await clickAt(skipPoint.x, skipPoint.y);
  await moveMouseAway(canvas);

  let probeDelta = null;
  const transitionDeadline = Date.now() + 8000;
  while (Date.now() < transitionDeadline) {
    await sleep(220);
    const probe = await capture('probe.png', controlsClip, false);
    probeDelta = comparePng(beforeControl.data, probe.data);
    if (probeDelta.changedPixelRatio >= 0.03 && probeDelta.meanAbsoluteDelta >= 1.0) break;
  }
  const transitionMs = Date.now() - transitionStarted;
  await sleep(350);
  const afterFull = await capture('03_home_after_skip.png');
  const afterControl = await capture('03_home_after_skip_control.png', controlsClip);
  const afterDialogue = await capture('03_home_after_skip_dialogue_region.png', dialogueClip);
  const fullDelta = comparePng(beforeFull.data, afterFull.data);
  const controlDelta = comparePng(beforeControl.data, afterControl.data);
  const dialogueDelta = comparePng(beforeDialogue.data, afterDialogue.data);
  const pass = controlDelta.changedPixelRatio >= 0.03
    && dialogueDelta.changedPixelRatio >= 0.08
    && fullDelta.changedPixelRatio >= 0.08;
  return {
    pass,
    assertion: 'SKIP removes prologue controls/dialogue and renders the HOME scene',
    skipPoint,
    controlsClip,
    dialogueClip,
    transitionMs,
    probeDelta,
    controlDelta,
    dialogueDelta,
    fullDelta,
    screenshots: [
      beforeFull.path,
      beforeControl.path,
      beforeDialogue.path,
      afterFull.path,
      afterControl.path,
      afterDialogue.path,
    ],
    hashes: {
      prologue: beforeFull.sha256,
      home: afterFull.sha256,
    },
  };
});

const report = {
  kind: 'LUMENBOUND_PROLOGUE_CONTROLS_WEB_QA',
  browserPath,
  sourceUrl: url,
  runToken,
  freshSessionIsolation: {
    distinctSandboxSessions: autoScenario.sandboxSession !== skipScenario.sandboxSession,
    distinctProfiles: autoScenario.profilePath !== skipScenario.profilePath,
    distinctPorts: autoScenario.port !== skipScenario.port,
  },
  scenarios: {
    auto: autoScenario,
    skip: skipScenario,
  },
};
report.pass = Object.values(report.freshSessionIsolation).every(Boolean)
  && autoScenario.pass
  && skipScenario.pass;

await writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report));
if (!report.pass) process.exitCode = 1;
