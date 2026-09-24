# Map art and gameplay batch — IN PROGRESS

Historical checkpoint: the export/pending notes below predate candidate 10.
For the current build and actual verification, use `20260907_CURRENT_STATUS.md`
and `20260907_VERIFICATION_MANIFEST.json`. Candidates 15 and 19 have completed
real map gallery and N20/H01 route checks; full commercial art acceptance still
remains HOLD. This historical record is retained rather than rewritten as a PASS.

User's target: contemporary high-quality commercial-game presentation, not a
blank-field patch. No deployment. This target has NOT been declared achieved.

## Local tools/provenance

- Installed Blender 4.5.11 LTS used locally; no model weights or external API.
- Read-only inspection of existing project R11 kit (1.9 MB) completed.
- Project-authored canopy/trunk/rock kit built deterministically from Blender
  primitives with the source script under tools/blender. Candidate02 GLB is
  47,392 bytes, SHA256
  `8ed13bec8be252c7cf595be305043c384faca2a8b6c38d5afd2516269f9140e5`.
- Studio preview inspected: rounded layered foliage, tapered bark, rock group.
  This is a prototype/technical asset review, not commercial-quality acceptance.
- Runtime copy under godot/assets/art/chapter_map/R17 is attached for the next
  LOCAL candidate test only. In-game composition/GPU verification remains pending.
- Candidate01 preview script failed; full failed bundle/source/log/manifest is
  retained in work/map_polish_20260907/quarantine/candidate01_preview_failed.
  No retired files have been deleted.

## Current changes awaiting the next local export

- Stage-matched continuous moss ground + spatially culled background vegetation.
- World-anchored terrain detail and slow river current shaders, restrained range
  fill, smaller internal-ID-free stage badges; complete debug IDs stay in tooltips.
- Organic environment kit replaces primitive canopy/trunk/boulder family meshes
  without changing placement, collision or navigation authority.
- Map and battle loading use progress-aware 12 s idle / 45 s absolute watchdogs.
  The 5 s map target remains measured. Candidate08 exposed the old bug: active
  terrain build was aborted at 5.157 s and shown as RETRY. It is NOT a PASS build.
- N20 completion no longer routes back to cleared N01. The completion action
  selects pending HARD operations, or shows completed state.
- HUD face-crop memory accounting retained across wave changes; actor/effect
  atlases still release before acquiring the next wave.

## Passed evidence (different earlier candidates; do not mix with final acceptance)

- Map 350/350, environment 26/26, general + watchdog 271/271 before new art kit.
- 390x844 real Chrome touch: growth scroll 0→2117→0; level-up action refresh;
  WPN004→WPN010 equipment selection; reward scroll 0→1502.
- N05 actual battle→reward→3 dialogue pages→N06 route.
- N20 actual boss-wave HD actor/effects lease and victory→map, exposed N01 bug.
- Fresh twenty-stage service chain passed (not twenty manually played stages).
- Existing HD art remains partial/LOCAL_QA_ONLY; no blanket HD promotion.

Next: export with the watchdog and new geometry, inspect mobile/landscape map
screens, run final_route_audit.mjs against the final candidate, check errors and
frame timings, and continue refining map art if the rendered result is weak.
