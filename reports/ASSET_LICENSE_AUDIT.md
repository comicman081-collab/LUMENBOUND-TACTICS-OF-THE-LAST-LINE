# Asset License Audit

Status: **TECHNICAL PASS / COMMERCIAL REVIEW REQUIRED**

- Canonical ledger: `godot/assets/generated_import/licenses.json`.
- Records: 109, all with SHA-256.
- Factory records: 93 file-level entries.
- Project combat records: 15 bundle manifests (including one preserved older Guardian revision).
- Font record: 1, Noto Sans KR under SIL Open Font License 1.1.

The procedural factory code is MIT, but its visual manifests do not declare individual output rights. Those 93 outputs therefore remain conservatively recorded as `MANIFEST_NOT_DECLARED`, `commercial_use: false`, `attribution_required: true` and `DEV_PLACEHOLDER`.

Project-generated cutout animation and projectile bundles are recorded as `PROJECT_GENERATED_DEV_REVIEW_REQUIRED`, not production-approved. The two generated nonhuman enemy sources and all derived animation/VFX packs remain DEV-only pending final art-direction and legal review.

`godot/assets/generated_import/attribution.md` contains the merged attribution table. Godot’s engine license and the font OFL are separately accessible from the in-game settings/license screen. No ambiguous external asset is claimed commercially cleared.
