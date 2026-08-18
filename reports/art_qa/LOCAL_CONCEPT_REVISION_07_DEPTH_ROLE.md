# Local Concept Revision 07 — Depth Role QA

Date: 2026-08-17

## Scope

- Local SDXL Base 1.0 plus local SDXL Depth ControlNet
- Project-authored depth masses; no copied pose or third-party reference image
- Source models preserved read-only
- Krea2 excluded
- Outputs are rejected QA evidence, not runtime assets

## Result

| Candidate | Female | Adult | Attire | Full body / role prop | Premium SD asset quality | Integration |
|---|---|---|---|---|---|---|
| CHR001 Guardian R07 | PASS | PASS | PASS | PASS | FAIL: insufficient SD proportion and finish | REJECTED |
| CHR008 Medic R07 | PASS | FAIL: ambiguous facial read | PASS | Ring PASS; anatomy FAIL | FAIL | REJECTED |

Depth guidance avoided the severe stitched-line artifact seen in R06. The Guardian result is structurally coherent and correctly female, adult, full-body, revealing-but-covered, and shield-readable. It still does not reach the intended premium SD combat style. The Medic result does not pass the unambiguous adult-read or anatomy gates.

Neither output is copied to the Godot import tree or admitted to the Blender bridge. Further generation must use an appearance model whose exact commercial terms and lineage are approved; lowering the gate to accept these images is prohibited.
