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
