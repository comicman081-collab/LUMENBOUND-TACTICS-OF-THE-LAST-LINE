# Local Audio Integration Report

## Scope

- Source root: `D:\AI 종합 폴더\Games\블아 like\Sound`
- Runtime policy: local files only; no network, cloud, external API, or runtime download
- Title track: English-only `01_wake_the_black_star.wav` (the source header is MP3/ID3 despite the legacy `.wav` suffix)
- Original source files were preserved in place and were not modified or deleted.

## Integrated runtime entries

| Group | Runtime entries | Runtime use |
|---|---:|---|
| BGM | 5 | title, lobby, story, battle, boss scenes |
| Player SFX | 4 | basic attack, normal skill, ultimate, received hit |
| Enemy SFX | 3 | normal attack, skill, received hit |
| Boss SFX | 3 | attack, skill, received hit |
| **Total** | **15** | `audio_manifest.json` |

The title source is trimmed at complete MP3 frame boundaries to a 30-second loop without an external codec. PCM BGM loops are downmixed to mono, resampled to 22.05 kHz, and compacted to 5 seconds for the Web package; the original tracks remain untouched. Short effects are copied byte-for-byte.

## Runtime integration

- `AudioService` loads the generated manifest and uses pooled local players.
- Scene routing starts title/lobby/story/battle/boss music at the existing screen boundaries.
- Battle events map to player, enemy, and boss attack/skill/ultimate/hit cues.
- Settings exposes a local-audio toggle; missing audio remains non-fatal.
- Headless execution suppresses player creation, avoiding audio-device leaks in CI.
- Map input accepts mouse and `InputEventScreenTouch`/`InputEventScreenDrag`, so the map route is touch-capable on mobile Web.

## Verification

```text
AUDIO_MANIFEST_ENTRIES=15
AUDIO_VALIDATION=PASS
STATIC_DATA_SOURCE_AUDIT: 60/60 PASS
GODOT_RUNTIME_TESTS: 87/87 PASS
WEB_BUILD: PASS (R7 fixed overwrite path)
SITES_ARCHIVE_LIMIT: PASS
```

The generated runtime manifest records source and runtime SHA-256 values. Source ownership and commercial rights for the supplied Sound folder have not been independently verified, so generated entries remain `LICENSE_UNRESOLVED` and are not claimed as commercially cleared.
