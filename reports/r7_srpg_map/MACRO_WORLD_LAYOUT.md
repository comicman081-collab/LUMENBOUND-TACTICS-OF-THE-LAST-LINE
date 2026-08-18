# Chapter 1 Macro World Layout — R7M

## Product decision

Chapter 1 is no longer a complete board that fits into one normal gameplay
camera view. The player sees only the local terrain around the squad. The full
route has a **minimum 12 local-view lengths** from the relay camp to NORMAL N10.
This is deliberately larger than the requested ten-view minimum.

The map is not re-rolled per save or per play session. It uses the fixed seed
`7011801`, so its apparently wandering direction is stable for saves, replay,
deterministic pathfinding, screenshots, and content QA.

## Authoritative layout

- Coordinate system: axial hex (`q`, `r`).
- Macro bounds: `q -18..112`, `r -34..18`.
- Start: `(0, 0)`.
- NORMAL spine: N01 `(8,1)` → N10 `(95,-16)`.
- HARD branch: H01 `(91,-10)` → H05 `(60,-12)`.
- Start-to-N10 axial distance: 96 hexes.
- First encounter length: 9 hexes, deliberately long enough to show movement
  but short enough not to turn every first-stage entry into waiting.
- Map movement cost: zero stamina. Only battle confirmation uses the existing
  single stamina transaction.

## Runtime streaming

The data grid is complete, but `ChapterMapScreen` retains meshes and terrain
dressing only within an 8-hex radius of the camera focus. Moving the camera or
squad streams out stale tile meshes and their prop roots, then streams in the
new local neighbourhood. Node state, route choice, fog, progression, and save
state remain coordinate/data-driven and are never derived from rendered nodes.

The continuous ocean plane is visual-only. Its presence does not make water
walkable: deep-water boundary rows remain blocked in `HexGrid` and are covered
by the pathfinding tests.

## Save compatibility

Save schema v3 stores the squad at stable axial coordinates and stable node IDs.
For v1/v2 saves created when the map was compact, migration reanchors the squad
to its immutable `last_selected_node`, otherwise the latest cleared node, then
the start. Clear history, stars, HARD attempts, pity, rewards, and unlocks are
preserved unchanged.

## Verification

- Chapter-map suite: 57/57 PASS on Godot 4.7.1 Stable.
- Existing runtime suite: 87/87 PASS after the macro-map change.
- Actual Web Release flow: local route preview, 9-hex movement, N01 battle
  entry, and map return at `(8,1)` observed in the Codex in-app browser.
- Visual/production approval: still waiting for user review; this document does
  not promote the map art to production status.
