import sys
from pathlib import Path

INTRO_CUT_SECONDS = 53.0
VIDEO_BITRATE_KBPS = 2200
AUDIO_BITRATE_KBPS = 128

import bpy


def _arguments_after_double_dash() -> list[str]:
    if "--" not in sys.argv:
        raise RuntimeError("expected input and output paths after --")
    return sys.argv[sys.argv.index("--") + 1 :]


arguments = _arguments_after_double_dash()
if len(arguments) != 2:
    raise RuntimeError("usage: blender -b --python convert_intro_to_ogv.py -- INPUT OUTPUT")

source_path = str(Path(arguments[0]).resolve())
output_path = str(Path(arguments[1]).resolve())
scene = bpy.context.scene
editor = scene.sequence_editor_create()
clip = bpy.data.movieclips.load(source_path)
movie = editor.sequences.new_movie("LumenboundIntroVideo", source_path, channel=1, frame_start=1)
sound = editor.sequences.new_sound("LumenboundIntroAudio", source_path, channel=2, frame_start=1)

scene.render.resolution_x = clip.size[0]
scene.render.resolution_y = clip.size[1]
scene.render.resolution_percentage = 100
scene.render.fps = round(clip.fps)
scene.render.fps_base = 1.0
scene.frame_start = 1
# The source MV concludes with a third-party Flow Music end card.  The game
# intro ends cleanly at the final gameplay frame immediately before that card
# fades in, so the runtime asset must never inherit the source's last seconds.
cut_frame = min(clip.frame_duration, round(clip.fps * INTRO_CUT_SECONDS))
scene.frame_end = cut_frame
movie.frame_final_duration = cut_frame
sound.frame_final_duration = cut_frame

scene.render.image_settings.file_format = "FFMPEG"
scene.render.ffmpeg.format = "OGG"
scene.render.ffmpeg.codec = "THEORA"
# The prior CRF-only encode occupied 39 MiB inside the startup PCK. A bounded
# 720p rate preserves fast battle motion without restoring that cold-launch
# penalty; 2200 kbps is the quality floor for this high-motion intro.
scene.render.ffmpeg.constant_rate_factor = "NONE"
scene.render.ffmpeg.video_bitrate = VIDEO_BITRATE_KBPS
scene.render.ffmpeg.audio_codec = "VORBIS"
scene.render.ffmpeg.audio_bitrate = AUDIO_BITRATE_KBPS
scene.render.filepath = output_path

print(
    "INTRO_TRANSCODE",
    {
        "source": source_path,
        "output": output_path,
        "resolution": (scene.render.resolution_x, scene.render.resolution_y),
        "fps": scene.render.fps,
        "frames": scene.frame_end,
        "duration_seconds": scene.frame_end / scene.render.fps,
        "source_cut_seconds": INTRO_CUT_SECONDS,
        "video_bitrate_kbps": VIDEO_BITRATE_KBPS,
        "audio_bitrate_kbps": AUDIO_BITRATE_KBPS,
    },
)
bpy.ops.render.render(animation=True)
