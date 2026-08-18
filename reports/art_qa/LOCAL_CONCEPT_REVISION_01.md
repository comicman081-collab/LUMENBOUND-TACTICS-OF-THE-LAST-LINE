# Local concept revision 01 visual QA

Model: local SDXL Base 1.0 only. Krea2 used: no. Reference screenshots were
observed only for abstract quality comparison and were not passed to the model.

| Candidate | Useful evidence | Hard failures | Verdict |
|---|---|---|---|
| CHR001 R01 | Stronger face, hair layering, ornament density | Wrong white hair; staff/lantern replaces shield; malformed hand; fantasy hood dominates | REJECTED_AS_FINAL |
| CHR001 R02 | Clean readable silhouette; chestnut hair; useful coat palette | Shield absent; material response too flat; rigid stance; young-looking proportions | REJECTED_AS_FINAL |
| CHR008 R01 | Appealing face and layered mint bob | Bust crop; no full body; no diagnostic ring; hand incomplete | REJECTED_AS_FINAL |
| CHR008 R02 | Full-body chibi direction and color separation | Diagnostic ring absent; sparse medic detail; weak hand pose; mostly 2D flat shading | REJECTED_AS_FINAL |

Compared with the user-provided commercial screenshots, none meets full-screen
character or in-game SD reference parity. No candidate is promoted to the
Godot runtime, `VISUAL_PASS`, `REFERENCE_PARITY_PASS`, or `PRODUCTION_APPROVED`.
