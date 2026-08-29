# LANTERNLINE Art Direction Bible

Status: pilot R5. This document defines an independent visual language; it does not authorize copying any reference title.

The core image is a nocturnal relay civilization built from dark brass, glass conduits, mineral light and weathered stone. Characters must read first through face, hair mass, role silhouette and one luminous accent. Backgrounds carry depth through foreground framing, a playable ground plane, mid-distance machinery and a cool atmospheric vanishing point.

Player humans are clearly adult women. Their designs use maximum non-explicit exposure without nudity or sexualized childlike traits. Enemies are genderless nonhuman machines or signal anomalies. Krea2 is excluded. External game assets and paid generation APIs are excluded.

Production gates remain: technical correctness, actual game-scale legibility, independent design, browser integration and user approval. A technically valid Blender render is never an automatic visual pass.

## Immutable presentation-role contract

Every playable character owns two separate visual families. They are not
interchangeable placeholders and one family must never silently replace the
other.

| Surface | Required visual family | Scope |
| --- | --- | --- |
| Real-time battle and chapter-map pawn | High-resolution adult SD (roughly 3.5–4 heads) | All 44 characters |
| Recruit/gacha reveal, character card, roster, profile, story standing and all non-combat UI | Premium 8-head full-body character illustration | All 44 characters |

All 8-head card/standing sources are authored against a flat `#00FF00` matte
for separation, then promoted only as true transparent RGBA. The green matte,
white background, checkerboard and crop boundary must never appear in the
runtime. Each promoted asset records character identity, costume fingerprint,
source SHA-256, alpha extrema and safe inset QA. If one family is absent for a
character, the card/recruit/roster build is a hard failure. It may not borrow
the SD counterpart, another character's art, or a generic fallback.
