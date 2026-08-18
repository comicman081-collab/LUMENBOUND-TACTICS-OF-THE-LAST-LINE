# R7 Web runtime asset and audio correction

Date: 2026-08-19

## Root cause

The prior slim Web export excluded `assets/art/characters/*` and
`assets/generated_import/*` to stay below the hosted single-file limit.  The
runtime manifest still resolved the character IDs to those excluded paths, so
formation and the map pawn fell through to `dev_placeholder.svg`.

Title BGM was also requested during boot.  Web browsers block WebAudio started
before a user gesture, leaving that request silent without a later retry.

## Correction

- Added eight 384x576 RGBA **runtime Web cards** under
  `godot/assets/runtime_web/characters/`.
- Added `runtime_asset_manifest.json` and load it after legacy/premium
  manifests, preserving existing immutable icon and portrait asset IDs.
- Formation now renders card art in both the five equipped slots and the
  selectable roster grid.
- The Chapter Map resolves the selected party leader for every character ID,
  not only two previous pilot IDs.  The pawn is placed above the tile with its
  existing contact marker retained.
- Boot-time BGM is deferred.  The first real button, mouse, or touch gesture
  unlocks local WebAudio and plays the pending BGM.  All subsequent local BGM,
  SFX, voice hooks, and the existing settings toggle use the same guard.

Original source art and Blender/model sources were not edited or moved.
CHR006/CHR007 Web card source files are kept separately in
`data_source/art_source/runtime_cards/`.

## Verification

- Headless functional tests: **88/88 PASS** (one new assertion verifies all
  eight icon/portrait IDs resolve to existing packaged runtime cards).
- Chapter Map tests: **57/57 PASS**.
- Audio manifest validation: **15/15 entries PASS**.
- Web export PCK: `r7_current_dc1349025cbc.pck`, 11,176,404 bytes,
  SHA-256 `DC1349025CBC5C8A88121E11C57DF4C2BA48399FBC0FD0AA0E41BD8AD44DCBEA`.
- PCK string audit confirms inclusion of runtime character cards and local
  `title_theme.mp3` / `player_ultimate.wav` assets.
- In-app browser, local `127.0.0.1:8078`: title → home → formation → map
  verified with no console errors or warnings.  The five formation cards and
  eight roster cards were rendered; selected leader art was rendered on the
  map and moved from N01 toward N02 along the generated route.

## Scope and licensing

The compact cards restore UI and map-pawn identity in the hosted Web build.
They do not claim to replace the full high-frame SD combat packs.  Local audio
assets are included as supplied local files. On 2026-08-19 the project user
declared the Sound folder to contain original Manus-created material and
authorized commercial use; the audio manifest now records `USER_OWNED` with
that declaration basis.
