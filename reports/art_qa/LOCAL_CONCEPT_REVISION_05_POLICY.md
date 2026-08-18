# Local Concept Revision 05 — Policy and Role QA

Date: 2026-08-17

## Scope

- Generator: local SDXL Base 1.0 only
- Source model path: `C:\AI_MODELS\sdxl-base-1.0`
- Source model mutated: no
- Krea2 used: no
- Runtime dependency: none
- Global character policy: `FEMALE_ONLY`, `ADULT_ONLY`, `MAXIMUM_NON_EXPLICIT`

## Visual QA result

All four R05 images visibly passed the female, adult, and maximum non-explicit attire gates. None presented as male. All four failed the role/silhouette asset gate and remain excluded from integration.

| Candidate | Policy gates | Role / framing result | Integration |
|---|---|---|---|
| CHR001 Guardian v01 | PASS | Shield unreadable, insufficient SD proportions, feet cropped | REJECTED |
| CHR001 Guardian v02 | PASS | Bust crop, shield absent, not an SD full-body asset | REJECTED |
| CHR008 Medic v01 | PASS | Diagnostic ring absent, insufficient SD proportions | REJECTED |
| CHR008 Medic v02 | PASS | Diagnostic ring absent, static and weak medic silhouette | REJECTED |

## Decision

R05 proved that the gender, adult-read, and attire prompt gates are functioning better than the rejected earlier runs. Text prompting alone did not preserve essential role geometry. R05 is therefore retained as QA evidence only and is not copied to the Godot asset import or Blender guide bridge.

The next revision must begin with project-authored role geometry and local ControlNet Canny guidance. A candidate may be promoted only after explicit visual confirmation of all policy gates plus full-body SD framing and the required shield or diagnostic-ring silhouette.
