# Enemy and Projectile Animation QA — R28

Date: 2026-08-17

## Outcome

- ENM001 and ENM002 code-drawn placeholders were replaced in the active HTML battle by two original, genderless nonhuman machine cutouts.
- Each enemy has a full 80-frame, transparent 512×512 combat pack: idle 8, move 12, basic attack 8, normal skill 12, ultimate 18, hit 4, down 8, victory 10.
- Both packs obey `THREE_QUARTER_LEFT_DOWN_30`, `ENEMY_RIGHT_SIDE_FACING_LEFT`, `SEPARATE_LEFT_RIGHT`, and foot anchor `(0.50, 0.88)`.
- Seven distinct 8-frame projectile/VFX packs are active: five player characters plus the two test enemies. Total projectile frames: **56**.
- Damage remains authoritative in the deterministic 30 Hz simulation. Projectiles and cutout frames only visualize emitted battle events.

## Enemy generation prompts

Both images were generated with Codex built-in `imagegen`; no separately billed API key, external paid model, Krea2, or runtime download was used.

- ENM001: exactly one original genderless nonhuman crystalline beetle-wolf rush drone; four armored legs and physically connected foreclaws; navy/gunmetal armor, coral-orange core, cyan navigation lights; low charging silhouette; right-side deployment facing screen-left in a three-quarter view and aiming about 30 degrees downward; transparent full-body cutout; no human traits, text, UI, detached equipment, copied franchise design, or extra unit.
- ENM002: exactly one original genderless nonhuman hovering arc-mote turret; faceted blue-gray segmented body, stabilizer fins, physically connected long energy emitter, cyan conduits, crimson-magenta core; right-side deployment facing screen-left in a three-quarter view and aiming about 30 degrees downward; transparent full-unit cutout; no human traits, text, UI, detached weapon, copied franchise design, or extra unit.

The generated source originals are preserved unchanged under `work/art_gen/imagegen_enemies_r28/`. Runtime animation derivatives are separately stored under `godot/assets/generated_import/enemies/`.

## Character-specific VFX

- CHR001: teal/gold shield-energy crescent.
- CHR002: coral/white close-range blade crescent.
- CHR003: icy cyan/violet rifle tracer.
- CHR004: magenta/violet anomaly energy bolt.
- CHR005: emerald/gold heavy-cannon orb with rotating rings.
- ENM001: orange crystal claw arc facing left.
- ENM002: crimson/cyan arc bolt facing left.

Every projectile pack has a validated manifest, 256×256 transparent frames, 20 FPS playback, explicit orientation and runtime size, and no runtime Python dependency. BASIC attacks create VFX from the attack event; NORMAL and ULTIMATE damage create VFX from their authoritative damage events. Projectile animation time freezes while battle pause is active.

## Runtime visual QA

- HTML path executed: title → home → CH01-N01 → live battle → result.
- ENM001 and ENM002 visible as distinct animated machine sprites: PASS.
- Enemy entry MOVE and event-driven BASIC_ATTACK/HIT playback: PASS.
- ENM001 left-facing claw VFX observed in live battle: PASS.
- CHR003 tracer and CHR005 cannon orb observed in live battle: PASS.
- Enemy and player HP bars remain above manifest-derived head anchors: PASS.
- Browser console warnings/errors: **0**.
- Godot 4.7.1 headless suite: **71 PASS / 0 FAIL**.

Evidence:

- `reports/art_qa/player_projectiles_r28_preview.gif`
- `reports/art_qa/enemy_projectile_r28_preview.gif`
- `reports/screenshots/battle_r28_enemies.png`
- `reports/screenshots/battle_r28_enemy_projectile.png`
- `reports/screenshots/battle_r28_player_projectiles.png`

## Status boundary

These are real runtime assets and animations, but remain explicitly marked `DEV_CUTOUT_RIG_ANIMATION` and `DEV_CODE_RENDERED_VFX`. They are not claimed as final hand-redrawn production animation. Commercial-release rights and final art-direction approval remain separate review gates.

## R29 projectile-speed correction

The initial 0.40-second visual flight was rejected as too slow. Runtime flight is now data-driven per source and constrained by regression test to 0.05–0.15 seconds:

- CHR001 0.13 s
- CHR002 0.08 s
- CHR003 0.06 s
- CHR004 0.09 s
- CHR005 0.12 s
- ENM001 0.08 s
- ENM002 0.09 s

All eight authored VFX frames are normalized over each short flight duration instead of playing only the first frames. These are presentation objects; hit and dodge outcomes remain deterministic simulation results rather than collision with the rendered sprite. Final HTML runtime console warnings/errors: 0. Godot suite: 72 PASS / 0 FAIL.
