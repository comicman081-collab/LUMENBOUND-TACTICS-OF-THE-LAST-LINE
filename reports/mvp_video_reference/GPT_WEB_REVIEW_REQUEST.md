# GPT Web review request — current MVP checkpoint

Please review the current independent Godot Web RPG MVP against the following evidence. Do not infer a production approval from the evidence alone; identify concrete visual, UX, or state-consistency defects first.

## Scope under review

- Long Chapter 1 SRPG exploration map with bounded movement pulses.
- Event companion MapPawn → automatic unchanged realtime SD battle → result/recruitment → map return.
- A pre-battle companion contact card states whether a victory grants an
  immediate formation join or a deferred signal follow-up; it remains visible
  for 1.85 seconds before the ordinary realtime battle transition.
- Story hierarchy: narration is intentionally larger than navigation buttons while button touch targets remain large.
- No external game art, assets, or UI are used.

## Current verified facts

- Godot 4.7.1 Compatibility Web release rebuilt in place.
- Latest local Release artifact: `builds/web_release/index.pck`, 62,791,336
  bytes, SHA-256 `148efe50fd4327b97de86b921cfe156b41626eb323ce9369c4191614053194e1`.
- Core/static/map/R15/R16 suites: 559 / 559 PASS (165 + 70 + 249 + 49 + 26).
- The current Chapter 1 deterministic balance matrix was rerun from its
  checkpoint: 90 cells × 200 seeds = 18,000 BattleSimulation runs. Its stated
  target audit is 13 PASS / 0 FAIL / 0 UNVERIFIED, including N10 and H05
  AUTO/manual target rows. This is simulation evidence only, not a substitute
  for the intentionally separate stamina-gated physical Release HARD E2E.
- The rebuilt package now uses the full user-supplied title BGM rather than a
  30-second excerpt; lobby, story, battle, and boss BGM retain their full
  approximately 89.94-second runtime streams. The existing two-player
  1.8-second loop crossfade is unchanged. This is a technical packaging and
  playback-path result, not a human listening/mix approval.
- Development and genuine fresh-save Release N04 event E2E: companion event MapPawn → battle → victory/recruitment → direct map return → refresh recovery; browser console error/warning: 0 / 0.
- The companion-contact card was visually inspected through the
  development-only N04 physical-contact fixture. The equivalent Release code
  was rebuilt in place and passed a fresh title → home → map smoke. Do not
  treat this particular card inspection as a new full Release N04 claim.
- Release Web Title → Home → Story works in desktop and 390×844 portrait, browser console error/warning: 0 / 0.
- The Release N04 run used no development unlocks or fixture; it progressed Prologue → N01 → N02 → N03 → N04 under normal movement-pulse and wait rules.
- The Chapter outro now displays a packaged 1280×720 runtime CG derivative in the actual Release; original authoring art remains outside the Web PCK.
- Current Release HARD E2E: H01 physical map contact → realtime battle victory → H02 unlock. H02 route stopped when its movement pulse reached 0/7, **대기** restored 7/7, contact entered the same realtime battle, defeat granted no reward, map return preserved the hostile, and browser refresh restored the exact returned state. Browser warning/error: 0 / 0.
- A newer isolated fresh Release session completed Prologue → N01…N10 without development unlocks. It included N04 immediate companion contact/recruitment, N08 companion contact → N09 deferred recruitment, actual shared-material recommended growth, N10 storm/boss victory (`46.03s`), chapter-outro CG, browser reload, and persisted HARD availability. The same session recorded H01 AUTO defeat before legal growth, H01 AUTO victory after legal growth, and H02 AUTO defeat; this is not claimed as a completed H01→H05 route or a balance-certification sample.
- A further H02 physical-contact retry in the isolated Release session at the
  same natural Lv.21 growth state again ended in AUTO defeat at `19.83s` with
  no reward. This is retained as real below-recommended retry evidence, not
  as a reason to alter the data-authoritative balance matrix.
- The stable public Web URL now fingerprints its final PCK/WASM/JS/HTML cache
  inputs, performs network-first navigation, and retains an offline fallback.
  A previously installed obsolete LANTERNLINE-only PWA cache was not deleted.
  The latest rebuilt URL loaded the Godot canvas with 0/0 console errors, but a
  full fresh visual pass after cache removal still needs explicit confirmation.
- The rebuilt Release booted through trusted Title → Home input in a single
  temporary QA tab; it and port 8078 were closed after the check.
- The latest isolated QA pass also completed the current PCK's physical
  N01 loop: Chapter 1 intro → map → route preview → movement pulse exhaustion
  at 0/7 → WAIT refill to 7/7 → physical contact → realtime SD battle →
  victory at 15.47s with five survivors → per-item before/after reward result
  → map return/N02 unlock → full browser refresh/recovery. The console had
  0 errors and 0 warnings. After the trusted gesture, the 89.94-second local
  BGM was in verified streaming playback with no failed start.
- A full canonical `N01…N10 → H01…H05` service-level transaction/reload
  regression passes with development authority disabled. It proves one-shot
  result/reward/node/recruitment handling and reload restoration, but does not
  replace the remaining physical browser H03–H05 E2E evidence.

## Evidence files

- `reports/mvp_video_reference/01_N04_COMPANION_EVENT_MAP_WEB.png`
- `reports/mvp_video_reference/02_N04_SPECIAL_CONTACT_BATTLE_WEB.png`
- `reports/mvp_video_reference/08_N04_COMPANION_RESULT_ART_WEB.png`
- `reports/mvp_video_reference/07_N04_DIRECT_MAP_RETURN_WEB.png`
- `reports/mvp_video_reference/09_RELEASE_N04_COMPANION_SELECTED_WEB.png`
- `reports/mvp_video_reference/10_RELEASE_N04_SPECIAL_SIGNAL_WEB.png`
- `reports/mvp_video_reference/11_RELEASE_N04_RECRUIT_RESULT_WEB.png`
- `reports/mvp_video_reference/12_RELEASE_N04_DIRECT_MAP_RETURN_WEB.png`
- `reports/mvp_video_reference/13_RELEASE_N04_RELOAD_RESTORED_WEB.png`
- `reports/r16_environment/38_RELEASE_STORY_TYPOGRAPHY_WEB.png`
- `reports/r16_environment/39_RELEASE_STORY_TYPOGRAPHY_PORTRAIT_WEB.png`
- `reports/r16_environment/112_RELEASE_CH01_OUTRO_CG_RUNTIME_WEB.png`
- `reports/mvp_video_reference/113_RELEASE_HARD_ROUTE_STATE_CURRENT_WEB.png`
- `reports/mvp_video_reference/114_RELEASE_H01_VICTORY_CURRENT_WEB.png`
- `reports/mvp_video_reference/115_RELEASE_H02_DEFEAT_CURRENT_WEB.png`
- `reports/mvp_video_reference/116_RELEASE_H02_DEFEAT_RETURN_CURRENT_WEB.png`
- `reports/mvp_video_reference/117_RELEASE_H02_DEFEAT_RELOAD_CURRENT_WEB.png`
- `reports/mvp_video_reference/EVENT_COMPANION_FLOW_UPDATE.md`

## Requested review output

1. List only reproducible, evidence-grounded defects, grouped P0/P1/P2.
2. Separate confirmed defects from uncertain visual preferences.
3. Confirm whether the companion event progression is understandable without reading developer/debug labels.
4. Evaluate whether the story type hierarchy is readable in desktop and portrait screenshots.
5. Evaluate whether the movement-pulse exhaustion → wait → resumed physical
   traversal is understandable without debug labels.
6. Suggest the smallest next corrective task, without adding a new game system.
7. Based on the companion event evidence, suggest up to three short,
   independent Chapter-1 event beats that could make the immediate-versus-
   deferred recruitment distinction clearer without adding a new progression
   currency, external IP, or a new combat system.
8. Identify whether there is a specific evidence-grounded P0/P1 defect that
   warrants code work before the intentionally separate, stamina-gated normal
   Release H02→H05 long-run evidence can be collected.
