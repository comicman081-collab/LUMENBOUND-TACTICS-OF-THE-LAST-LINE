# R7 Baseline Status Audit

Audit date: 2026-08-18 (Asia/Seoul)

## Reproducible baseline

- Web baseline: `builds/baseline_r6p5/SD_STORY_RPG_R6P5_WEB_BASELINE.zip`
- Bytes: `268,919,133`
- SHA-256: `9A0B03F50C9C4D1FBFB4053EEBC3BB839D230DCB6C0939F1B42D724094BC9999`
- Review baseline: `builds/baseline_r6p5/SD_STORY_RPG_R6P5_REVIEW_BASELINE.zip`
- Bytes: `48,892,417`
- SHA-256: `AFF455BDBBA3EF4980F7C4D9741FC728834B5921D601BC7E4AF4A5222DE1B793`
- Baseline source manifest rows: `4,620`
- Static tests: `60/60 PASS`
- Godot runtime tests: `87/87 PASS`
- Combined baseline: `147/147 PASS`

The current hashes match the values reported for R6P5. The source tree is not a Git worktree, so the copied ZIPs and file manifests are the reversible R7 starting snapshot.

## Active combat-pack reconciliation

The count below follows the active mapping in `godot/battle/view/battle_sprite_library.gd`; superseded duplicate manifests are not double-counted.

| Entity group | Total | Premium active | Legacy active | Runtime fallback |
|---|---:|---:|---:|---:|
| Players | 8 | 2 (`CHR001`, `CHR008`) | 4 (`CHR002`–`CHR005`) | 2 (`CHR006`, `CHR007`) |
| Enemies, including bosses | 11 | 3 (`ENM001`, `ENM007`, `BOSS001`) | 1 (`ENM002`) | 7 |

The reported five premium 80-frame packs are exactly two player packs, two enemy packs, and one boss pack. The older generated-import tree also contains legacy packs, including IDs superseded by premium mappings; those are lineage evidence, not additional active entities. Therefore “players remaining 2 / enemies remaining 7” means active fallback replacement work, not the total number of authored frame-pack directories.

R7 does not mass-produce the remaining character or enemy packs. Map pawns use the approved premium pilot characters where available and the authored squad-standard token otherwise.

## Balance evidence

`reports/FINAL_BALANCE_HARDENING_REPORT.md` exists and records 10,000 deterministic runs. The latest recorded recommended-party results include:

- `CH01-N10` AUTO: win rate `86.0%`, mean `51.858s`.
- `CH01-N10` scripted manual ultimate: win rate `91.0%`, mean `52.402s`.
- `CH01-H05` AUTO: win rate `47.5%`, mean `71.280s`.
- `CH01-H05` scripted manual ultimate: win rate `47.0%`, mean `72.880s`.

The earlier N10 result of 100% / 27.2847s is therefore superseded and the over-easy classification is resolved by existing data. R7 freezes battle data and only checks deterministic regression.

## Reference availability

The file `1000069770.mp4` was not present in the project, Codex attachment cache, or current temporary-file search scope at audit time. R7 therefore implements only the interaction grammar explicitly described by the user (2.5D hex terrain, selection, route preview, squad movement, detail panel, focus/fade transition). It does not claim independent frame-by-frame analysis and does not package any reference footage.

## Environment note

The baseline Godot headless run emitted a Windows certificate-store read warning while all 87 runtime assertions passed. The project performs no runtime network access; the warning is retained as an environment note and is not represented as a functional failure.
