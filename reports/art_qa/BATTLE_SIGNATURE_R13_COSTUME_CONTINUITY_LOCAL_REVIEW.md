# Battle Signature R13 / Effect R4 — CHR004 Costume Continuity Local Review

Status: **LOCAL_QA_PASS · PROMOTION HOLD**  
Reviewed: 2026-09-05 (Asia/Seoul)  
Scope: CHR004 Eda only. This records a local runtime-candidate review; it does
not grant production approval, public-export authority, or permission to
replace the existing identity authority.

## Immutable identity authority

| Candidate | Canonical authority | Immutable source manifest SHA-256 | Local visual result |
| --- | --- | --- | --- |
| CHR004 Eda | `docs/art/identity/CHR004_CANONICAL_IDENTITY_R1.md` | `521c8f2b29a56659f5d62e6e7ff0bfe2c5e117fd01a2cdbd8e37e70c7799fec0` | Pass: adult mobile assault read, deep-violet high side ponytail, amethyst eyes, black/violet tactical armor, restrained magenta seams, and compact angular energy-carbine two-hand grip remain distinct from CHR002's greatsword weight and CHR003's long-rifle stance. |

The R13 actor candidate is a deterministic 512px-source-to-384px,
alpha-tight-atlas derivative only. It does not change the source rig, costume,
weapon class, adult classification, player-facing orientation, foot anchor
`(0.5, 0.88)`, head anchor `(0.5, 0.064453125)`, or the compact 128px fallback.
Its narrowed state selection preserves four idle, twelve ultimate, four hit,
and eight down frames for real anticipation, contact, recoil, and recovery
without stretching a card or thumbnail.

## Green-master and RGBA evidence

- Retained green-master/keyed derivative manifest:
  `godot/assets/generated_import/chroma_key_derivatives/battle_signature_r13/CHR004/chroma_key_derivative_manifest.json`
  (`55182d6a7a034c8669a1d26e60b1a54196d547dbc0426eb974e4f128dfdc5b1c`).
- The master is opaque uniform `#00FF00`; it is provenance only. Runtime atlas
  frames use the separate keyed RGBA branch and the source is not modified.
- Dual-backdrop evidence:
  `reports/art_qa/BATTLE_SIGNATURE_HD_R13_CHR004_CHROMA_KEY_QA.png`.
  The 28-source-frame dark/light check shows no opaque rectangular background,
  no visible green halo, and preserved fine hair, hand, carbine, and magenta
  energy-edge detail.
- The keyed alpha cleanup reduced exterior near-white rim detections from
  28,283 to 459; the remaining pixels are isolated intended highlight/weapon
  edges, not a background plate. Visual review on both backdrops is the
  deciding evidence.

## Runtime candidate evidence

- Actor manifest:
  `godot/assets/runtime_web/combat_signature/r13/CHR004/signature_manifest.json`
  (`698ce372f6f0df4e8179686a81b02b7bb2f57d910e819638056b3c764210f3dc`).
- Effect manifest:
  `godot/assets/runtime_web/effect_signature/r4/CHR004/effect_signature_manifest.json`
  (`35ade67fc86c86b60a9494018b404bf65f0a823e4b5619a95af2daf7f3b5a6e4`).
- R13 actor group: CHR001/CHR002/CHR003/**CHR004**/CHR005/CHR008/BOSS001/ENM001.
  Core idle/hit/down residency is 58,421,248 bytes; core plus the largest
  one-caster ultimate page peaks at 67,166,208 bytes, below the 75,497,472-byte
  mobile ceiling.
- R4 effect group has 6,704,096-byte projectile core and 8,662,688-byte
  core-plus-one-ultimate peak, below the 12,582,912-byte mobile ceiling.
- Contact sheets:
  `reports/art_qa/BATTLE_SIGNATURE_HD_R13_CONTACT_SHEET.png` and
  `reports/art_qa/BATTLE_EFFECT_SIGNATURE_R4_CONTACT_SHEET.png`.

## Gates intentionally held

1. `CHR004_CANONICAL_IDENTITY_R1.md` still says
   `PRODUCTION_APPROVED = WAITING_USER_APPROVAL`; this review does not override it.
2. R13/R4 remain `LOCAL_QA_ONLY`. They require real 390×844 runtime capture,
   full technical regression, and the existing ChatGPT web Sol Pro review
   before any promotion decision.
3. No public export, deployment, GitHub Action, or deletion of a quarantined
   candidate is authorized by this review.
