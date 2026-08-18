# Build Report

Date: 2026-08-17

## Web / HTML

Status: **BUILT / RELEASE BROWSER PASS**

- Engine: Godot `4.7.1-stable (official)` Standard, GDScript.
- Renderer: Compatibility; Web threads and GDExtension disabled.
- Outputs: `builds/web_development/`, `builds/web_release/`.
- Package: `builds/SD_STORY_RPG_HTML.zip`.
- HTML package bytes: 219,207,871.
- HTML package SHA-256: `9f51b1f99d1b6c8973618b9ecf8cc2bbb608c2bb78bfa4a6abc95ff3ee38eeb5`.

The final release was served locally on `127.0.0.1:8062` and exercised in a real browser through story, formation, battle, pause, result and save/reload. Korean text/font rendered, story and combat textures resolved from the canonical asset path, and the console produced 0 errors/warnings.

## Source

Status: **PACKAGING SCRIPT READY / FINAL HASH IN `builds/SHA256SUMS.txt`**

`PACKAGE_SOURCE.ps1` includes the Godot project, canonical data sources, tools, documents, tests, reports and licenses. It excludes `.godot`, `.runtime_profile`, temporary staging, Python caches, credentials, signing files, local model roots, build intermediates and the ignored legacy bridge duplicate.

- Source package: `builds/SD_STORY_RPG_SOURCE.zip`.
- Source bytes: 261,283,132.
- Source SHA-256: `17204292432d8af9a09fa4f3d18a0c615fbc6ae43943a1a49dbe193fea330cda`.

## Native Windows / Android

Status: **NOT BUILT**

The current scope is HTML only. The installed Windows Godot executable is used as the editor/headless runner/Web exporter; no Windows application artifact is claimed. Android APK creation is explicitly deferred by the user, so Android execution and visual QA remain UNVERIFIED.
