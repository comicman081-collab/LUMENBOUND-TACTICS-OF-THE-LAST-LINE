"""Assemble the five user clips locally; keep only the previous intro soundtrack.

No source file is modified. Outputs and FFmpeg scratch stay inside the project.
At 24 fps, a seven-frame dissolve is 0.291667 s. The first four clips are
retimed from 240 to 247 frames so overlapping them still yields exactly 50 s.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FPS, SOURCE_FRAMES, OVERLAP_FRAMES = 24, 240, 7


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', type=Path, required=True)
    parser.add_argument('--ffprobe', type=Path, required=True)
    parser.add_argument('--soundtrack-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    old = args.soundtrack_source.resolve()
    if not output.is_relative_to(ROOT) or not old.is_relative_to(ROOT):
        raise ValueError('Project-local output and soundtrack source required')
    output.mkdir(parents=True, exist_ok=False)
    scratch = output / 'tmp'
    scratch.mkdir()
    env = {**os.environ, 'TEMP': str(scratch), 'TMP': str(scratch),
           'TMPDIR': str(scratch), 'XDG_CACHE_HOME': str(scratch)}
    commands = []

    def run(name, arguments):
        command = [str(args.ffmpeg), '-hide_banner', '-nostdin', '-n', *arguments]
        commands.append(command)
        print(name, flush=True)
        with (output / f'{name}.log').open('w', encoding='utf8') as log:
            subprocess.run(command, cwd=ROOT, env=env, stdout=log,
                           stderr=subprocess.STDOUT, check=True)

    def probe(path):
        return json.loads(subprocess.check_output([
            str(args.ffprobe), '-v', 'error', '-show_streams', '-show_format',
            '-of', 'json', str(path)], cwd=ROOT, env=env, text=True, encoding='utf8'))

    sources = [ROOT / 'intro' / f'{index}.mp4' for index in range(1, 6)]
    source_records = []
    for source in sources:
        info = probe(source)
        video = next(s for s in info['streams'] if s['codec_type'] == 'video')
        assert (video['width'], video['height'], video['avg_frame_rate'],
                int(video['nb_frames'])) == (1920, 1080, '24/1', SOURCE_FRAMES), info
        source_records.append({'path': str(source.relative_to(ROOT)),
                               'sha256': digest(source), 'probe': info})
    old_info = probe(old)
    assert any(s['codec_name'] == 'vorbis' for s in old_info['streams'])
    retained_audio = output / 'existing_intro_bgm.ogg'
    run('retain_existing_music', ['-i', str(old), '-map', '0:a:0', '-vn',
                                 '-c:a', 'copy', str(retained_audio)])

    filters = []
    for index in range(5):
        frames = SOURCE_FRAMES + (OVERLAP_FRAMES if index < 4 else 0)
        filters.append(
            f'[{index}:v]setpts={frames}/{SOURCE_FRAMES}*(PTS-STARTPTS),'
            f'fps={FPS},tpad=stop_mode=clone:stop_duration=0.1,'
            f'trim=end_frame={frames},settb=AVTB,setsar=1,format=yuv420p[v{index}]')
    previous = 'v0'
    for index in range(1, 5):
        name = f'blend{index}'
        filters.append(f'[{previous}][v{index}]xfade=transition=fade:'
                       f'duration={OVERLAP_FRAMES / FPS:.9f}:offset={index * 10}[{name}]')
        previous = name
    graph = ';\n'.join(filters)
    (output / 'filter_graph.txt').write_text(graph + '\n', encoding='utf8')
    inputs = [part for source in sources for part in ('-i', str(source))]
    silent = output / 'intro_1080p_50s_silent.mp4'
    run('assemble_silent_video', [*inputs, '-filter_complex_threads', '4',
        '-filter_complex', graph, '-map', f'[{previous}]', '-an', '-frames:v', '1200',
        '-r', str(FPS), '-c:v', 'libx264', '-preset', 'medium', '-crf', '16',
        '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(silent)])
    runtime = output / 'lumenbound_intro_full.ogv'
    run('encode_godot_video', ['-i', str(silent), '-i', str(retained_audio),
        '-map', '0:v:0', '-map', '1:a:0', '-t', '50', '-c:v', 'libtheora',
        '-q:v', '7', '-g', '48', '-pix_fmt', 'yuv420p', '-c:a', 'copy', str(runtime)])
    preview = output / 'intro_1080p_50s_with_existing_bgm.mp4'
    run('encode_preview', ['-i', str(silent), '-i', str(retained_audio),
        '-map', '0:v:0', '-map', '1:a:0', '-t', '50', '-c:v', 'copy',
        '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', str(preview)])
    probes = {p.name: probe(p) for p in (silent, retained_audio, runtime, preview)}
    assert len(probes[silent.name]['streams']) == 1, 'Source audio leaked into silent master'
    for path in (silent, runtime, preview):
        info = probes[path.name]
        video = next(s for s in info['streams'] if s['codec_type'] == 'video')
        assert (video['width'], video['height']) == (1920, 1080)
        assert abs(float(video['duration']) - 50) < .001
        run(f'decode_check_{path.suffix[1:]}_{path.stem}',
            ['-v', 'error', '-xerror', '-i', str(path), '-f', 'null', '-'])
    manifest = {'sources': source_records, 'soundtrack_source': str(old.relative_to(ROOT)),
        'soundtrack_source_sha256': digest(old), 'source_clip_audio_used': False,
        'retained_audio_method': 'Vorbis packet copy from previous runtime intro; cut at 50s',
        'fps': FPS, 'frames': 1200, 'duration_seconds': 50,
        'dissolve_frames': OVERLAP_FRAMES, 'dissolve_seconds': OVERLAP_FRAMES / FPS,
        'transition_start_seconds': [10, 20, 30, 40],
        'first_four_clip_duration_scale': 247 / 240, 'last_clip_duration_scale': 1,
        'outputs': {p.name: {'sha256': digest(p), 'bytes': p.stat().st_size,
                          'probe': probes[p.name]} for p in (silent, retained_audio, runtime, preview)},
        'commands': commands, 'validation': 'PASS: metadata, audio mapping and full decode'}
    (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)
                                         + '\n', encoding='utf8')
    print(json.dumps({'status': 'PASS', 'runtime': str(runtime),
                      'bytes': runtime.stat().st_size}, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
