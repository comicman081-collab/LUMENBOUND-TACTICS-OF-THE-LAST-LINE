# Local commercial-use model license audit

Audit date: 2026-08-17. Scope: locally installed assets under `C:\AI_MODELS` that can materially improve the premium pilot. This is a technical rights-screening record, not legal advice and not a warranty that every generated output is non-infringing.

## Approved for offline build-time use

| Pipeline role | Local asset | License finding | Conditions |
|---|---|---|---|
| Main generation | SDXL Base 1.0 | CreativeML Open RAIL++-M | Follow use restrictions; audit each output for third-party IP |
| Targeted correction | SDXL Inpaint 0.1 | CreativeML Open RAIL++-M | Project-owned input images only |
| Shape consistency | ControlNet Canny / Depth SDXL | CreativeML Open RAIL++-M | No external copyrighted reference ingestion |
| Depth extraction | Depth Anything V2 Small | Apache-2.0 | Small checkpoint only; Base/Large/Giant remain excluded |
| Image-prompt consistency | IP-Adapter SDXL ViT-H | Apache-2.0 | Project-owned concept inputs only; no FaceID path |
| Masking and QA | SAM 2.1 Small, GroundingDINO Base, CLIPSeg | Apache-2.0 | Preserve notices; build-time only |
| Alternate inpaint | Kandinsky 2.2 Prior + Inpaint Decoder | Apache-2.0 | Output still requires originality and IP review |

## Binding evidence

- SDXL Inpaint official model card: https://huggingface.co/diffusers/stable-diffusion-xl-1.0-inpainting-0.1
- ControlNet Canny exact locally cached commit: https://huggingface.co/diffusers/controlnet-canny-sdxl-1.0/tree/eb115a19a10d14909256db740ed109532ab1483c
- ControlNet Depth model card: https://huggingface.co/diffusers/controlnet-depth-sdxl-1.0
- Depth Anything V2 official repository: https://github.com/DepthAnything/Depth-Anything-V2
- IP-Adapter exact locally cached commit: https://huggingface.co/h94/IP-Adapter/tree/018e402774aeeddd60609b4ecdb7e298259dc729
- IP-Adapter official code repository: https://github.com/tencent-ailab/IP-Adapter
- SAM2 official repository: https://github.com/facebookresearch/sam2
- GroundingDINO Base official model page: https://huggingface.co/IDEA-Research/grounding-dino-base
- Kandinsky 2.2 Prior: https://huggingface.co/kandinsky-community/kandinsky-2-2-prior
- Kandinsky 2.2 Inpaint Decoder: https://huggingface.co/kandinsky-community/kandinsky-2-2-decoder-inpaint

## Prohibited

Krea2 remains a permanent non-commercial exclusion. DreamShaper XL, ControlNet OpenPose, IP-Adapter FaceID/InsightFace, the local LoRA collection, SD 1.5 Inpainting, and the MPFB-derived body remain blocked until their exact weight and training lineage is separately proven acceptable. Availability on disk is not approval.

All model roots and environments remain read-only. No weight, config, linked asset, cache, or environment file was modified, moved, renamed, or deleted during this audit.
