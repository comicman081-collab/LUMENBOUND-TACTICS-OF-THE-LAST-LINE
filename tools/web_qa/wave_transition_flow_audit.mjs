import {GameplaySession} from './gameplay_session.mjs';
import {writeFile, mkdir} from 'node:fs/promises';
import path from 'node:path';

const [output,input,port='9533',video='']=process.argv.slice(2);
const url=new URL(input);url.searchParams.set('gameplay-qa','1');url.searchParams.set('qa','wave-transition-reference');
const session=new GameplaySession(output),checks=[],scenes=[];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
let movie=null;
async function startMovie(){
  movie={frames:[],active:true};
  movie.listener=event=>{
    const message=JSON.parse(event.data);
    if(message.method!=='Page.screencastFrame')return;
    session.send('Page.screencastFrameAck',{sessionId:message.params.sessionId}).catch(()=>{});
    if(movie.active&&movie.frames.length<1000)movie.frames.push({timestamp:message.params.metadata.timestamp,data:message.params.data});
  };
  session.socket.addEventListener('message',movie.listener);
  await session.send('Page.startScreencast',{format:'jpeg',quality:80,maxWidth:1920,maxHeight:1080,everyNthFrame:2});
}
async function stopMovie(){
  movie.active=false;await session.send('Page.stopScreencast');
  session.socket.removeEventListener('message',movie.listener);
  const folder=path.join(output,'movie_frames');await mkdir(folder,{recursive:true});
  const lines=['ffconcat version 1.0'];
  for(let i=0;i<movie.frames.length;i++){
    const name='frame_'+String(i).padStart(4,'0')+'.jpg',frame=movie.frames[i];
    await writeFile(path.join(folder,name),Buffer.from(frame.data,'base64'));
    lines.push("file 'movie_frames/"+name+"'");
    const interval=i+1<movie.frames.length?movie.frames[i+1].timestamp-frame.timestamp:1/30;
    lines.push('duration '+Math.max(1/120,interval).toFixed(6));
  }
  await writeFile(path.join(output,'capture_frames.ffconcat'),lines.join('\n')+'\n');
  await writeFile(path.join(output,'capture_metadata.json'),JSON.stringify({visual_only:true,not_fps_evidence:true,
    sound_recorded:false,render_resolution:[1920,1080],frame_count:movie.frames.length,
    seconds:movie.frames.at(-1).timestamp-movie.frames[0].timestamp},null,2));
  delete movie.frames;
}
function check(pass,name){checks.push({pass:!!pass,name});console.log(JSON.stringify(checks.at(-1)));if(!pass)throw Error(name)}
async function clickButton(s,predicate){const b=s.buttons.find(b=>!b.disabled&&predicate(b));if(!b)throw Error('Missing action on '+s.screen);await session.click(b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2)}
async function settleMap(){
  for(let n=0;n<240;n++){
    const s=await session.game();
    const skip=s.buttons.find(b=>!b.disabled&&b.text.startsWith('SKIP'));
    if(s.screen==='STORY'&&skip){await clickButton(s,b=>b===skip);await delay(300);continue}
    if(s.map?.tutorial?.visible){const r=s.map.tutorial.continue;await session.click(r[0]+r[2]/2,r[1]+r[3]/2);await delay(300);continue}
    if(s.map?.ready&&!s.map.moving&&!s.map.turn_transitioning&&!s.transition_loading.active)return s;
    await delay(300);
  }
  throw Error('Map not ready');
}
try{
  await mkdir(output,{recursive:true});
  await session.start({browserPath:'C:/Program Files/Google/Chrome/Application/chrome.exe',url:url.href,
    port:Number(port),width:1920,height:1080});
  let ready=false;
  for(let n=0;n<240;n++){if(await session.evaluate('!!window.__localGameplayQA?.ready')){ready=true;break}await delay(500)}
  check(ready,'local gameplay fixture available');
  for(const stage of ['CH01-N05','CH01-N20']){
    await session.game('prepare_stage_contact',{stage_id:stage,campaign_flow:true});let s=await settleMap();
    check(s.map.player_rules,'ordinary rules on '+stage);
    await clickButton(s,b=>b.text==='다음 조우');
    for(let n=0;n<60;n++){s=await session.game();if(s.buttons.some(b=>!b.disabled&&b.text.includes('칸 이동')))break;await delay(150)}
    await clickButton(s,b=>b.text.includes('칸 이동'));
    for(let n=0;n<240;n++){
      s=await session.game();
      if(s.buttons.some(b=>!b.disabled&&b.text.startsWith('건너뛰기'))){await clickButton(s,b=>b.text.startsWith('건너뛰기'));await delay(250);continue}
      if(s.buttons.some(b=>!b.disabled&&b.name==='EventDialogueNext')){await clickButton(s,b=>b.name==='EventDialogueNext');await delay(250);continue}
      if(s.battle?.ready&&!s.transition_loading.active){
        const deploy=s.buttons.find(b=>!b.disabled&&b.text==='전투 개시');if(deploy)await clickButton(s,b=>b===deploy);
        break;
      }
      await delay(300);
    }
    check(s.battle?.ready&&s.layout.size.join(',')==='1920,1080','real 1080p combat loaded '+stage);
    const seen=new Map(),started=Date.now();let firstClear=false;
    while(Date.now()-started<95000){
      s=await session.game();
      const wave=s.battle?.wave_scene;
      if(video==='video'&&wave?.active&&wave.boss&&!movie)await startMovie();
      if(movie?.active&&!wave?.active)await stopMovie();
      if(wave?.active){
        let record=seen.get(wave.wave);
        if(!record){record={stage,wave:wave.wave,boss:wave.boss,time:s.battle.time,hp:s.battle.actors.map(a=>[a.uid,a.hp]),shots:[],samples:[]};seen.set(wave.wave,record);scenes.push(record)}
        record.samples.push({scene:wave,time:s.battle.time,hp:s.battle.actors.map(a=>[a.uid,a.hp])});
        const shot=wave.mask>.85?'aperture':wave.enemy_caption>.85?'enemy':wave.ally_caption>.85?'squad':wave.banner>.85?'encounter':null;
        if(shot&&!record.shots.includes(shot)){await session.screenshot(stage+'_W'+wave.wave+'_'+shot);record.shots.push(shot)}
      }
      const fieldSkip=s.buttons.find(b=>!b.disabled&&b.name==='FieldSceneSkip');
      if(fieldSkip){await session.screenshot(stage+'_aftermath');await clickButton(s,b=>b===fieldSkip);await delay(400)}
      if(s.restart_progress.first_clear[stage]){firstClear=true;break}
      await delay(110);
    }
    check(firstClear,'natural AUTO victory after authored scenes '+stage);
    check(seen.size===(stage==='CH01-N20'?2:1),'every reinforcement wave owns exactly one scene '+stage);
    for(const record of seen.values()){
      const label=stage+' W'+record.wave;
      check(record.samples.length>=12,label+' real scene sampled across multiple frames');
      check(record.samples.every(v=>v.time===record.time),label+' simulation timer freezes throughout scene');
      check(record.samples.every(v=>JSON.stringify(v.hp)===JSON.stringify(record.hp)),label+' no attacks or damage occur behind camera');
      check(record.samples.some(v=>v.scene.camera_zoom>1.25),label+' actual SD actors enlarged by camera');
      check(['aperture','enemy','squad','encounter'].every(shot=>record.shots.includes(shot)),label+' aperture, enemy cue, squad reply and encounter band actually rendered');
      check(record.samples.some(v=>v.scene.phase==='return'&&v.scene.camera_zoom<1.08),label+' continuous pull-back rejoins battle');
    }
    await session.screenshot(stage+'_cleared');
  }
  check(session.logs(10000).every(e=>e.type!=='error'&&!/SCRIPT ERROR|Parse Error/.test(e.text)),'no engine/browser errors');
}catch(error){checks.push({pass:false,name:String(error)});console.error(error);process.exitCode=1;await session.screenshot('failure').catch(()=>{})}
finally{if(movie?.active)await stopMovie().catch(()=>{});await writeFile(path.join(output,'wave_flow_summary.json'),JSON.stringify({checks,scenes},null,2));await session.close()}
