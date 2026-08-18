# Foundation Discovery

Date: 2026-08-17 KST

## Workspace

- Active parent: `D:\AI 종합 폴더\Games\블아 like`.
- Project root: `D:\AI 종합 폴더\Games\블아 like\SD_STORY_RPG_GODOT`.
- Existing external projects and model roots were not overwritten.
- Superseded/rejected material is preserved under `DELETE_CANDIDATES`; an old bridge duplicate remains `.gdignore`-archived because a filesystem move was denied.

## Toolchain

- Godot: `D:\AI 종합 폴더\Godot\4.7.1-standard\Godot_v4.7.1-stable_win64_console.exe`.
- Version verified: `4.7.1.stable.official.a13da4feb` Standard.
- Renderer: Compatibility (`gl_compatibility`).
- Web export templates: installed for 4.7.1 and copied into the isolated project profile for builds.
- Isolated runtime profile: `godot/.runtime_profile`; all project scripts set `APPDATA` and `LOCALAPPDATA` before invoking Godot.
- Android SDK/ADB/device: not used; APK explicitly excluded by current instruction.
- Local build Python is used only for deterministic build-time data/asset tools, never by the exported game.

Godot import/export, GDScript parse, 87 headless assertions, Compatibility offscreen rendering and Web Release browser execution are verified. Windows native and Android application outputs are not claimed.

## Baseline

External factory baseline SHA-256 values are retained in `ASSET_FACTORY_DISCOVERY.md`. Model roots `C:\AI_MODELS` and `C:\AI_ENVS` were inspected read-only; original models were not modified.
