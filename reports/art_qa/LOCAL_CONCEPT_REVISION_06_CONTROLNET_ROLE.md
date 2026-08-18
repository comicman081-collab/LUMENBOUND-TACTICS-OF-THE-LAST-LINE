# Local Concept Revision 06 — ControlNet Role QA

Date: 2026-08-17

## Scope

- Local SDXL Base 1.0 plus local ControlNet Canny
- Project-authored vector-line controls; no external reference art
- Source model directories were read-only and unchanged
- Krea2 was not loaded
- Outputs were never runtime or production assets

## Result

| Candidate | Female / adult / attire | Required role prop | Asset quality | Integration |
|---|---|---|---|---|
| CHR001 Guardian R06 | PASS | Octagonal shield PASS | Face, hands, materials, and SD readability FAIL | REJECTED |
| CHR008 Medic R06 | PASS | Diagnostic ring PASS | Face, anatomy, materials, and SD readability FAIL | REJECTED |

The strong full-frame Canny constraint made the required props visible, but it also forced the guide lines into seams and removed useful facial detail. Both candidates remain QA evidence only. They are not copied into `godot/assets/generated_import` and are not admitted to the Blender concept bridge.

## Next correction

Use a policy-passing, project-generated R05 source as the appearance anchor. Apply project-authored prop geometry with lower ControlNet strength and an early cutoff so the model retains face and material quality while correcting only the role silhouette.
