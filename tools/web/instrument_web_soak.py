"""Inject an opt-in, invisible RAF soak probe into a Godot Web export.

The probe is enabled only by ``?r7-soak=1``.  It does not add a visual
overlay, does not read player data, and only emits aggregate timing/memory
telemetry to the browser console for local Web QA.
"""
from __future__ import annotations

import sys
from pathlib import Path


MARKER = '<script id="r7-web-soak-probe">'
SCRIPT = r'''<script id="r7-web-soak-probe">
(() => {
  if (!new URLSearchParams(location.search).has('r7-soak')) return;
  const samples = [];
  const windowMs = 5000;
  const percentile = (values, ratio) => {
    if (!values.length) return 0;
    const sorted = [...values].sort((a, b) => a - b);
    return sorted[Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * ratio))];
  };
  let last = performance.now();
  let started = last;
  let lastReport = last;
  let frames = 0;
  let longFrames = 0;
  const report = (now) => {
    const frameTimes = samples.splice(0, samples.length);
    const memory = performance.memory || null;
    const payload = {
      elapsed_seconds: Number(((now - started) / 1000).toFixed(3)),
      window_seconds: Number(((now - lastReport) / 1000).toFixed(3)),
      frames,
      average_fps: Number((frames * 1000 / Math.max(1, now - lastReport)).toFixed(2)),
      p50_ms: Number(percentile(frameTimes, 0.50).toFixed(3)),
      p95_ms: Number(percentile(frameTimes, 0.95).toFixed(3)),
      p99_ms: Number(percentile(frameTimes, 0.99).toFixed(3)),
      long_frames_gt_100ms: longFrames,
      used_js_heap_bytes: memory ? memory.usedJSHeapSize : null,
      total_js_heap_bytes: memory ? memory.totalJSHeapSize : null,
    };
    console.log('R7_RAF_SAMPLE ' + JSON.stringify(payload));
    lastReport = now;
    frames = 0;
    longFrames = 0;
  };
  const tick = (now) => {
    const delta = now - last;
    last = now;
    if (delta > 0 && delta < 1000) {
      samples.push(delta);
      if (delta > 100) longFrames += 1;
    }
    frames += 1;
    if (now - lastReport >= windowMs) report(now);
    requestAnimationFrame(tick);
  };
  console.log('R7_RAF_PROBE_READY window_ms=' + windowMs);
  requestAnimationFrame(tick);
})();
</script>'''


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit('usage: instrument_web_soak.py <web-release-directory>')
    html_path = Path(sys.argv[1]).resolve() / 'index.html'
    if not html_path.is_file():
        raise SystemExit(f'missing Web entry point: {html_path}')
    html = html_path.read_text(encoding='utf-8')
    if MARKER in html:
        start = html.index(MARKER)
        end = html.index('</script>', start) + len('</script>')
        html = html[:start] + html[end:]
    if '</body>' not in html:
        raise SystemExit('Web entry point has no body closing tag')
    html = html.replace('</body>', SCRIPT + '\n\t</body>', 1)
    html_path.write_text(html, encoding='utf-8', newline='\n')
    print('R7_WEB_RAF_PROBE=PASS')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
