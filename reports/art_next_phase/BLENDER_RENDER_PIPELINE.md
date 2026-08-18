# Blender Render Pipeline

- Executable: `C:\Program Files\Blender Foundation\Blender 4.5\blender.exe`
- Version: Blender 4.5.11 LTS
- Invocation: `blender.exe --background <source.blend> --python <script.py> -- <arguments>`
- Engine: Eevee Next, transparent film, supersampled source then contracted output
- Camera: orthographic/controlled perspective presets; players lower-right 30 degrees, enemies lower-left
- Output: 512×512 RGBA SD frames at 12 fps; 1920×1080 backgrounds/CG; 1024×1536 portrait; 2048×3072 master
- Compositor/process: alpha flood removal, component pruning, alpha-edge correction, color control and manifest hashing
- Reproduction root: `D:\AI 종합 폴더\Games\asset_share\blender\premium`
- Source root: `D:\AI 종합 폴더\Games\asset_share\blender_sources`
- Runtime root: `godot/assets/art`

R1–R4 and failed VFX attempts are preserved. R5 is technically reproducible; identical input is protected from silent overwrite rather than regenerated in place.
