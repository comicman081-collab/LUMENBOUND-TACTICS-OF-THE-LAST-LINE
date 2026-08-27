# Release HARD continuation plan — 2026-08-25

This is a QA execution note, not a gameplay override.

The isolated Release namespace `hard-release-cert-r15` currently has operation
power `5/124`. The authored stage costs are:

| Stage | Cost |
|---|---:|
| H02 | 12 |
| H03 | 12 |
| H04 | 13 |
| H05 | 13 |

The Web save uses the normal six-minute-per-point recovery rule. The remaining
Release evidence must therefore be performed in the same namespace only when
each entry cost is naturally available. No developer grant, save reset, direct
storage edit, or data/cost change is permitted.

Required evidence sequence:

1. Recover to 12, enter H02 through physical map contact, and record victory,
   reward exactly once, hostile removal, and H03 reveal.
2. Recover to 12, repeat the same physical-contact flow for H03; recover to 13
   for H04 and H05.
3. After H05, return to the map, reload the browser, Continue, and verify H02–H05
   remain cleared, no hostile pawns respawn, no reward/first-clear duplication
   occurs, and map/account/growth state is intact.

Until those observations are captured, Release H02→H05 and H05 reload remain
`UNVERIFIED`; automated tests and Development route coverage do not replace
this evidence.

## Latest actual checkpoint

- H02 was physically reached after the authored multi-pulse route and entered
  the unchanged real-time battle automatically.
- H02 defeat, reward-zero, hostile retention, exact pre-contact return, and
  reload recovery all passed in the same Release namespace.
- H02 is now at `3/3` attempts. `AppState` contains a local-date reset path,
  but the browser has not crossed a date boundary, so reset, H02 victory,
  H03–H05, and H05 reload remain `UNVERIFIED`.
- Do not reset the save, edit the date, use developer authority, or substitute
  Development evidence for Release certification.

## Map-capacity Web checkpoint (2026-08-25 15:54 KST)

An isolated Release `capacity-web-r15` sandbox loaded Title → Prologue →
Chapter 1 map from the current PCK and visibly showed `이동 7/7`, the 96-hex
long-distance terrain, squad pawn, and encounter marker. The temporary tab and
local server were closed immediately. GPT Web marked map entry, movement-cap
HUD, long-map rendering, and pulse/WAIT as PASS. Direct browser attribution of
VT03/HT03 route-module `+1/+1` remains UNVERIFIED and does not alter the HARD
recovery sequence above.
