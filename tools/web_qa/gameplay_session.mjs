// Local-only, interactive gameplay QA. Uses a fresh browser profile and does
// not alter the game, its saves on other origins, or the deployed artifact.
import {spawn} from 'node:child_process';
import {mkdir, writeFile, readFile, rm} from 'node:fs/promises';
import path from 'node:path';
import {createInterface} from 'node:readline';
import {fileURLToPath} from 'node:url';

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
export class GameplaySession {
  constructor(output) {
    this.output = path.resolve(output);
    this.events = [];
    this.actions = [];
    this.pending = new Map();
    this.nextId = 1;
  }
  async start({browserPath, url, port = 9248, width = 390, height = 844, profileGPU = false, profileAudio = false, allowFileAccess = false}) {
    this.url = url;
    this.viewport = {width, height};
    await mkdir(this.output, {recursive: true});
    const browserArgs = [
      '--headless=new', '--enable-webgl', '--ignore-gpu-blocklist',
      '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
      '--no-first-run', '--no-default-browser-check', '--mute-audio',
      '--force-device-scale-factor=1', `--window-size=${width},${height}`,
      `--remote-debugging-port=${port}`, `--user-data-dir=${path.join(this.output, 'profile')}`,
    ];
    if (allowFileAccess) browserArgs.push('--allow-file-access-from-files');
    browserArgs.push('about:blank');
    this.browser = spawn(browserPath, browserArgs, {windowsHide: true, stdio: ['ignore', 'ignore', 'pipe']});
    this.stderr = '';
    this.browser.stderr.on('data', chunk => {this.stderr = (this.stderr + chunk).slice(-24000);});
    let target;
    for (let n = 0; n < 100; n++) {
      try {
        const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
        target = targets.find(item => item.type === 'page');
        if (target) break;
      } catch {}
      await delay(200);
    }
    if (!target) throw new Error(`Local QA browser did not start: ${this.stderr}`);
    this.socket = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => {
      this.socket.addEventListener('open', resolve, {once: true});
      this.socket.addEventListener('error', reject, {once: true});
    });
    this.socket.addEventListener('message', event => {
      const message = JSON.parse(event.data);
      if (message.id) {
        const pending = this.pending.get(message.id);
        if (!pending) return;
        clearTimeout(pending.timer);
        this.pending.delete(message.id);
        if (message.error) pending.reject(new Error(JSON.stringify(message.error)));
        else pending.resolve(message.result);
      } else if (['Runtime.consoleAPICalled', 'Runtime.exceptionThrown', 'Network.loadingFailed', 'Network.responseReceived', 'Log.entryAdded'].includes(message.method)) {
        if (message.method === 'Network.responseReceived' && message.params.response.status < 400) return;
        this.events.push({at: Date.now(), ...message});
      }
    });
    for (const domain of ['Runtime', 'Page', 'Network', 'Log']) await this.send(`${domain}.enable`);
    await this.send('Emulation.setDeviceMetricsOverride', {width, height, deviceScaleFactor: 1, mobile: height > width});
    await this.send('Emulation.setTouchEmulationEnabled', {enabled: height > width, maxTouchPoints: 5});
    await this.send('Emulation.setFocusEmulationEnabled', {enabled: true});
    await this.send('Page.addScriptToEvaluateOnNewDocument', {source: `(() => {
      const q = window.__gameplayQA = {phase: 'boot', windows: [], marks: [], current: [], last: 0, start: 0, longTasks: []};
      const flush = now => {
        if (!q.current.length) return;
        const a = q.current.slice().sort((a,b) => a-b);
        q.windows.push({phase:q.phase, at:now, count:a.length, max:a.at(-1),
          p50:a[Math.floor(a.length*.5)], p95:a[Math.floor(a.length*.95)], p99:a[Math.floor(a.length*.99)],
          over50:a.filter(v=>v>50).length, over100:a.filter(v=>v>100).length,
          over250:a.filter(v=>v>250).length, over1000:a.filter(v=>v>1000).length,
          fps:1000*a.length/a.reduce((x,y)=>x+y,0)});
        q.current=[]; q.start=now;
      };
      q.mark = name => {flush(performance.now()); q.phase=name; q.marks.push({name, at:performance.now()});};
      q.flush = () => flush(performance.now());
      document.addEventListener('visibilitychange', () => {flush(performance.now()); q.last=0;});
      try {new PerformanceObserver(list=>{for(const e of list.getEntries()) q.longTasks.push({phase:q.phase,at:e.startTime,duration:e.duration});}).observe({entryTypes:['longtask']});} catch {}
      function frame(now) {
        if(q.last && document.visibilityState==='visible') q.current.push(now-q.last);
        q.last=now; if(now-q.start>=5000) flush(now); requestAnimationFrame(frame);
      }
      requestAnimationFrame(frame);
    })();`});
    if (profileGPU) await this.send('Page.addScriptToEvaluateOnNewDocument', {source: `(() => {
      const profile = window.__localGPUProfile = {calls: [], contexts: [], programs: []};
      const sources = new WeakMap(), attachments = new WeakMap(), recorded = new WeakSet();
      for (const klass of [window.WebGLRenderingContext, window.WebGL2RenderingContext]) {
        if (!klass) continue;
        const sourceOriginal = klass.prototype.shaderSource;
        klass.prototype.shaderSource = function(shader,source) {sources.set(shader,source);return sourceOriginal.call(this,shader,source);};
        const attachOriginal = klass.prototype.attachShader;
        klass.prototype.attachShader = function(program,shader) {if(!attachments.has(program))attachments.set(program,[]);attachments.get(program).push(shader);return attachOriginal.call(this,program,shader);};
        for (const name of ['compileShader','linkProgram','getShaderParameter','getProgramParameter','getUniformLocation','finish','texImage2D','texStorage2D']) {
          const original = klass.prototype[name];
          if (!original) continue;
          klass.prototype[name] = function(...args) {
            const started = performance.now();
            try {return original.apply(this, args);} finally {
              const duration = performance.now() - started;
              if (duration > 5) profile.calls.push({name, at:started, duration});
              if(name==='getProgramParameter' && duration>100 && !recorded.has(args[0])) {recorded.add(args[0]);profile.programs.push({at:started,duration,sources:(attachments.get(args[0])||[]).map(shader=>sources.get(shader))});}
            }
          };
        }
      }
      const original = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function(...args) {
        const context = original.apply(this,args);
        if(context && String(args[0]).includes('webgl')) {
          const ext=context.getExtension('WEBGL_debug_renderer_info');
          profile.contexts.push({type:args[0],renderer:ext?context.getParameter(ext.UNMASKED_RENDERER_WEBGL):context.getParameter(context.RENDERER),extensions:context.getSupportedExtensions()});
        }
        return context;
      };
    })();`});
    if (profileAudio) await this.send('Page.addScriptToEvaluateOnNewDocument', {
      source: await readFile(new URL('./audio_graph_probe.js', import.meta.url), 'utf8'),
    });
    await this.send('Page.navigate', {url});
    return {pid: this.browser.pid, url, viewport: this.viewport};
  }
  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {this.pending.delete(id); reject(new Error(`CDP timeout: ${method}`));}, 45000);
      this.pending.set(id, {resolve, reject, timer});
      this.socket.send(JSON.stringify({id, method, params}));
    });
  }
  async evaluate(expression) {
    const scoped = `(() => { const frame=document.getElementById('landscape-game'); return (frame ? frame.contentWindow : window).eval(${JSON.stringify(expression)}); })()`;
    const response = await this.send('Runtime.evaluate', {expression: scoped, returnByValue: true, awaitPromise: true});
    if (response.exceptionDetails) throw new Error(JSON.stringify(response.exceptionDetails));
    return response.result.value;
  }
  async mark(name) {
    this.actions.push({at: Date.now(), type: 'mark', name});
    return this.evaluate(`window.__gameplayQA.mark(${JSON.stringify(name)})`);
  }
  async inputPoint(x,y) {
    const response=await this.send('Runtime.evaluate',{expression:`(() => {
      const f=document.getElementById('landscape-game'); if(!f)return {x:${x},y:${y}};
      const r=f.getBoundingClientRect(); return f.dataset.rotated==='1'
        ? {x:r.left+f.clientHeight-${y},y:r.top+${x}} : {x:r.left+${x},y:r.top+${y}};
    })()`,returnByValue:true});
    return response.result.value;
  }
  async click(x, y) {
    ({x,y}=await this.inputPoint(x,y));
    this.actions.push({at: Date.now(), type: 'click', x, y});
    await this.send('Input.dispatchMouseEvent', {type: 'mouseMoved', x, y});
    await this.send('Input.dispatchMouseEvent', {type: 'mousePressed', x, y, button: 'left', clickCount: 1});
    await this.send('Input.dispatchMouseEvent', {type: 'mouseReleased', x, y, button: 'left', clickCount: 1});
  }
  async key(key, code, virtualKeyCode) {
    this.actions.push({at: Date.now(), type: 'key', key});
    const params = {key, code, windowsVirtualKeyCode: virtualKeyCode};
    await this.send('Input.dispatchKeyEvent', {type: 'keyDown', ...params});
    await this.send('Input.dispatchKeyEvent', {type: 'keyUp', ...params});
  }
  async tap(x, y) {
    ({x,y}=await this.inputPoint(x,y));
    this.actions.push({at: Date.now(), type: 'touch', x, y});
    await this.send('Emulation.setTouchEmulationEnabled', {enabled: true, maxTouchPoints: 1});
    await this.send('Input.dispatchTouchEvent', {type: 'touchStart', touchPoints: [{x,y,radiusX:1,radiusY:1,force:1,id:0}]});
    await this.send('Input.dispatchTouchEvent', {type: 'touchEnd', touchPoints: []});
  }
  async game(command = 'snapshot', params = {}) {
    const id = Date.now();
    const request = JSON.stringify({id,command,...params});
    const result = await this.evaluate(`new Promise((resolve,reject)=>{
      const q=window.__localGameplayQA;
      if(!q?.ready){reject(new Error('Local sandbox developer probe unavailable'));return;}
      q.request=${JSON.stringify(request)};
      const started=performance.now();
      const poll=setInterval(()=>{
        if(q.response?.id===${id}){clearInterval(poll);resolve(q.response.result);}
        else if(performance.now()-started>15000){clearInterval(poll);reject(new Error('Game snapshot timeout'));}
      },50);
    })`);
    this.actions.push({at: id, type: 'game', command, params, result});
    await writeFile(path.join(this.output, `state_${id}.json`), JSON.stringify(result,null,2)+'\n');
    return result;
  }
  async swipe(x, y, endY, duration = 500) {
    this.actions.push({at:Date.now(), type:'swipe', x,y,endY,duration});
    const start=await this.inputPoint(x,y),end=await this.inputPoint(x,endY);
    await this.send('Input.dispatchTouchEvent', {type:'touchStart', touchPoints:[{...start,id:0}]});
    const steps = 20;
    for(let i=1;i<=steps;i++) {
      await new Promise(resolve=>setTimeout(resolve,duration/steps));
      await this.send('Input.dispatchTouchEvent', {type:'touchMove', touchPoints:[{x:start.x+(end.x-start.x)*i/steps,y:start.y+(end.y-start.y)*i/steps,id:0}]});
    }
    await this.send('Input.dispatchTouchEvent', {type:'touchEnd', touchPoints:[]});
  }
  async checkpoint(name) {
    const state=await this.game();
    const file=await this.screenshot(name);
    const buttons=state.buttons?.filter(b=>b.rect[0]>=-1 && b.rect[1]>=0 && b.rect[1]+b.rect[3]<=this.viewport.height+1);
    const battle=state.battle ? {time:state.battle.time,wave:state.battle.wave,ended:state.battle.ended,ready:state.battle.ready,paused:state.battle.paused,
      signature:state.battle.signature,actors:state.battle.actors} : undefined;
    return {file,screen:state.screen,stage:state.stage,buttons,scrolls:state.scrolls,map:state.map,battle,sandbox:state.sandbox};
  }
  async resize(width, height) {
    this.viewport = {width, height};
    await this.send('Emulation.setDeviceMetricsOverride', {width, height, deviceScaleFactor: 1, mobile: height > width});
  }
  async screenshot(name) {
    const shot = await this.send('Page.captureScreenshot', {format: 'png', captureBeyondViewport: false});
    const filename = path.join(this.output, `${name}.png`);
    await writeFile(filename, Buffer.from(shot.data, 'base64'));
    this.actions.push({at: Date.now(), type: 'screenshot', filename});
    return filename;
  }
  logs(tail = 20) {
    return this.events.filter(e=>e.method==='Runtime.consoleAPICalled').slice(-tail).map(e=>({type:e.params.type, text:e.params.args.map(x=>x.value??x.description??'').join(' ')}));
  }
  async report() {
    const telemetry = await this.evaluate(`(() => {const q=window.__gameplayQA; q.flush();return {windows:q.windows,marks:q.marks,longTasks:q.longTasks}})()`);
    const report = {url:this.url, viewport:this.viewport, actions:this.actions, telemetry, events:this.events, stderr:this.stderr};
    const filename = path.join(this.output, 'gameplay_report.json');
    await writeFile(filename, JSON.stringify(report, null, 2)+'\n');
    return {filename, windows:telemetry.windows.slice(-6), errors:this.events.filter(e=>e.method==='Runtime.exceptionThrown'||e.method==='Network.loadingFailed'||e.method==='Network.responseReceived').length};
  }
  async close() {
    // Keep browser report serialization/teardown distinct from gameplay.
    try {
      await this.mark('qa_report_collection').catch(()=>{});
      await this.report();
    } catch(error) {
      await writeFile(path.join(this.output,'report_collection_error.txt'),String(error)).catch(()=>{});
    }
    if (this.socket?.readyState===WebSocket.OPEN) await this.send('Browser.close').catch(()=>{});
    this.socket?.close();
    // Screenshots, commands, console output and assertions are the evidence.
    // A disposable Chromium cache is not: retaining one for every audit grew
    // this project by 26 GiB. Only delete this session's exact owned profile.
    if (this.browser && this.browser.exitCode === null) {
      await Promise.race([new Promise(resolve=>this.browser.once('exit',resolve)),delay(5000)]);
      if (this.browser.exitCode === null) this.browser.kill();
    }
    const profile=path.resolve(this.output,'profile');
    if (path.dirname(profile)!==this.output) throw Error('QA profile escaped output directory');
    await rm(profile,{recursive:true,force:true,maxRetries:8,retryDelay:300})
      .catch(error=>writeFile(path.join(this.output,'profile_cleanup_error.txt'),String(error)));
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [output, url, width = '390', height = '844', port = '9248'] = process.argv.slice(2);
  const session = new GameplaySession(output);
  console.log(JSON.stringify(await session.start({
    browserPath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    url, width: Number(width), height: Number(height), port: Number(port),
  })));
  const lines = createInterface({input: process.stdin, terminal: false});
  for await (const line of lines) {
    try {
      const {method, args = []} = JSON.parse(line);
      if (!['mark','click','tap','swipe','checkpoint','key','game','resize','screenshot','logs','report','close','evaluate','send'].includes(method)) throw new Error('Unknown QA command');
      console.log(JSON.stringify({method, result: await session[method](...args)}));
      if (method === 'close') {lines.close(); break;}
    } catch (error) {console.log(JSON.stringify({error: String(error)}));}
  }
}
