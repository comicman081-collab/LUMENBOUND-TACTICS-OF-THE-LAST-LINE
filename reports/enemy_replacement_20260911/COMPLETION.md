# Sprite Gen monster replacement — 52 creatures

Follow-up completed: the original 8 SD characters and 13 monsters were also redrawn and integrated. Current delivery and cleanup: `../existing_roster_spritegen_20260911/COMPLETION.md`. The first-batch build below is a historical verification record; its duplicate non-audio export files were retired after the combined replacement passed its gates.

The 32 polygon enemies ENM011–ENM042 and 20 polygon bosses BOSS004–BOSS023 now use individually generated and reviewed GPT originals. The user explicitly authorized Codex GPT image generation through Sprite Gen, and subsequently approved the artwork's appearance.

Generation: installed Sprite Gen 2.1.0 `gen --provider codex`, with 52 original designs. Uniform green masters are retained. Where the provider returned actual alpha despite the green request, the untouched raw was retained and composited onto an exact green master before the canonical Sprite Gen cutout. No local models or installed runtimes were altered.

Integration: 52 compact battle packs, 52 full-density 256px battle packs and 52 192px map packs share the same source hash/identity. Existing combat timing and presentation motion remain in use; this batch does not claim newly drawn animation rows. Enemies and bosses retain explosion-only defeat effects.

Validation:

- 52/52 alpha, framing and visual reviews passed.
- 7,281 installed atlas/source/timing checks passed.
- All 500 authored encounters fit the 144 MiB actor budget; worst starting/largest-five party lease is 144,683,008 bytes (137.98 MiB).
- Godot's actual BattleSpriteLibrary and StageAssetCache passed 832/832 checks across all 52 creatures.
- Existing headless regression suite passed 301/301.
- Browser render audit passed 228/228 across CH02-N01, CH08-N20 and CH20-N20. Final boss waves were held renderer fixtures, not claims that preceding waves were won.
- Ordinary Release player navigation passed 4/4 checks, including real map entry, browser BGM and no exposed developer command bridge.

Verified local Release: `builds/web_monster52_spritegen_20260911_release`, PCK SHA-256 `6045268aeece3329cb205e272d22cc40094e1791dbd984f3e2e7cf0a09806059`.

Old runtime packs and index files are retained at `quarantine/enemy_placeholders_20260911/` with a retirement manifest. Original source art, all audio and all earlier intro videos are preserved. No network deployment or GitHub Actions was triggered.

User's next authorized batch: refresh the original 8 SD characters and the previous 13 monsters using Sprite Gen, preserving character identity/costumes and combat role. Preparation inventory: `work/existing_roster_spritegen_20260911/reference_inventory.json`. That batch begins after this verified 52-monster batch.
