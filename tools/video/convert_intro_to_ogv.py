import sys
from pathlib import Path

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
scene.frame_end = clip.frame_duration
movie.frame_final_duration = clip.frame_duration
sound.frame_final_duration = clip.frame_duration

scene.render.image_settings.file_format = "FFMPEG"
scene.render.ffmpeg.format = "OGG"
scene.render.ffmpeg.codec = "THEORA"
scene.render.ffmpeg.constant_rate_factor = "MEDIUM"
scene.render.ffmpeg.audio_codec = "VORBIS"
scene.render.ffmpeg.audio_bitrate = 192
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
    },
)
bpy.ops.render.render(animation=True)
