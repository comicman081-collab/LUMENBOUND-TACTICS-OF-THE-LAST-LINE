# Local concept revision 03 — SDXL Inpaint

Model: approved local `diffusers/stable-diffusion-xl-1.0-inpainting-0.1`. Offline: yes. Character policy: `FEMALE_ONLY`. Krea2 used: no. Source model modified: no. Production approved: no.

## Guardian

Verdict: `FAIL`.

- The requested octagonal shield was removed rather than reconstructed.
- The hood-like blue shape remained.
- A watermark-like mark appeared at the lower-left edge.
- The unmasked face and costume identity mostly survived, but the principal role silhouette became weaker.

The result is retained only as failure evidence and is not copied into the Blender guide collection.

## Medic

Verdict: `FAIL`.

- The diagnostic ring was not generated.
- The arm region became simpler and less material-rich.
- The pose remained static.
- Face and mint palette survived, but the requested profession-defining silhouette is still absent.

## Pipeline decision

SDXL Inpaint remains license-approved for narrow texture or small-detail corrections, but it is not accepted as the sole method for large structural prop replacement in this pilot. Revision 04 must lock project-authored geometry with Canny or depth conditioning before image synthesis. No R03 output is promoted to `DIRECTION_SELECTED_ONLY` or `PRODUCTION_APPROVED`.
