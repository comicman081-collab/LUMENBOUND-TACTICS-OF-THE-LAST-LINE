# Repository automation policy

These rules apply to ChatGPT, Codex, and other coding agents working in this repository.

## GitHub Actions safety
- Normal code edits, commits, pushes, branch work, and pull requests MUST NOT intentionally trigger GitHub Actions.
- Do not run, re-run, dispatch, or otherwise start GitHub Actions unless the user explicitly asks for a deployment or explicitly asks to run CI.
- The deployment workflow is intentionally gated by `.deploy/REQUEST`. Do not modify that file during ordinary coding.

## Explicit deployment protocol
- Only when the user explicitly says to deploy/publish/release the current repository, update `.deploy/REQUEST` on `main` with a fresh deployment request value and push that single change.
- That request is the approved trigger for exactly one deployment workflow run.
- Do not create retry loops. If deployment fails, inspect the existing failed run first. Do not retry without explicit user approval.
- Do not change the deployment trigger back to broad `push` or `pull_request` events.

## Cost guardrails
- Prefer local/static verification during normal development.
- Never add broad `push`, `pull_request`, `schedule`, `workflow_run`, or recursive dispatch triggers without explicit user approval.
- Keep `concurrency`/`cancel-in-progress` and finite timeouts on runner jobs.

## Local storage (user request, 2026-09-11)
- Retain the current verified local player build and only the candidate currently under verification. Retire replaced build copies after their replacement passes the relevant checks; record paths and hashes first.
- Do not retain disposable browser profiles after QA. Preserve screenshots, assertions and console reports. Use the cleanup implemented in `tools/web_qa/gameplay_session.mjs`.
- Preserve every previous intro video and all BGM, title songs and ending songs, including unused music and their source archives. The protected media inventories are under `reports/storage_cleanup_20260911/`.
- Keep required source artwork and the existing failed-asset review gate. Do not accumulate duplicate export bundles, copied test templates or abandoned temporary pack files.
- Additional cleanup must preserve every remaining audio file, not just currently used tracks. The September 11 second-pass inventory records this boundary.
- Update (user request, 2026-09-28): remove everything unneeded and keep sound assets. Story voices are the exception: keep only the takes linked in game (`godot/assets/audio/voice/ja/voice_manifest.json` runtime files and the raw takes named in `work/voice_ja_20260927/selection.json`); discarded takes, auditions and probes are deleted. Every other sound (BGM, title/ending songs, SFX, source archives) stays, used or not.
- `quarantine/retained_archive_20260911/` was retired on 2026-09-28 under that request. Its audio members matched kept copies; every file is hashed in `reports/cleanup_20260928/retired_files.jsonl.gz`. `tools/qa/restore_legacy_storage.py` no longer has an archive to restore from.
