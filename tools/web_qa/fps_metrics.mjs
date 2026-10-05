// Keep the acceptance calculation separate from browser setup and capture.
export function frameStats(times) {
  if (!times.length) return null;
  if (times.some(t => !Number.isFinite(t) || t <= 0)) throw Error('Invalid frame interval');
  const sorted = times.slice().sort((a, b) => a - b);
  const count = Math.max(1, Math.ceil(sorted.length * .01));
  const worst = sorted.slice(-count), total = times.reduce((a, b) => a + b, 0);
  return {frames: times.length, seconds: total / 1000, average_fps: 1000 * times.length / total,
    one_percent_low_fps: 1000 / (worst.reduce((a, b) => a + b, 0) / count),
    slowest_one_percent_frames: count,
    p99_frame_ms: sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * .99) - 1)],
    max_frame_ms: sorted.at(-1), over_33_333ms: times.filter(t => t > 1000 / 30).length,
    over_50ms: times.filter(t => t > 50).length, over_100ms: times.filter(t => t > 100).length};
}

export function gameplayFrame(frame) {
  const tag = frame[2];
  return !['LOADING(', 'NOT_READY', 'NO_MAP', 'NO_VIEW', 'DEPLOYMENT', 'AFTERMATH_DIALOGUE']
    .some(excluded => tag.includes(excluded));
}

export function summarizeCaptures(captures) {
  const groups = {}, stages = new Map();
  for (const capture of captures) {
    // The first interval starts midway through a frame; retain every later hitch.
    const frames = capture.engine.frames.slice(1);
    groups[capture.label + '_all'] = frameStats(frames.map(f => f[1]));
    const active = frames.filter(f => gameplayFrame(f) &&
      f[2].startsWith(capture.label.startsWith('map') ? 'STAGE_SELECT' : 'BATTLE'));
    groups[capture.label + '_gameplay'] = frameStats(active.map(f => f[1]));
    for (const tag of new Set(active.map(f => f[2]))) {
      groups[capture.label + '::' + tag] = frameStats(active.filter(f => f[2] === tag).map(f => f[1]));
    }
    if (capture.label.startsWith('combat_')) {
      const stage = capture.label.replace(/_exit$/, '');
      stages.set(stage, [...(stages.get(stage) || []), ...active]);
    }
  }
  for (const [stage, frames] of stages) {
    groups[stage + '_complete_gameplay'] = frameStats(frames.map(f => f[1]));
    for (const [name, tag] of [['cutins', 'CUTIN'], ['wave_transition', 'WAVE_TRANSITION'], ['boss_entry', 'BOSS_ENTRY'], ['boss_victory', 'BOSS_VICTORY']]) {
      const selected = frames.filter(f => f[2].includes(tag));
      if (selected.length) groups[stage + '_' + name + '_gameplay'] = frameStats(selected.map(f => f[1]));
    }
  }
  return groups;
}

export function performanceAcceptance(groups, mode = 'full', includeWaveScenes = false) {
  const required = [];
  if (!['combat', 'boss'].includes(mode)) {
    required.push('map_idle_gameplay');
    for (let i = 0; i < (mode === 'map_profile' ? 1 : 3); i++) required.push('map_move_' + i + '_gameplay');
  }
  if (!['map', 'map_profile'].includes(mode)) {
    if (mode !== 'boss') required.push('combat_CH01-N05_complete_gameplay');
    required.push('combat_CH01-N20_complete_gameplay', 'combat_CH01-N20_cutins_gameplay',
      'combat_CH01-N20_boss_entry_gameplay', 'combat_CH01-N20_boss_victory_gameplay');
    if (includeWaveScenes) {
      if (mode !== 'boss') required.push('combat_CH01-N05_wave_transition_gameplay');
      required.push('combat_CH01-N20_wave_transition_gameplay');
    }
  }
  const cases = required.map(name => ({name, frames: groups[name]?.frames ?? 0,
    one_percent_low_fps: groups[name]?.one_percent_low_fps ?? null,
    pass: !!groups[name] && groups[name].one_percent_low_fps > 30}));
  return {target_one_percent_low_fps: 30, comparison: 'strictly greater than',
    pass: cases.every(c => c.pass), cases};
}
