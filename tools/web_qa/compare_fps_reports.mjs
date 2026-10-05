import {readdir, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {summarizeCaptures, performanceAcceptance} from './fps_metrics.mjs';

const [baseline, candidate, output] = process.argv.slice(2);
async function report(folder) {
  const names = (await readdir(folder)).filter(name => name.endsWith('_raw_frames.json')).sort();
  const captures = await Promise.all(names.map(async name => JSON.parse(await readFile(path.join(folder, name), 'utf8'))));
  const previous = JSON.parse(await readFile(path.join(folder, 'fps_summary.json'), 'utf8'));
  const bootstrap = JSON.parse(await readFile(path.join(folder, 'bootstrap_browser_frames.json'), 'utf8'));
  const groups = summarizeCaptures(captures);
  return {folder: path.resolve(folder), resolution: previous.resolution, renderer: bootstrap.renderer,
    runtime_checks_pass: previous.checks.every(check => check.pass),
    acceptance: performanceAcceptance(groups), groups};
}
const result = {baseline: await report(baseline), candidate: await report(candidate)};
result.comparison = result.candidate.acceptance.cases.map(c => ({case: c.name,
  baseline_one_percent_low_fps: result.baseline.groups[c.name]?.one_percent_low_fps ?? null,
  candidate_one_percent_low_fps: c.one_percent_low_fps, pass: c.pass}));
result.pass = result.baseline.runtime_checks_pass && result.candidate.runtime_checks_pass &&
  result.candidate.acceptance.pass;
await writeFile(output, JSON.stringify(result, null, 2));
console.log(JSON.stringify({pass: result.pass, comparison: result.comparison}, null, 2));
if (!result.pass) process.exitCode = 1;
