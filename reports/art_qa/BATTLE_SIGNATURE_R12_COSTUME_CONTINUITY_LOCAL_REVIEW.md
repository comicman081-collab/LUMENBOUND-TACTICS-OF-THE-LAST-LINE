# Battle Signature R12 — Costume Continuity Local Review

Status: **LOCAL_QA_PASS · PROMOTION HOLD**  
Reviewed: 2026-09-05 (Asia/Seoul)  
Scope: CHR003 Narin and CHR005 Soren only; this is a local runtime-candidate
review and does not grant production approval or public-export authority.

## Immutable identity authorities

| Candidate | Authority | Source animation manifest SHA-256 | Local visual result |
| --- | --- | --- | --- |
| CHR003 Narin | `docs/art/identity/CHR003_CANONICAL_IDENTITY_R1.md` | `e5aa931b41432023ab6ad94aee6e1541408dcb6c8461746111956addc323e2fa` | Pass: silver-blue high left-swept ponytail, focused adult face, black/white/cobalt tactical silhouette, controlled two-hand precision-rifle pose remain distinct from sword and artillery roles. |
| CHR005 Soren | `docs/art/identity/CHR005_CANONICAL_IDENTITY_R1.md` | `e786b8278fa9ebe27843f9fd03e090e7b0511b394222a4458c2d677e3c14863e` | Pass: honey-blonde high ponytail, charcoal/brass + ivory split-coat silhouette, grounded two-hand emerald-core anomaly cannon remain distinct from the guardian, vanguard, and rifle specialist. |

The R12 build is deterministic resize + alpha-tight atlas packing only; it
does not alter either source or costume. Both candidates keep the existing
30-degree player orientation, adult non-explicit presentation, separate
left/right facing policy, foot anchor `(0.5, 0.88)`, and 384px runtime logical
frame canvas.

## Visual and runtime evidence

- Dark mobile runtime: `reports/art_qa/battle_signature_hd_r12_viewport_2026-09-04T15-57-00/01_idle.png`, `09_chr003_ultimate_windup.png`, `10_chr003_ultimate_projectile_travel.png`, `12_chr005_ultimate_windup.png`, and `13_chr005_ultimate_projectile_travel.png`.
- Full concurrent staging: CHR001/CHR002/CHR003/CHR005/CHR008 with BOSS001 and ENM001 at **390×844**. The report records five face-only ultimate orbs, five READY badges at full gauge, and zero party HP/SH text cards.
- Alpha evidence: every R12 packed animation reports `visible_exact_green_pixels = 0`; no white rectangle or opaque source background is visible in the mobile battle screenshots.
- Companion chroma checks for the two previously matted assets passed on both dark and light backdrops: `reports/art_qa/BATTLE_SIGNATURE_HD_R12_CHR002_CHROMA_KEY_QA.png` and `reports/art_qa/BATTLE_SIGNATURE_HD_R12_ENM001_CHROMA_KEY_QA.png`. Green masters are retained as provenance only; runtime uses their keyed RGBA derivatives.
- Paging evidence: each of CHR003 and CHR005 acquired only its own transient ultimate page during its real ULTIMATE event, then returned to the 51,146,752-byte core residency. The largest recorded actor peak is 59,891,712 bytes, under the 75,497,472-byte mobile ceiling.

## Gates still intentionally held

1. The identity authority documents for CHR003 and CHR005 retain
   `WAITING_USER_APPROVAL` / local-QA source status. This review does not
   override that condition.
2. R12/R3 remain `LOCAL_QA_ONLY`; no deployment or GitHub Actions release was
   requested or run.
3. ChatGPT web Sol Pro implementation review must return and be evaluated
   after this completed local batch before any promotion decision.

