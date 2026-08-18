# Local concept revisions 11–15

Date: 2026-08-17

## Fixed QA gates

- Human and humanoid characters: unmistakably adult women only
- Character shape: compact approximately three-head SD silhouette with oversized head and short rounded limbs
- Attire: `MAXIMUM_NON_EXPLICIT`, with opaque intimate coverage
- Equipment: one shield, physically connected to a readable hand/forearm grip
- Local models only; source models preserved read-only
- Krea2: prohibited and not loaded
- Integration: blocked until all gates pass

## R11 — text-only SDXL chibi reroll

All four candidates failed. The body ratios remained too tall or unstable; individual variants also introduced a watermark, duplicated shield, or cropped anatomy. No runtime integration was permitted.

## R12 — project-authored depth-controlled SDXL

The depth guide improved the SD ratio. Variant 03 came closest to the compact target but added a wing-like black cape, retained covered armor, and did not visibly connect the shield to a grip. Variant 04 preserved a clean silhouette but contained a generator mark, covered the torso and waist, and left the shield detached. All variants failed.

## R14 — broad costume and grip inpainting

Both candidates increased exposed skin while preserving the R12 shape, but neither met the requested maximum non-explicit costume contract because the abdomen remained covered by a bodysuit panel. The first grip repair did not reveal a handle. The second introduced an extra malformed arm-like shape behind the shield. Both records are marked `ART_QA_REJECTED` and `FAIL` in the manifest.

## R15 — narrow correction pass

R15 preserved the R14 face and compact body, but the source armor dominated the narrow edit. Variant 01 retained a teal bodysuit with only narrow skin cutouts; variant 02 restored a fully covered abdomen. The grip refinement erased the authored handle instead of producing a grasp. Both variants failed.

## R16 — color-structure-guided correction

Status: `IN_PROGRESS`.

R16 begins from a project-authored color topology inside the mask: a skin-colored torso, physically separate opaque bra and briefs, and a visible navel guide. The handle and palm are also explicitly drawn at the shield rim. Diffusion strength is reduced so the local model refines those structures instead of replacing them with another bodysuit or detached prop.

## Current verdict

No R11–R15 output is production approved or present in the runtime import tree. R16 must pass adult readability, exposure, SD proportion, equipment attachment, anatomy, text/watermark, and full-body framing checks before it can become a direction-selected candidate.
