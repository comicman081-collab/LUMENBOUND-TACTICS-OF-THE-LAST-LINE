# R6 GPT Web Remediation Specification

Source: persistent collaboration session in the Codex in-app browser at
`https://chatgpt.com/c/6a83bf83-2c00-83ee-ade9-8ec3e31d58ac`.

This document records the actionable review contract received from ChatGPT Web.
It does not grant production approval and does not replace visual inspection.

## UI tokens

- Backgrounds: `#080B12`, `#0E1320`, `#151C2B`, `#1B2536`, glass `#101827E8`.
- Primary accent: `#78E6D0`; hover `#9AF0DE`; secondary `#A8B7FF`; gold `#E9C979`.
- Text: `#F4F7FB`, `#CDD5E3`, `#8E9AAF`, `#596578`.
- State: success `#68DCA0`, warning `#F1C66A`, danger `#F07886`.
- Borders: `#FFFFFF18` and `#FFFFFF30`; focus `#78E6D0CC`.
- Shadow `#00000066`; scrim `#05070BCC`; radii `6/10/16/24`.
- Preserve existing clickable node geometry. Apply visual changes through Theme
  and StyleBox resources so the verified interaction flow is not displaced.

## SD animation

- Retain the exact 80-frame runtime contract and existing state ranges.
- Use planted-foot deformation, authored key poses, upper-body/hair secondary
  motion, and explicit muzzle/projectile events.
- Foot drift acceptance: at most 1.5 px. Projectile spawn discrepancy: at most
  2 px from the declared muzzle anchor.
- Never hide a bad transition behind an opaque or black material fade.

## VFX timing

- Every effect retains 12 frames with anticipation, peak, impact and recovery.
- Basic: 0.40 seconds, visual peak frame 3.
- Normal: 0.52 seconds, visual peak frame 4.
- Ultimate: 0.72 seconds, visual peak frame 5.
- Impact effects render at the target anchor and remain readable at 1x and 3x.

## Web gates

- Exclude unused QA, legacy placeholder and duplicate runtime assets from export.
- Preserve source and review assets outside the Web runtime package.
- Web ZIP hard limit: 300,000,000 bytes.
- Show a non-interactive orientation gate in portrait or below 844x390.
- Run a real 20-minute browser soak with samples every five seconds.
- Required gates: illustration >=88, SD >=88, VFX >=85, UI >=85, package under
  300 MB, responsive QA, soak QA, baseline 147 tests and art 15 tests.

## Evidence rule

Automated technical checks cannot award visual PASS. Contact sheets, real Web
captures and runtime motion must be inspected. User approval remains
`WAITING_USER_APPROVAL` even after all technical gates pass.
