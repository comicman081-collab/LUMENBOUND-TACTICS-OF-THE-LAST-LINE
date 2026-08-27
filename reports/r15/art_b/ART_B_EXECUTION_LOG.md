# R15 Art B — Static Character Completion

## Gate order

1. Canonical identity sheet.
2. Blender alpha-bearing render derived from the same identity source.
3. Runtime manifest integration without changing gameplay IDs.
4. Asset technical checks and actual Web UI smoke.
5. Contact-sheet and identity review before moving to the next character.

## CHR002 R1

- Existing runtime authority inspected: `CHR002_card_384x576.png` and the
  complete 80-frame `runtime_web/combat/CHR002` pack.
- Identity document: `docs/art/identity/CHR002_CANONICAL_IDENTITY_R1.md`.
- First ImageGen output was rejected before integration because it was an
  RGB checkerboard image, not a transparent alpha file.
- Current source is an ImageGen output with a uniform chroma background, kept
  as authoring input under the project asset factory. It will be converted by
  the project Blender pipeline into alpha-bearing PNG outputs.
- No runtime manifest, gameplay data, battle animation, or save ID has been
  altered at this point.

## Status

`CHR002_STATIC_ART_R1: TECHNICAL_PASS / VISUAL_REVIEW_PENDING`

## CHR002 R1 Blender reproducibility

- Blender binary: `C:\Program Files\Blender Foundation\Blender 4.5\blender.exe`
- Blender version: `4.5.11 LTS`
- Source blend: `D:\AI 종합 폴더\Games\asset_share\blender_sources\characters\CHR002\CHR002_STATIC_ART_R1.blend`
- Headless script: `asset_share/blender_sources/characters/CHR002/scripts/build_chr002_static_art.py`
- Authoring input: `CHR002_IMAGEGEN_R1_CHROMA.png`; it is preserved unmodified.
- Render outputs: 2048×3072 master, 1024×1536 portrait and 512×512 icon,
  each verified as `Format32bppArgb` with transparent corner pixels and opaque
  character pixels.
- Iteration notes: the first alpha buffer save was opaque, then a UV-less
  camera plane rendered black. The final headless camera render uses an
  explicit UV plane, Blender Chroma Matte, and a one-pixel alpha cleanup.
- Runtime IDs are unchanged. Only `portrait_chr002_dev` and `icon_chr002_dev`
  now resolve to the R1 PNG paths. No gameplay, battle, map, save, or growth
  data changed.

## Web delivery correction and runtime smoke

- Root cause found during actual Web inspection: the Web export excluded the
  whole `assets/art/characters` branch. The manifest therefore named CHR002 R1
  while its texture was absent from the PCK.
- The export now includes CHR002's delivery images while retaining exclusions
  for source-size master art and unrelated character source branches.
- The transparent PNG contracts remain the canonical master, portrait and icon
  outputs. A separate Blender-composited navy-backplate `RUNTIME` portrait and
  icon are the Web Compatibility Renderer delivery derivatives; this avoids
  the observed straight-alpha sampling failure without changing the authored
  art or using runtime chroma keying.
- Actual local Web smoke passed in both Character Detail and Party Formation:
  CHR002's red-haired vanguard portrait and icon are visible; no fallback card
  is used for either stable asset ID.
- Godot headless suite after import: `98/98 PASS`, including the stricter
  CHR002 R1 resolution assertion. The test count increased by one; no prior
  assertion was removed or weakened.
- Contact sheet:
  `reports/r15/art_b/contact_sheets/CHR002_STATIC_ART_R1_CONTACT_SHEET.png`.

## Pending gate

- GPT visual review for identity, crop, alpha edge, and UI legibility.
- The asset remains `ART_QA_CANDIDATE`; it is not production-approved and is
  not counted as final Chapter 1 asset completion.

## CHR002 R2 — reviewed runtime contract

- The initial opaque Web derivative was retained as an authoring-only
  compatibility derivative after an actual fresh Web test proved that Blender's
  transparent PNG output loads correctly through the current Compatibility
  Renderer export. It is no longer mapped to either stable runtime ID and is
  excluded from the Web PCK.
- Shared runtime art framing is now a dark `PanelContainer` card frame owned
  by `screens/app_shell.gd`, rather than a character-specific image matte.
  The Character Detail art box increased from the former 250×310 presentation
  to 282×350, approximately twelve percent larger, without clipping the
  character.
- Actual fresh Web R2 checks covered Character Detail and Party Formation.
  The previous blue temporary-card impression, alpha fringe, and special-case
  icon treatment are absent.
- GPT in-app pixel review: `TECHNICAL_PASS=YES`, `VISUAL_PASS=YES`,
  `REFERENCE_PARITY_PASS=YES`, `P0=NONE`. It also recorded no obvious direct
  external-game asset or character-design trace from the reviewed pixels.
- `CHR002` master art and identity are frozen as the static-art pilot contract;
  `PRODUCTION_APPROVED` remains `WAITING_USER_APPROVAL`.

## CHR003 R1 — implementation in progress

- Canonical identity: adult female `ASSAULT / MIDDLE / PHYSICAL / ARMOR /
  RIFLE`, silver-blue high side ponytail, teal eyes, black/white/cobalt
  precision-rifle equipment. Source: `docs/art/identity/CHR003_CANONICAL_IDENTITY_R1.md`.
- Authoring input is preserved at
  `asset_share/blender_sources/characters/CHR003/textures/CHR003_IMAGEGEN_R1_CHROMA.png`
  (`SHA-256 B131A8D3F0E4A5BFCE63A1B202AE37EA6CEE71CEA7BA0A7369BC889396BB8E2E`).
- Blender 4.5.11 LTS headless render created the retained source blend,
  transparent master (2048×3072), portrait (1024×1536), and icon (512×512).
  Their Godot copies and an immutable output manifest live under
  `godot/assets/art/characters/CHR003/`.
- Runtime stable IDs now map only to the transparent portrait/icon and use the
  frozen CHR002 shared frame. The master and unused opaque compatibility
  derivatives are excluded from the Web PCK.
- Technical regression after Godot import: headless `99/99 PASS`; R15 content
  suite `31/31 PASS`. Actual Web Character Detail and Party Formation screens
  show the CHR003 art without fallback.
- Contact sheet:
  `reports/r15/art_b/contact_sheets/CHR003_STATIC_ART_R1_CONTACT_SHEET.png`.
- GPT pixel review: `TECHNICAL_PASS=YES`, `VISUAL_PASS=YES`,
  `REFERENCE_PARITY_PASS=YES`, identity continuity and head-authority ±5%
  `PASS`, hard failure `NONE`. It found no obvious direct external-game asset
  or character-design trace in the reviewed pixels. The only note was an
  optional future 2–4% faceward icon crop for a smaller 64px-only UI; it is
  not required for the current contract.
- `CHR003` is frozen at R1 under the same shared card-frame contract as
  CHR002; `PRODUCTION_APPROVED` remains `WAITING_USER_APPROVAL`.

## CHR004 R1 — approved pilot-contract instance

- Canonical identity and source provenance:
  `docs/art/identity/CHR004_CANONICAL_IDENTITY_R1.md` and
  `asset_share/blender_sources/characters/CHR004/CHR004_STATIC_ART_R1.blend`.
- Blender 4.5.11 LTS headless camera render supplies the 2048×3072 master,
  1024×1536 transparent portrait, and 512×512 transparent icon. Stable
  runtime IDs map to the transparent output on the same shared card frame.
- Technical suites after integration: headless `100/100 PASS`; R15 content
  suite `31/31 PASS`. Actual Web Detail and Formation both rendered without
  fallback.
- GPT in-app pixel review: `TECHNICAL_PASS=YES`, `VISUAL_PASS=YES`,
  `REFERENCE_PARITY_PASS=YES`, no hard failure and no obvious external
  direct-copy indicator. Optional P1: the dark violet design has slightly
  lower contrast on the dark formation card; no R2 or master-art change is
  required.
- `CHR004` R1 is frozen. `PRODUCTION_APPROVED=WAITING_USER_APPROVAL`.

## CHR005 R1 — approved pilot-contract instance

- Canonical identity and source provenance:
  `docs/art/identity/CHR005_CANONICAL_IDENTITY_R1.md` and
  `asset_share/blender_sources/characters/CHR005/CHR005_STATIC_ART_R1.blend`.
- Blender 4.5.11 LTS headless camera render supplies the 2048×3072 master,
  1024×1536 transparent portrait, and 512×512 transparent icon. Stable
  runtime IDs resolve only to the transparent portrait/icon on the frozen
  shared card frame. The master and opaque authoring derivatives are excluded
  from the Web PCK.
- Technical regression after Godot import: headless `101/101 PASS`; R15
  content suite `31/31 PASS`. A fresh local Web release rendered CHR005 in
  Character Detail and Party Formation without fallback.
- Contact sheet:
  `reports/r15/art_b/contact_sheets/CHR005_STATIC_ART_R1_CONTACT_SHEET.png`.
- GPT in-app pixel review: `TECHNICAL_PASS=YES`, `VISUAL_PASS=YES`,
  `REFERENCE_PARITY_PASS=YES`, identity continuity and head-authority ±5%
  `PASS`, hard failure `NONE`. It found no obvious direct external-game asset
  or character-design trace in the reviewed pixels. Optional P1: a future
  tiny-icon derivative may bias the crop 2–3% toward the face at sizes below
  the current 64–96px formation contract; no R2 is required.
- `CHR005` R1 is frozen. `PRODUCTION_APPROVED=WAITING_USER_APPROVAL`.

## CHR006 R1 — reviewed pilot-contract instance

- Canonical identity and retained Blender provenance:
  `docs/art/identity/CHR006_CANONICAL_IDENTITY_R1.md` and
  `asset_share/blender_sources/characters/CHR006/CHR006_STATIC_ART_R1.blend`.
  The source character is an adult female `SPECIALIST / MIDDLE / ENERGY / WARD /
  FOCUS`; the identity contract uses an asymmetric frost-silver braid, teal eyes,
  ivory/navy navigator mantle, and a suspended cyan relay prism.
- Blender 4.5.11 LTS headless camera render produced a transparent 2048×3072
  master, 1024×1536 portrait, and 512×512 icon. Stable runtime IDs map only to
  the transparent portrait/icon under the frozen shared dark card frame; opaque
  compatibility derivatives remain authoring-only and excluded from the Web PCK.
- Technical regressions after import: headless `102/102 PASS`; R15 content
  suite `31/31 PASS`. A fresh local Web build rendered the asset in read-only
  Character Detail and the Party Formation candidate grid with no fallback.
- Contact sheet:
  `reports/r15/art_b/contact_sheets/CHR006_STATIC_ART_R1_CONTACT_SHEET.png`.
- GPT in-app pixel review: `TECHNICAL_PASS=YES`, `VISUAL_PASS=YES`,
  `REFERENCE_PARITY_PASS=YES`, identity continuity and head-authority ±5%
  `PASS`, hard failure `NONE`. It found no obvious direct external-game asset
  or character-design trace in the reviewed pixels; that is a visual review,
  not a legal provenance certification. Its only P1 note was that the slender
  specialist silhouette is intentionally lighter than weapon-focused units; no
  change is required for the current contract.
- `CHR006` R1 is frozen. `PRODUCTION_APPROVED=WAITING_USER_APPROVAL`.

## CHR007 R1 — reviewed pilot-contract instance

- Canonical identity and retained Blender provenance:
  `docs/art/identity/CHR007_CANONICAL_IDENTITY_R1.md` and
  `asset_share/blender_sources/characters/CHR007/CHR007_STATIC_ART_R1.blend`.
  The source character is an adult female `SPECIALIST / BACK / ANOMALY /
  BARRIER / SUPPORT_DEVICE`, designed around ink-violet layered hair, warm
  amber eyes, an indigo/ivory signal mantle, a distinct amber relay astrolabe,
  and a compact signal folio.
- The initial camera render exposed a partial green chroma veil in actual
  pixel inspection. The input was retained, while the Blender material was
  corrected to render the pre-keyed image's straight alpha rather than use a
  partial compositor key. The regenerated transparent 2048×3072 master,
  1024×1536 portrait, and 512×512 icon are the R1 source outputs; the old
  partial-matte output was overwritten before any Godot runtime mapping.
- Stable runtime IDs map only to the transparent portrait/icon under the
  frozen shared dark card frame. Opaque/compatibility derivatives are excluded
  from the Web PCK. Headless regression after import: `103/103 PASS`; R15
  content suite: `31/31 PASS`. Actual Web Character Detail and Party Formation
  screens rendered without fallback.
- Contact and evidence:
  `reports/r15/art_b/contact_sheets/CHR007_STATIC_ART_R1_CONTACT_SHEET.png`,
  `reports/r15/art_b/web/CHR007_R1_CHARACTER_DETAIL.png`, and
  `reports/r15/art_b/web/CHR007_R1_FORMATION.png`.
- GPT in-app pixel review: `TECHNICAL_PASS=YES`, `VISUAL_PASS=YES`,
  `REFERENCE_PARITY_PASS=YES`, head-authority ±5%, crop, fringe, Detail, and
  Formation all `PASS`; green-matte regression was not visible and hard
  failure was `NONE`. It found no obvious direct external-game asset or
  character-design trace in the reviewed pixels; that visual conclusion is
  not a legal provenance certification. P1 is only a future lineup instruction:
  avoid repeating the long-mantle/floating-device silhouette for CHR008.
- `CHR007` R1 is frozen. `PRODUCTION_APPROVED=WAITING_USER_APPROVAL`.

## CHR008 R1 — reviewed pilot-contract instance

- Canonical identity and retained Blender provenance:
  `docs/art/identity/CHR008_CANONICAL_IDENTITY_R1.md` and
  `asset_share/blender_sources/characters/CHR008/CHR008_STATIC_ART_R1.blend`.
  The source character is an adult female `MEDIC / BACK / ENERGY / BARRIER /
  SUPPORT_DEVICE`, designed around a rose-gold asymmetric bob, sea-green eyes,
  a porcelain/teal/coral rescue jacket, a hand-held tri-lens luminance kit, and
  a forearm barrier plate. It deliberately avoids the CHR006/007 long-mantle
  and floating-device silhouette family.
- Blender 4.5.11 LTS headless camera render produced a transparent 2048×3072
  master, 1024×1536 portrait, and 512×512 icon. Existing legacy files in the
  CHR008 folder were preserved; only explicit legacy paths, the R1 master, and
  retained compatibility derivatives are excluded from the Web PCK. Stable
  runtime IDs map to the transparent R1 portrait/icon.
- Technical regressions after import: headless `104/104 PASS`; R15 content
  suite `31/31 PASS`. A fresh same-port Web build rendered the character in
  Character Detail and Party Formation without fallback.
- Contact and evidence:
  `reports/r15/art_b/contact_sheets/CHR008_STATIC_ART_R1_CONTACT_SHEET.png`,
  `reports/r15/art_b/web/CHR008_R1_CHARACTER_DETAIL.png`, and
  `reports/r15/art_b/web/CHR008_R1_FORMATION.png`.
- GPT in-app pixel review: `TECHNICAL_PASS=YES`, `VISUAL_PASS=YES`,
  `REFERENCE_PARITY_PASS=YES`, identity continuity and head-authority ±5%
  `PASS`, hard failure `NONE`. It found no obvious direct external-game asset
  or character-design trace in the reviewed pixels; that visual conclusion is
  not a legal provenance certification. P0 is none. P1 is an optional 2–4%
  left-side breathing room for the tri-lens silhouette on a future tiny icon
  and a final CHR002–008 lineup parity sheet; neither requires an R2.
- `CHR008` R1 is frozen. `PRODUCTION_APPROVED=WAITING_USER_APPROVAL`.
