# Known Limitations

Actual remaining limitations only:

1. Active character/enemy cutout animation, story portraits and backgrounds are explicitly DEV assets. Technical visual QA passed, but no final production-art approval is claimed.
2. Five of eight playable characters have active image-based 80-frame combat packs. CHR006–CHR008 remain runtime fallbacks when used; completing their image packs is still required for full art parity.
3. Two of eleven enemy definitions have image-based animation packs. Other enemies use the generic nonhuman fallback presentation.
4. Story backgrounds remain low-detail factory placeholders; static portrait staging works but final 1920×1080 backgrounds/CGs and 1024×1536 portrait sets are not complete.
5. Factory visual outputs lack per-output commercial-rights declarations and remain `commercial_use: false` until the owner confirms them.
6. The level-10 CH01-N10 100-run sample won 100%; balance requires hardening before content sign-off.
7. The 600-simulation-second load test passed, but an actual wall-clock ten-minute browser/GPU soak is UNVERIFIED.
8. Character detail, skill and weapon controls currently share one dense combined growth screen rather than fully separated polished tabs.
9. No production audio files were available; playback hooks exist, but audio QA is UNVERIFIED.
10. Offline HARD daily limits, local dates and checksums are not server-authoritative anti-cheat.
11. Windows native app and Android APK/device QA are not part of the current HTML-only scope; Android is explicitly deferred by the user.
12. Windows Godot reports a nonfatal root-certificate-store warning in offline headless runs. Project save/log writes use `.runtime_profile` and do not depend on the blocked default AppData log path.
