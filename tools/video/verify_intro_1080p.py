"""Verify a built intro's frames and unchanged music; extract local review stills."""
import argparse
import json
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build', type=Path)
    parser.add_argument('report', type=Path)
    parser.add_argument('--ffmpeg', type=Path, required=True)
    parser.add_argument('--ffprobe', type=Path, required=True)
    args = parser.parse_args()
    build, report = args.build.resolve(), args.report.resolve()
    if not all(p.is_relative_to(ROOT) for p in (build, report)):
        raise ValueError('Only project-local review paths are allowed')
    report.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((build / 'manifest.json').read_text(encoding='utf8'))
    previous = ROOT / manifest['soundtrack_source']
    runtime = build / 'lumenbound_intro_full.ogv'
    checks = []

    def check(passed, name):
        checks.append({'name': name, 'pass': bool(passed)})
        if not passed:
            raise AssertionError(name)

    def probe(arguments, source):
        return json.loads(subprocess.check_output([str(args.ffprobe), '-v', 'error',
            *arguments, '-of', 'json', str(source)], cwd=ROOT, encoding='utf8'))

    video = probe(['-select_streams', 'v:0', '-count_frames', '-show_streams'], runtime)['streams'][0]
    check((video['width'], video['height']) == (1920, 1080), 'native 1920x1080 runtime video')
    check(video['nb_read_frames'] == '1200', 'all 1200 video frames decode')
    check(video['avg_frame_rate'] == '24/1' and float(video['duration']) == 50,
          '24 fps and exactly 50 seconds of video')
    audio_arguments = ['-select_streams', 'a:0', '-show_packets', '-show_data_hash', 'sha256']
    before, after = (probe(audio_arguments, source)['packets'] for source in (previous, runtime))
    before_hashes, after_hashes = ([packet['data_hash'] for packet in packets] for packets in (before, after))
    check(len(after_hashes) > 2000 and after_hashes == before_hashes[:len(after_hashes)],
          'every compressed audio packet matches the previous intro in order')
    check(not manifest['source_clip_audio_used'], 'none of the five new source audio streams was mapped')

    frame_numbers = [48, 239, 240, 243, 248, 288, 479, 483, 488, 528,
                     719, 723, 728, 768, 959, 963, 968, 1008, 1128, 1199]
    frames_dir = report / 'frames'
    frames_dir.mkdir(exist_ok=False)
    select = '+'.join(f'eq(n,{number})' for number in frame_numbers)
    subprocess.run([str(args.ffmpeg), '-v', 'error', '-nostdin', '-n', '-i', str(runtime),
        '-vf', f"select='{select}',scale=480:270", '-fps_mode', 'vfr', '-an',
        str(frames_dir / 'frame_%02d.png')], cwd=ROOT, check=True)
    sheet = Image.new('RGB', (1920, 300 * 5), '#0e1520')
    draw = ImageDraw.Draw(sheet)
    for index, number in enumerate(frame_numbers):
        x, y = (index % 4)*480, (index//4)*300
        with Image.open(frames_dir / f'frame_{index+1:02d}.png') as frame:
            sheet.paste(frame, (x, y+30))
        draw.text((x+10, y+7), f'{number/24:.3f}s | frame {number}', fill='white')
    sheet.save(report / 'intro_contact_sheet.jpg', quality=94)
    check(len(list(frames_dir.glob('*.png'))) == len(frame_numbers),
          'all transition and final-frame review stills extracted')
    result = {'checks': checks, 'original_audio_packets': len(before_hashes),
              'retained_audio_packets': len(after_hashes), 'runtime_video': video,
              'review_frames': frame_numbers, 'visual_review': 'contact sheet requires reviewer inspection'}
    (report / 'media_verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)
                                                  + '\n', encoding='utf8')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
