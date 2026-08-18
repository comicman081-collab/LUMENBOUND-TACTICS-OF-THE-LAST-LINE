# Combat Direction and Animation QA — R21 to R26

Date: 2026-08-17

## Required contract

- Player deployment: left side, looking lower-right at approximately 30 degrees.
- Enemy deployment: right side, looking left.
- Asymmetric player assets: `SEPARATE_LEFT_RIGHT`; runtime mirroring is prohibited.
- Adult women only for human/humanoid characters.
- Attire: maximum non-explicit exposure with opaque chest and groin coverage.
- Damage authority: deterministic `BattleSimulation`; animation only visualizes emitted events.

## Visual review

- R21: rejected. Direction, prop count, and shield attachment were inconsistent.
- R22: rejected. Body and face stayed too frontal; several variants detached the shield.
- R23: rejected as final art. Face turn improved, but the grip pass detached the shield.
- R24: rejected as final art. Deterministic shield translation overlapped the body but did not create a real hand/wrist connection.
- R25: rejected. The shield touched the body silhouette, but the hand and wrist remained hidden.
- R26v01/v02/v04: rejected. Grip remained hidden.
- R26v03: selected only as `DEV_DIRECTION_SOURCE`. The shoulder-to-forearm chain visibly connects to the shield, the lower-right gaze and exposure contract remain readable, and no extra weapon or limb is visible. Finger anatomy and authored limb animation remain below production-final quality.

Selected source:

`work/art_gen/sdxl_guardian_visible_grip_r26/chr001_maeru_guardian_combat_right30_r26v03_seed171313.png`

SHA-256: `0b6fdb1f65cbc3a4b6fa0fd012ea037a11a827b448ccc56e44efe040eca1c076`

## Runtime animation pack

Path: `godot/assets/generated_import/characters/sd_chr001_maeru_combat_r26_dev/`

- Frame canvas: 512×512 transparent PNG.
- Foot anchor: `(0.50, 0.88)`.
- Default playback: 12 FPS.
- Facing policy: `SEPARATE_LEFT_RIGHT`.
- Frame counts: idle 8, move 12, basic attack 8, normal skill 12, ultimate 18, hit 4, down 8, victory 10.
- Total individual frames: 80.
- Sheets: 2048×2048 maximum; ultimate is split across two sheets.
- Runtime states react to battle events, pause state, and 1×/2×/3× speed.

The current animation pack is a deterministic whole-character DEV motion derivation. It is visibly animated and runtime-valid, but it is not reported as final hand-authored separated-limb animation.

## Verification

- Godot engine: 4.7.1 stable official.
- Headless tests: 69 total, 69 passed, 0 failed.
- Web Development export: passed.
- Local HTTP browser path: title → home → CH01-N01 → battle → result passed.
- Compatibility renderer offscreen capture: 10 screenshots written to `reports/screenshots/`.
- Android: out of scope for the current HTML-only phase.
