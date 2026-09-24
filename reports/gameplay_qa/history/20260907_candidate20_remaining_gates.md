# Remaining gates — not an all-work-complete report

The mobile blocking-dialog work is a batch within the continuing game QA/art
task. It does not authorize deployment or disposal of rejected assets.

## Cold start / actual phone performance

Candidate 19's isolated N20 browser audit recorded 20,440.3 ms maximum boot
frame gap, with four gaps >= 1 second. After entering gameplay, no >= 1 second
gaps were recorded in combat, rewards, map return or steady map phases. Combat
still had a worst full-window p95 of 40 ms and a maximum gap of 160 ms; the
reward phase max was 190 ms. These figures include the local QA probe and are
not a physical-phone 60 fps certification.

The existing boot warmup still builds StandardMaterial terrain/prop variants
in `godot/autoload/web_soak_probe.gd`, while the new map dressing uses custom
terrain/environment shaders. This is a candidate cause of additional first-map
pipeline compiles, not a proven fix. A future optimization must compare cold
and warm startup separately and must not merely move an unmeasured freeze into
boot or increase the watchdog timeout again.

Actual Android/iOS GPU memory, thermal behavior, touch browser chrome and audio
playback remain untested. Browser tests used fresh localhost profiles and muted
audio; the browser's pre-gesture AudioContext warning is recorded separately.

## Complete art coverage / commercial-quality acceptance

The new map uses project-authored Blender geometry and shader changes, and the
continuous backdrop, bridge winding and real blocked-water checks have passed
local visual/runtime tests. Contemporary high-end commercial-game parity has
not passed visual acceptance. This is still a stylized environment revision.

R13 actor and R4 FX signatures remain partial and LOCAL_QA_ONLY. Move/basic/
normal attack states, several enemy families and the map pawn still have compact
fallbacks. All-actor/all-FX HD coverage must not be inferred from the boss or
five tested party-member leases. Original green masters, licensing/provenance,
failed candidates and promotion gates must be respected in further art work.

## Evidence boundary

20 maps / 80 map contacts / 960 Korean-English localization references passed
static data checks. Real browser combat coverage in this batch is representative
first-chapter routes, not manual playthroughs of all 20 chapters. Current report
and verification manifest identify the exact tested builds and stage fixtures.

No external ChatGPT web review, deployment, GitHub Actions run or quarantine
disposal took place in this batch. Do not promote a partial local PASS to global
production approval.
