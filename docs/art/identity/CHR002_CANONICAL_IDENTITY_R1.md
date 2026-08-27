# CHR002 — Roan (DEV) Canonical Identity R1

## Authority and scope

This sheet freezes the authored identity already visible in the runtime
`CHR002_card_384x576.png` and `runtime_web/combat/CHR002/atlas.png` before
static illustration work begins. It does not redesign the character. All
full-body, portrait, icon, and future expression renders must be recognisable
as this same adult female vanguard when shown alongside the existing combat
SD pack.

## Immutable identity cues

| Category | Canonical cue |
| --- | --- |
| Role / weapon | Front-line VANGUARD; oversized crimson-and-silver greatsword held with both hands. |
| Gender / age | Adult woman only; non-explicit combat presentation. |
| Hair | Coral-red hair, dense swept fringe, high side ponytail flowing to the left. |
| Face | Warm amber-gold eyes, focused/confident expression, compact angular anime face. |
| Ornament | Small angular black-and-silver mechanical hair ornament with a red inset. |
| Costume silhouette | Charcoal/black fitted tactical bodice, deep crimson split coat/skirt panels, segmented silver armor bracers and greaves. |
| Accent language | Triangular red crystal/inset details, controlled silver bevels, not gold or blue ornamentation. |
| Body / stance | Athletic adult build, agile forward combat weight, not a childlike body or a generic heavy knight. |
| Palette | Primary: coral red / charcoal. Secondary: deep crimson / silver. Accent: amber eyes / red crystal. |
| SD continuity | The existing 30-degree lower-right combat view and separate-left-right policy remain unchanged. |

## Forbidden identity drift

- Blonde, blue, purple, or black replacement hair; a short bob replacing the side ponytail; or a missing mechanical ornament.
- A firearm, staff, shield, or thin rapier replacing the broad greatsword.
- A blue/white healer palette or a generic uniform that erases the black/crimson/silver armor layering.
- Childlike proportions, male presentation, nudity, or explicit content.
- Reusing the combat atlas as a portrait/icon or treating a raw transparent cutout as final static art.

## R1 static-art derivation

The source is a locally generated, original CHR002 illustration with a
uniform chroma background. Blender produces the alpha-bearing runtime outputs
from that source so the same canonical identity feeds:

1. `CHR002_ILLUSTRATION` — full body,
2. `CHR002_PORTRAIT` — portrait framing,
3. `CHR002_ICON` — face-first square crop.

The ImageGen source and Blender source file are authoring-only and are not
Web runtime assets. The runtime manifest must retain the existing immutable
character and asset IDs while replacing only their file paths after technical
and visual QA.

## R1 review status

- Identity source: **READY FOR BLENDER ALPHA RENDER**
- Runtime mapping: **NOT CHANGED**
- Production approval: **WAITING_USER_APPROVAL**
