import test from 'node:test';
import assert from 'node:assert/strict';
import {frameStats, summarizeCaptures, performanceAcceptance} from './fps_metrics.mjs';

test('one percent low includes the worst frame and is not inverse p99', () => {
  const times = [...Array(100).fill(10), 100];
  const result = frameStats(times);
  assert.equal(result.slowest_one_percent_frames, 2);
  assert.equal(result.one_percent_low_fps, 1000 / 55);
  assert.equal(result.p99_frame_ms, 10);
  assert.equal(times.at(-1), 100);
});
test('invalid sampling data fails instead of silently discarding it', () => {
  assert.equal(frameStats([]), null);
  for (const invalid of [NaN, Infinity, 0, -1]) assert.throws(() => frameStats([16, invalid]));
});
test('static dialogue and loading do not dilute combat; slow active frames remain', () => {
  const capture = (label, rows) => ({label, engine: {frames: [[0, 1, 'BATTLE'], ...rows]}});
  const groups = summarizeCaptures([
    capture('combat_CH01-N20', [[1, 16, 'BATTLE|READY|WAVE:3'], [2, 80, 'BATTLE|READY|WAVE:3|CUTIN'],
      ...Array(1000).fill([3, 16, 'BATTLE|READY|WAVE:3|AFTERMATH_DIALOGUE']),
      [4, 400, 'BATTLE|LOADING(BATTLE_RESULT)']]),
    capture('combat_CH01-N20_exit', [[5, 20, 'BATTLE|READY|WAVE:3|BOSS_VICTORY'], [6, 16, 'RESULT']]),
  ]);
  assert.equal(groups.combat_CH01_N20, undefined);
  assert.equal(groups['combat_CH01-N20_complete_gameplay'].frames, 3);
  assert.equal(groups['combat_CH01-N20_complete_gameplay'].one_percent_low_fps, 12.5);
  assert.equal(groups['combat_CH01-N20_complete_gameplay'].max_frame_ms, 80);
  assert.equal(groups['combat_CH01-N20_cutins_gameplay'].max_frame_ms, 80);
  assert.equal(groups['combat_CH01-N20_all'].max_frame_ms, 400);
});
test('30 exactly fails the requested greater-than-30 target and missing cases fail', () => {
  const names = ['map_idle_gameplay', 'map_move_0_gameplay', 'map_move_1_gameplay', 'map_move_2_gameplay'];
  const groups = Object.fromEntries(names.map(name => [name, {frames: 600, one_percent_low_fps: 31}]));
  assert.equal(performanceAcceptance(groups, 'map').pass, true);
  groups.map_move_0_gameplay.one_percent_low_fps = 30;
  assert.equal(performanceAcceptance(groups, 'map').pass, false);
  delete groups.map_move_0_gameplay;
  assert.equal(performanceAcceptance(groups, 'map').pass, false);
});

test('wave scenes remain in active combat and receive their own performance gate', () => {
  const groups = summarizeCaptures([{label:'combat_CH01-N20',engine:{frames:[
    [0,1,'BATTLE'],[1,16,'BATTLE|READY|WAVE:2|WAVE_TRANSITION'],[2,40,'BATTLE|READY|WAVE:2|WAVE_TRANSITION'],
    [3,16,'BATTLE|READY|WAVE:3|BOSS_ENTRY']]}}]);
  assert.equal(groups['combat_CH01-N20_complete_gameplay'].frames,3);
  assert.equal(groups['combat_CH01-N20_wave_transition_gameplay'].frames,2);
  assert.equal(groups['combat_CH01-N20_wave_transition_gameplay'].one_percent_low_fps,25);
  const waveCase=performanceAcceptance(groups,'boss',true).cases.find(c=>c.name==='combat_CH01-N20_wave_transition_gameplay');
  assert.equal(waveCase.pass,false);
});
