# Local concept revisions 08–10

Date: 2026-08-17

## Scope and policy

- Human character: unmistakably adult woman only
- Attire: `MAXIMUM_NON_EXPLICIT`
- Runtime dependencies: none
- Local model roots: read-only
- Krea2: excluded and not loaded
- External APIs: none

## R08 — local SDXL + Depth ControlNet + IP-Adapter

Two full-body Guardian candidates were produced from a project-owned R05 appearance source and a project-authored depth guide. Both correctly avoided male and juvenile reads and showed the Guardian shield. They remain below the supplied reference quality: variant 1 overweights the shield and variant 2 has simplified materials and insufficient costume detail. Both are rejected for integration.

## R09 — project-authored Blender 4.5 color SD pilot

Blender 4.5 LTS generated a new full-color adult-woman Guardian, transparent master, QA render, manifest, and preserved `.blend` source. The silhouette, palette, shield, high-exposure opaque costume, and full-body framing are functional. Facial construction, hands, boots, and material detail remain too primitive for production. R09 is rejected for integration.

## R10 — Blender-to-local-SDXL img2img refinement

R09 was passed through approved local SDXL Base and non-FaceID IP-Adapter at low img2img strength. Two candidates were produced offline. The pass retained the Blender silhouette but did not sufficiently replace primitive face and limb construction. Both are rejected for integration.

## Verdict

Generation pipelines are operational, but no R08–R10 image is `PRODUCTION_APPROVED`. None is copied into the runtime import tree. The next art pass needs higher-quality authored Blender geometry/rigging and material work before diffusion refinement; lowering the QA gate is prohibited.
