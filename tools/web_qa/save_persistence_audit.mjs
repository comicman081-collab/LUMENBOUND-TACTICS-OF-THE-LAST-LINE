import {GameplaySession} from './gameplay_session.mjs';
import {writeFile} from 'node:fs/promises';
import {isDeepStrictEqual} from 'node:util';
import path from 'node:path';

const [output, url, port = '9791'] = process.argv.slice(2);
const session = new GameplaySession(output), checks = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
function check(pass, name) {
  checks.push({pass: !!pass, name});
  console.log(JSON.stringify(checks.at(-1)));
  if (!pass) throw Error(name);
}
async function boot() {
  for (let i = 0; i < 120; i++) {
    if (await session.evaluate('!!window.__localGameplayQA?.ready')) return;
    await delay(500);
  }
  throw Error('Boot timeout');
}
async function tap(predicate) {
  const state = await session.game();
  const button = state.buttons.find(b => !b.disabled && predicate(b));
  if (!button) throw Error('Save control unavailable');
  await session.tap(button.rect[0] + button.rect[2] / 2, button.rect[1] + button.rect[3] / 2);
  await delay(400);
}
try {
  await session.start({browserPath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', url,
    port: Number(port), width: 1280, height: 720});
  await boot();
  await session.game('prepare_growth', {mode: 'funded'});
  await tap(b => b.text === '스킬업');
  const before = (await session.game()).growth;
  await session.evaluate(`(() => {
    window.__originalStorageSet = Storage.prototype.setItem;
    Storage.prototype.setItem = function(key, value) {
      if (key.startsWith('lumenbound-save-journal:')) throw new DOMException('Intentional local QA quota', 'QuotaExceededError');
      return window.__originalStorageSet.call(this, key, value);
    }; return true;
  })()`);
  await tap(b => b.name === 'GrowthSkillApply_normal');
  const failed = await session.game();
  check(failed.growth.progress.skills.normal === before.progress.skills.normal + 1, 'failed persistence retains one applied upgrade in memory');
  check(failed.growth.feedback.includes('저장하지 못했습니다'), 'storage failure does not claim save completion');
  check(failed.buttons.filter(b => b.name.startsWith('GrowthSkillApply_')).every(b => b.disabled), 'unconfirmed save blocks another material charge');
  await session.checkpoint('quota_failure');
  await session.evaluate('Storage.prototype.setItem = window.__originalStorageSet; true');
  await tap(b => b.text.includes('저장') && b.text.includes('다시'));
  const saved = (await session.game()).growth;
  check(saved.feedback.includes('저장 완료'), 'explicit retry confirms persistence');
  check(isDeepStrictEqual(saved.progress, failed.growth.progress) && isDeepStrictEqual(saved.inventory, failed.growth.inventory), 'save retry never charges or upgrades twice');
  await session.evaluate('setTimeout(() => location.reload(), 0); true');
  await delay(600); await boot();
  await session.game('prepare_growth', {mode: 'resume'});
  const restored = await session.game();
  check(isDeepStrictEqual(restored.growth.progress, saved.progress), 'immediate reload restores confirmed skill state');
  check(isDeepStrictEqual(restored.growth.inventory, saved.inventory), 'immediate reload restores exact paid inventory');
  check(restored.sandbox.production_read_attempt_count === 0 && restored.sandbox.production_write_attempt_count === 0, 'fault injection stays in the isolated QA save');
  check(session.events.filter(e => e.method === 'Runtime.exceptionThrown').length === 0, 'no unhandled browser exceptions');
  await session.checkpoint('restored');
} catch (error) {
  checks.push({pass: false, name: String(error)});
  console.error(error);
  process.exitCode = 1;
  await session.checkpoint('failure').catch(() => {});
} finally {
  await session.close();
  await writeFile(path.join(output, 'acceptance.json'), JSON.stringify({checks,
    scope: 'Actual browser storage failure, UI retry, and immediate reload in a new isolated profile.'}, null, 2));
}
