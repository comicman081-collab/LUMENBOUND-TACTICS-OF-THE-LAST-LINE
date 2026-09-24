import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const pending = new Map(), scheduled = [], contexts = [];
class Param {
  constructor() { this.value = 1; }
  setValueAtTime(v,t) { this.value=v; scheduled.push(['set',v,t]); }
  linearRampToValueAtTime(v,t) { this.value=v; scheduled.push(['ramp',v,t]); }
  cancelScheduledValues() {}
  setTargetAtTime(v,t) { this.value=v; scheduled.push(['volume',v,t]); }
}
class Context {
  constructor() { this.state='running'; this.currentTime=1; this.destination={}; contexts.push(this); }
  resume() { this.state='running'; return Promise.resolve(); }
  createGain() { return {gain:new Param(),connect(){},disconnect(){}}; }
  createBufferSource() { return {playbackRate:{value:1},connect(){},disconnect(){},start(t){scheduled.push(['start',t]);},stop(t){scheduled.push(['stop',t]);}}; }
  decodeAudioData() { return Promise.resolve({duration:60}); }
}
const window = {addEventListener(){}};
const sandbox = {window, AudioContext:Context, URL, location:{href:'http://127.0.0.1/play/test/index.html'},
  fetch(url) { return new Promise(resolve=>pending.set(url,resolve)); }, setTimeout, clearTimeout};
vm.runInNewContext(readFileSync(new URL('../../godot/web/browser_bgm.js',import.meta.url),'utf8'),sandbox);
const audio=window.__lumenBGM;
const sfx=window.__lumenSFX;
const settle=async()=>{for(let i=0;i<12;i++) await Promise.resolve();};
const fulfill=async(file)=>{pending.get('http://127.0.0.1/play/test/'+file)({ok:true,arrayBuffer:async()=>new ArrayBuffer(16)}); await settle();};
let checks=0;
function check(value,label) { assert.ok(value,label); checks++; }
audio.unlock();
audio.play('MAP','_audio/bgm/map.wav');
await fulfill('_audio/bgm/map.wav');
contexts[0].currentTime=2;
check(audio.status().active,'actual scheduled source becomes active');
check(!audio.play('MAP','_audio/bgm/map.wav'),'same-track unlock/request never restarts');
check(audio.status().starts.MAP===1,'one source for repeated map requests');
audio.play('BATTLE','_audio/bgm/battle.wav');
check(audio.status().current==='MAP','old track keeps playing while replacement downloads');
await fulfill('_audio/bgm/battle.wav');
contexts[0].currentTime=3;
check(audio.status().current==='BATTLE','ready replacement becomes current');
check(scheduled.some(r=>r[0]==='stop' && r[1]>2.2),'outgoing stop is scheduled after crossfade');
audio.play('STORY','_audio/bgm/story.wav');
audio.stop();
await fulfill('_audio/bgm/story.wav');
check(audio.status().current==='' && !audio.status().starts.STORY,'late decode cannot revive music after stop');
audio.volume(0);
check(scheduled.at(-1)[0]==='volume' && scheduled.at(-1)[1]===0,'mute applies an actual zero gain');
sfx.play('PLAYER_HIT','_audio/sfx/misc/player_hit.wav',0.8,1.1);
await fulfill('_audio/sfx/misc/player_hit.wav');
check(sfx.status().starts.PLAYER_HIT===1,'combat SFX starts on the browser-owned audio context');
check(sfx.status().attempts.PLAYER_HIT===1,'combat SFX attempt is recorded independently of BGM');
sfx.volume(0.4);
check(scheduled.at(-1)[0]==='volume' && scheduled.at(-1)[1]===0.4,'SFX volume targets its own browser gain bus');
console.log('BROWSER_BGM_STATE_TESTS total='+checks+' pass='+checks+' fail=0');
