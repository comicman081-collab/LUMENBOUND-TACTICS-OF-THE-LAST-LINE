# Reproducible Blender Commands

Blender binary:

`C:\Program Files\Blender Foundation\Blender 4.5\blender.exe`

Background invocation contract:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 4.5\blender.exe' --background '<R5 source.blend>' --python 'D:\AI 종합 폴더\Games\asset_share\blender\premium\<builder>.py' -- --revision R5 --seed <manifest-seed>
```

The authoritative per-asset source, seed, output path, dimensions, SHA-256, and generator version are stored in:

- `asset_share/exports/premium/pilot/R5/pilot_manifest.json`
- `asset_share/exports/premium/pilot/R5/sd/<entity>/animation_manifest.json`
- `asset_share/exports/premium/pilot/R5/validation_report.json`

The PowerShell entry point is `tools/powershell/BUILD_PREMIUM_PILOT.ps1`. It validates Blender version, input paths, PNG dimensions/alpha, records hashes, and exits non-zero on technical failure.
