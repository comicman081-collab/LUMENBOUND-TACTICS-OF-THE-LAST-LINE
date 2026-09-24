import {readFile,readdir,writeFile} from 'node:fs/promises';
const game=JSON.parse(await readFile('godot/data/compiled/game_data.json','utf8'));
const locales=JSON.parse(await readFile('godot/data/compiled/localization.json','utf8'));
const problems=[],events=[],rows=[];
const characters=new Set(game.characters.map(c=>c.id)),enemies=new Set(game.enemies.map(c=>c.id));
const mapFiles=(await readdir('godot/data/compiled/chapter_maps')).filter(f=>/^CH\d+_MAP\.json$/.test(f));
for(const filename of mapFiles){
  const map=JSON.parse(await readFile(`godot/data/compiled/chapter_maps/${filename}`,'utf8'));
  for(const event of map.event_encounters??[]){
    events.push({map:filename,node:event.node_id,kind:event.event_kind,pages:event.pre_battle_dialogue?.length??0});
    if(event.event_kind==='COMPANION'&&!characters.has(event.character_id))problems.push({map:filename,node:event.node_id,error:'unknown companion'});
    if(event.event_kind==='SPECIAL_ENEMY'&&!enemies.has(event.enemy_id))problems.push({map:filename,node:event.node_id,error:'unknown special enemy'});
    const keys=[event.title_key,event.body_key,event.contact_outcome_key,...(event.pre_battle_dialogue??[]).map(p=>p.text_key)].filter(Boolean);
    for(const key of keys)for(const language of ['ko','en']){
      const text=locales[language]?.[key];
      if(typeof text!=='string'||!text.trim())problems.push({map:filename,node:event.node_id,key,language,error:'missing copy'});
      else rows.push({map:filename,node:event.node_id,key,language,length:[...text].length,text});
    }
  }
}
const output={status:problems.length?'FAIL':'STATIC_DATA_PASS_NOT_VISUAL_QA',map_count:mapFiles.length,event_count:events.length,localized_text_references:rows.length,events,problems,longest_copy:rows.sort((a,b)=>b.length-a.length).slice(0,12),scope:'All authored map contact localization and actor references. The shared responsive briefing handles this data; this is not proof of playing every chapter or fitting every scenario textbox.'};
await writeFile('reports/gameplay_qa/20260907_BRIEFING_CONTENT_INVENTORY.json',JSON.stringify(output,null,2));
console.log(JSON.stringify({status:output.status,maps:output.map_count,events:events.length,text_references:rows.length,problems}));
if(problems.length)process.exitCode=1;
