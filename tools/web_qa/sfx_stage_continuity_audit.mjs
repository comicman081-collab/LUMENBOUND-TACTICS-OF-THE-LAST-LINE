// Local-only regression: a real 1-1 combat followed by a real 1-2 combat
// must both emit attack/hit starts through the browser-owned SFX bus.
import {GameplaySession} from './gameplay_session.mjs';
import {mkdir, writeFile} from 'node:fs/promises';
import path from 'node:path';

const [output, url, port = '9382'] = process.argv.slice(2);
const session = new GameplaySession(output), checks = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const state = () => session.game();
const check = (value, name) => {
  checks.push({name, pass: !!value});
  console.log(JSON.stringify(checks.at(-1)));
  if (!value) throw Error(name);
};
const totalStarts = status => Object.values(status?.starts || {}).reduce((total, value) => total + Number(value || 0), 0);
async function tapVisible(predicate) {
  const snapshot = await state();
  const button = snapshot.buttons.find(button => predicate(button) && !button.disabled && button.rect[1] >= 0 && button.rect[1] + button.rect[3] <= session.viewport.height + 1);
  if (!button) throw Error('Missing visible combat-entry action');
  await session.tap(button.rect[0] + button.rect[2] / 2, button.rect[1] + button.rect[3] / 2);
  await delay(350);
}
async function enterBattle(stageNumber) {
  // Rebuild the actual map neighbour fixture per stage.  This clears the
  // previous contact transaction while retaining the same browser tab and its
  // WebAudio context, which is the scene-transition condition that regressed.
  await session.game('prepare_stage_contact', {stage_id: 'CH01-N' + String(stageNumber).padStart(2, '0')});
  for (let attempt = 0; attempt < 100; attempt++) {
    const snapshot = await state();
    if (snapshot.screen === 'STORY') {
      const skip = snapshot.buttons.find(button => button.name === 'StorySkipButton' && !button.disabled);
      if (skip) await tapVisible(button => button.name === 'StorySkipButton');
      else await delay(250);
      continue;
    }
    if (snapshot.battle?.ready) return snapshot;
    const tutorial = snapshot.buttons.some(button => button.text === '안내 건너뛰기' && !button.disabled);
    if (tutorial) { await tapVisible(button => button.text === '안내 건너뛰기'); continue; }
    const move = snapshot.buttons.some(button => button.text.includes('1칸 이동') && !button.disabled);
    if (move) { await tapVisible(button => button.text.includes('1칸 이동')); continue; }
    const next = snapshot.buttons.some(button => button.text === '다음 조우' && !button.disabled);
    if (next) { await tapVisible(button => button.text === '다음 조우'); continue; }
    const dialogue = snapshot.buttons.some(button => button.name === 'EventDialogueNext' && !button.disabled);
    if (dialogue) { await tapVisible(button => button.name === 'EventDialogueNext'); continue; }
    await delay(300);
  }
  throw Error('Battle did not become ready for CH01-N' + String(stageNumber).padStart(2, '0'));
}

try {
  await mkdir(output, {recursive: true});
  const target = new URL(url);
  target.searchParams.set('gameplay-qa', '1');
  target.searchParams.set('qa', 'sfx-stage-continuity');
  await session.start({browserPath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', url: target.href, port: Number(port), width: 844, height: 390, profileAudio: true});
  for (let attempt = 0; attempt < 90; attempt++) {
    if (await session.evaluate('!!window.__localGameplayQA?.ready')) break;
    await delay(500);
  }
  await enterBattle(1);
  await session.mark('sfx_stage_1');
  await delay(7000);
  const afterStage1 = await session.evaluate('window.__lumenSFX?.status()');
  const stage1Starts = totalStarts(afterStage1);
  check(afterStage1?.context_state === 'running', 'stage 1 browser SFX context is running');
  check(stage1Starts > 0, 'stage 1 produces real attack or hit SFX starts');
  await enterBattle(2);
  await session.mark('sfx_stage_2');
  await delay(7000);
  const afterStage2 = await session.evaluate('window.__lumenSFX?.status()');
  const stage2Starts = totalStarts(afterStage2);
  check(afterStage2?.context_state === 'running', 'stage 2 retains the browser SFX context after scene transition');
  check(stage2Starts > stage1Starts, 'stage 2 adds new attack or hit SFX starts after stage 1');
  check(!Object.keys(afterStage2?.failures || {}).length, 'stage 1 and stage 2 have no browser SFX fetch or decode failures');
} catch (error) {
  checks.push({name: String(error), pass: false});
  console.error(error);
  process.exitCode = 1;
} finally {
  const browserSfx = await session.evaluate('window.__lumenSFX?.status()').catch(() => null);
  const graph = await session.evaluate('window.__localAudioGraph').catch(() => null);
  await session.close();
  await writeFile(path.join(output, 'acceptance.json'), JSON.stringify({checks, browserSfx, graph, scope: 'Local Chrome regression using real CH01-N01 and CH01-N02 combat entry; verifies browser SFX start counters and context continuity, not human listening.'}, null, 2));
}
