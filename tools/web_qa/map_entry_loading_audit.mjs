import {writeFile} from 'node:fs/promises';
import path from 'node:path';
import {GameplaySession} from './gameplay_session.mjs';

const [output, url, port = '9461'] = process.argv.slice(2);
const session = new GameplaySession(output);
const sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const checks = [];
const samples = [];
const check = (condition, name) => {
  const item = {pass: !!condition, name};
  checks.push(item);
  console.log(JSON.stringify(item));
  if (!item.pass) throw new Error(name);
};
const contained = rect => rect[0] >= -1 && rect[1] >= -1 && rect[0] + rect[2] <= session.viewport.width + 1 && rect[1] + rect[3] <= session.viewport.height + 1;
async function tapStoryAdvance(state) {
  const button = state.buttons.find(candidate => !candidate.disabled && contained(candidate.rect) && ['DEV 전체 스킵', '다음'].includes(candidate.text));
  if (!button) throw new Error('story advance control is unavailable before first map');
  await session.tap(button.rect[0] + button.rect[2] / 2, button.rect[1] + button.rect[3] / 2);
  await sleep(350);
}

try {
  await session.start({
    browserPath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    url,
    port: Number(port),
    width: 1280,
    height: 720,
  });
  for (let attempt = 0; attempt < 100 && !await session.evaluate('!!window.__localGameplayQA?.ready'); attempt++) {
    await sleep(250);
  }
  check(await session.evaluate('!!window.__localGameplayQA?.ready'), 'local QA bridge is ready');

  await session.mark('first_map_entry');
  const requestedAt = Date.now();
  await session.game('prepare_fresh_first_map');
  let observedLoader = false;
  let loadingFrameSaved = false;
  let readyState = null;
  let readyAt = 0;
  let mapStartedAt = 0;
  let storyAdvanceCount = 0;
  for (let attempt = 0; attempt < 180; attempt++) {
    const state = await session.game();
    const elapsedMsec = Date.now() - requestedAt;
    const loading = !!state.transition_loading?.active;
    if (state.screen === 'STORY') {
      storyAdvanceCount++;
      await tapStoryAdvance(state);
      continue;
    }
    if (loading && !mapStartedAt) mapStartedAt = Date.now();
    observedLoader ||= loading;
    samples.push({elapsed_msec: elapsedMsec, screen: state.screen, loading, map_ready: !!state.map?.ready});
    if (loading && !loadingFrameSaved && elapsedMsec >= 250) {
      await session.screenshot('01_map_entry_loading');
      loadingFrameSaved = true;
    }
    if (state.screen === 'STAGE_SELECT' && state.map?.ready) {
      readyState = state;
      readyAt = Date.now();
      break;
    }
    if (state.buttons?.some(button => button.text === 'RETRY')) throw new Error('map entry showed retry');
    await sleep(150);
  }
  check(observedLoader, 'first map stays behind the dedicated loading surface');
  check(readyState != null, 'first CH01 map becomes ready');
  check(readyState.map.natural_terrain && readyState.map.natural_chunks > 0, 'ready map includes natural terrain');
  check(readyState.map.persistent_grid_cells > 100 && readyState.map.persistent_grid_drawn > 0, 'ready map keeps its faint full-map grid');
  check(readyState.map.movement_points === 3 && readyState.map.movement_points_max === 3, 'untouched first operation starts with three movement points');
  check(readyState.map.reachable > 7, 'first operation exposes more than a one-cell movement range');
  const tutorialSkip = readyState.buttons.find(button => !button.disabled && contained(button.rect) && button.text === '안내 건너뛰기');
  if (tutorialSkip) {
    await session.tap(tutorialSkip.rect[0] + tutorialSkip.rect[2] / 2, tutorialSkip.rect[1] + tutorialSkip.rect[3] / 2);
    await sleep(350);
    readyState = await session.game();
  }
  check(!readyState.modals?.some(modal => modal.name === 'FirstMapTutorial'), 'map screenshot is captured without the first-operation tutorial cover');
  await session.checkpoint('02_map_ready_landscape');
  const elapsedMsec = readyAt - (mapStartedAt || requestedAt);
  await writeFile(path.join(output, 'map_entry_timing.json'), JSON.stringify({
    elapsed_msec: elapsedMsec,
    story_advance_count: storyAdvanceCount,
    map_preload_msec: readyState.map_preload_msec,
    density_cache: readyState.density_cache,
    map: readyState.map,
    loader_frame_captured: loadingFrameSaved,
    samples,
  }, null, 2));
  console.log(JSON.stringify({elapsed_msec: elapsedMsec, map_preload_msec: readyState.map_preload_msec, status: readyState.map.status}));
} catch (error) {
  checks.push({pass: false, name: String(error)});
  console.error(error);
  await session.screenshot('failure').catch(() => {});
  process.exitCode = 1;
} finally {
  await session.close().catch(() => {});
  await writeFile(path.join(output, 'acceptance.json'), JSON.stringify({
    checks,
    scope: 'Local 1280x720 Chrome first-map fixture. No deployed files, real user save, or game balance data are modified.',
  }, null, 2));
}
