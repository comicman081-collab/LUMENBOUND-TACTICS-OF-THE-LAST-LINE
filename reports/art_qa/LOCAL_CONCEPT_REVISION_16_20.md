# Local concept revisions 16–20

Date: 2026-08-17

## Fixed gates

- Adult woman only; no male or juvenile character generation
- `MAXIMUM_NON_EXPLICIT` attire with opaque intimate coverage
- Compact approximately three-head SD silhouette
- One shield physically connected to the left hand/forearm
- No text, watermark, duplicate equipment, or malformed extra anatomy
- Local approved models only; Krea2 prohibited; source models preserved read-only

## R16 — color-topology correction

The authored skin/top/bottom structure finally forced a genuinely separated minimal costume. Variant 02 passed the exposure, compact silhouette, and flat-torso direction checks. It failed equipment attachment because the grip refinement removed the handle and left the shield detached.

## R17 — narrow waist and visible-finger correction

The waist became slimmer and the hand overlapped the shield rim. Both candidates failed because the generated briefs became either a black rectangular panel or shorts with hanging panels. Finger shapes also read as mechanical bars.

## R18 — briefs and organic-finger micro pass

Variant 02 established the best costume topology: opaque minimal briefs with bare abdomen, side waist, hips, and upper thighs. The glove overlapped the rim and connected to the forearm, solving the detached-shield structure, but its segmented fingers remained visibly synthetic. It was retained only as a direction source.

## R19 — low-denoise Canny polish

The R18 silhouette was locked with the approved local Canny ControlNet and refined at low denoise strength. Variant 01 introduced faint text-like background artifacts and failed. Variant 02 improved material polish and retained the correct exposure and proportions, but still preserved the segmented glove; it was retained as the source for R20.

## R20 — gauntlet-only micro pass

Variant 01 replaced the finger ladder with a single compact gauntlet that overlaps the shield rim and connects to the left forearm. It passes the user's three immediate structural corrections: exposure, reference-like compact SD proportion, and non-floating shield. It is marked `ART_QA_REVIEW_CANDIDATE`, not production approved, because the circular gauntlet inset and overall surface fidelity still need authored cleanup. Variant 02 detached the gauntlet again and failed.

## Current candidate

`work/art_gen/sdxl_chibi_guardian_r20/chr001_maeru_guardian_chibi_r20v01_seed171251.png`

The current candidate is intentionally not copied into the runtime asset tree. User/art-director review and a transparent-background production derivation remain required before integration.
