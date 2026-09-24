# Continuation history — final verified local candidate 33

Final update: candidate 33 is the visually reviewed replacement. Candidate 32's narrow-floor crowding was rejected; candidate 33 composites a continuous scene-matched foreground and preserves the same separated formation across normal/boss waves. Actual N20 recording and 360x640 / 390x844 / 1280x720 live rotation checks pass. General native 287/287 and full-density 109 actors / 436 FX / 109 map actors pass. The final isolated performance run and canonical report refresh are complete. CURRENT_STATUS.md and VERIFICATION_MANIFEST.json are authoritative; the following older entries are retained as implementation history, not pending work.

Latest user request: actors in the actual N20 recording float above the ground. Fix this together with all remaining gameplay QA; no deployment or deletion.

## Verified before current grounding revision

- Candidate 29: Web shader preparation 7,951.20 ms versus candidate 27 about 20.9 seconds. This is not total download/startup time.
- Candidate 29 actual browser route: 20 stages / 45 waves / 3,453 checks PASS, including N20 → H01. Isolated invincible neighbor fixtures; not a balance playthrough or physical phone.
- Candidate 30 intentional HD HTTP 503 failure and next-stage recovery PASS.
- Candidate 31: map gallery 19 PASS, actual N20 motion recording 4 PASS, audio signal continuity 8 PASS, final N20/H01/rotation/suspend route 223 PASS.
- Candidate 31 map R19 round foliage visually inspected; rejected spiky R18 is retained in quarantine.
- Candidate 31 recording still exposed action-dependent body scaling and ground misregistration. It is NOT visually accepted as the completed combat result.
- No audio/model/source images were altered. Runtime matte corrections from earlier batches remain intact.

## Current candidate 32 grounding implementation

- Reproduced scale regression first: 285 checks / 284 PASS / 1 FAIL in `20260907_scale_pop_before.log`.
- Fixed physical body scale independently of which density/action pack is resident.
- Added read-only per-frame alpha contact registry for 109 compact actors, 109 HD actors, 8 signature actors — 18,528 frames; PNGs unchanged.
- Registered posed silhouette to ground after mirroring/rotation/squash; body, HP bars and contact shadows now share one transform.
- Moved formations onto the actual floor portions of each backdrop; no ground diagonal crosses the cathedral moat.
- Removed vertical entry hop and additive hit bob; grounded shadows rendered before depth-sorted bodies.
- Native regression `20260907_ground32_native.log`: 287/287 PASS, including all contact frames with both facings and three lean angles.
- Candidate 32 export and actual browser visual/motion/ground-contact acceptance are still in progress. Do not call this complete without seeing the final screenshots/video.

## Retention / gates

No deployment, Actions, push, commit or deletion. R18 and slow candidate 28 remain hash-preserved quarantine. Failed initial OpenCV reference/motion duration reports and candidate 31 build/recording have been moved to `work/gameplay_qa_quarantine_20260907/grounding_predecessors` with before/after hash verification. Candidate 32 build/recording is retained in `grounding_candidate32` beneath the same quarantine root.

Canonical status/verification manifest still need final refresh from candidate 27 after candidate 32 visual acceptance. Physical phone, external ChatGPT review and commercial-reference joint-animation parity have NOT been established. Current work uses local deterministic analysis/code/Blender geometry only, not newly generated AI art.
