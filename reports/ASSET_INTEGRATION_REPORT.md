# Asset Integration Report

Date: 2026-08-17

## Procedural factory bridge

Status: **SYNCED — canonical contract path**

- Factory: `D:\AI 종합 폴더\Games\asset_share`
- Package/generator: 0.1.0 / 1.0.0
- Manifests scanned: 214; parse failures: 0; latest families: 44.
- Canonical output: `godot/assets/generated_import/`.
- Files synchronized: 93 PNG/atlas outputs; first canonical sync copied 93, repeat sync copied 0 and reused 93.
- Godot manifest check: 93 entries, 0 missing.
- Source manifest, preset, dimensions/alpha, source/export paths and SHA-256 are retained.

The external factory and linked sources were not modified. GLB inputs remain untouched and are not used as final SD combat characters. The former `placeholders_legacy` duplicate is preserved as an ignored archive, not a runtime registry.

## Active combat presentation

- Five playable character packs and two nonhuman enemy packs are connected to `BattleView`.
- Each active pack has a 512×512 common canvas, foot/head anchors and 80 frames: 8/12/8/12/18/4/8/10.
- Active unit frames: 560; animated projectile packs: 7; projectile frames: 56.
- Projectile travel contracts are 0.05–0.15 seconds.
- Player art faces lower-right at roughly 30° from the left deployment; enemy art faces left from the right deployment.
- Damage decisions remain simulation events; animation only presents the result.

These are `DEV_CUTOUT_RIG_ANIMATION` / `DEV_CODE_RENDERED_VFX` assets. They passed technical integration and browser visual QA but are not claimed as final hand-authored production animation.

## Local generation policy

- `C:\AI_MODELS` and `C:\AI_ENVS` are read-only source roots; original models were not modified.
- Krea2 is permanently excluded.
- Rejected local SDXL/ControlNet/Blender candidates remain quarantined and are not runtime art.
- Human/humanoid playable assets obey FEMALE/ADULT policy; enemies are genderless nonhuman.
