# Combat Party Art and Animation QA — R27

Date: 2026-08-17

## Outcome

- Five original adult female player combat cutouts replaced the code-drawn player placeholders in the active HTML battle.
- Source generation: Codex built-in `imagegen`; no separately billed API key, external paid model, Krea2, or runtime network dependency was used.
- The earlier local SDXL guardian candidate was retained as historical DEV work but is no longer the active player sprite.
- The supplied Blue Archive GIF was used only to study general motion timing: high three-quarter combat view, planted feet, short anticipation, upper-body/weapon recoil, fast recovery, and head-following HP UI. Character design and frames were not copied.

## Final prompt set

All five prompts shared these constraints: exactly one original adult woman; premium 2D anime mobile-RPG SD rendering; approximately three-head proportions; full-body transparent cutout; left-side deployment facing screen-right in a three-quarter view while looking roughly 30 degrees downward; maximum non-explicit exposure with opaque chest/groin coverage; connected hands and equipment; no copyrighted character, male, child, school uniform, text, watermark, detached equipment, or extra limbs.

Role-specific prompt subjects:

- CHR001 GUARDIAN: teal/gold long-ponytail shield fighter with the forward hand visibly gripping one shield.
- CHR002 VANGUARD: coral/black short-haired swordswoman gripping one broad blade with both hands.
- CHR003 ASSAULT: icy-blue/white/violet riflewoman with stock, trigger hand, and fore-end support hand connected.
- CHR004 ASSAULT: violet/magenta energy-carbine operative in a low forward firing stance.
- CHR005 ARTILLERY: blonde/black/gold heavy gunner physically bracing one anomaly cannon.

## Runtime packs

Each active pack contains 80 transparent 512×512 frames at 12 FPS:

- idle 8
- move 12
- basic_attack 8
- normal_skill 12
- ultimate 18
- hit 4
- down 8
- victory 10

Total active player frames: **400**.

The deterministic cutout rig locks the feet to `(0.50, 0.88)`, stores a per-character `head_anchor`, and applies role-specific anticipation, lunge/recoil, hit reaction, recovery, and ranged muzzle flash. Damage remains authoritative in the 30 Hz `BattleSimulation`; visual frames never decide damage.

## Visual QA

- HTML path executed: title → home → CH01-N01 → live battle → result.
- All five generated player assets visible simultaneously: PASS.
- Entry MOVE playback: PASS.
- BASIC_ATTACK playback and ranged projectile/flash presentation: PASS.
- HIT event now changes animation state: PASS; the prior unreachable branch was corrected.
- HP bars follow the individual `head_anchor` above each silhouette: PASS.
- Player spacing prevents the prior severe overlap: PASS.
- Browser console warnings/errors during the final battle: 0.
- Godot 4.7.1 headless suite: 69 PASS / 0 FAIL.

Evidence:

- `reports/art_qa/party_r27_animation_preview.gif`
- `reports/screenshots/battle_r27_entry.png`
- `reports/screenshots/battle_r27_attack.png`

## Status boundary

These are real runtime cutout animation assets and no longer code-native player placeholders. They remain `DEV_CUTOUT_RIG_ANIMATION`, not final hand-redrawn frame animation. Enemy art is still a separate nonhuman DEV placeholder task.
