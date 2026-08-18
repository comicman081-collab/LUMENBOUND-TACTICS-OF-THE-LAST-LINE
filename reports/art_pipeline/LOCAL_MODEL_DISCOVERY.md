# Local model discovery

## Preservation rule

`C:\AI_MODELS` and `C:\AI_ENVS` are read-only source registries. Their weights,
environments, configs, and linked assets must not be modified, renamed, moved,
or deleted. This project stores only wrappers, prompts, manifests, hashes, and
generated outputs under the project root.

## Selection

| Model | Local path | License evidence | Approved role |
|---|---|---|---|
| SDXL Base 1.0 | `C:\AI_MODELS\sdxl-base-1.0` | Local `LICENSE.md`, CreativeML Open RAIL++-M | Concept and build-time generation |
| SDXL Inpaint 0.1 | `C:\AI_MODELS\sdxl-inpaint` | Official model card at locally cached repository revision, Open RAIL++ | Masked anatomy, prop, and costume correction |
| ControlNet Canny SDXL | `C:\AI_MODELS\controlnet-sdxl\controlnet-canny-sdxl-1.0` | Official model card at local commit `eb115a1`, Open RAIL++ | Silhouette and prop-shape lock |
| ControlNet Depth SDXL | `C:\AI_MODELS\controlnet-sdxl\controlnet-depth-sdxl-1.0` | Local and official model cards, Open RAIL++ | Depth and volume consistency |
| Depth Anything V2 Small | `C:\AI_MODELS\depth-anything-v2-small` | Official local source license and repository, Apache-2.0; only Small is approved | Depth guide extraction |
| IP-Adapter SDXL ViT-H | `C:\AI_MODELS\ip-adapter\sdxl_models` | Official repository at local commit `018e402`, Apache-2.0 | Consistency from project-owned concepts only |
| SAM 2.1 Hiera Small | `C:\AI_MODELS\SAM2\sam2.1-hiera-small` | Local model card and official source license, Apache-2.0 | Masks and sprite alpha QA |
| GroundingDINO Base | `C:\AI_MODELS\GroundingDINO\grounding-dino-base` | Local and official model cards, Apache-2.0 | Object localization and automated QA |
| CLIPSeg RD64 Refined | `C:\AI_MODELS\auto-mask` | Local model card, Apache-2.0 | Text-guided masks |
| Kandinsky 2.2 Prior + Inpaint Decoder | `C:\AI_MODELS\kandinsky-2-2-prior`, `C:\AI_MODELS\kandinsky-2-2-decoder-inpaint` | Both local and official model cards, Apache-2.0 | Alternative inpaint and concept candidates |

## Explicit exclusions

| Asset | Reason | Decision |
|---|---|---|
| Krea2 | Local manifest limits use to non-commercial purposes | `NON_COMMERCIAL_EXCLUDED`; never use |
| DreamShaper XL | Model-specific local license record not found | `LICENSE_UNRESOLVED`; never use |
| ControlNet OpenPose SDXL | Model card says `license: other` and defers to OpenPose terms | Never use |
| IP-Adapter FaceID / InsightFace weights | Pretrained-weight commercial rights not approved for this project | Never use |
| Local LoRA collection | Training data and base-model lineage require per-LoRA audit | Never use until separately approved |
| SD 1.5 Inpainting copy | Local source binding and license file are not yet verified | Never use until verified |
| MPFB-derived TRIAD body | Existing audit records source license as unknown | Never use |

No model is copied into the Godot project or Web package. Generated candidates remain `ART_QA_CANDIDATE` until visual review; model availability does not imply visual quality, output IP clearance, or production approval. All approved tools are build-time-only and must obey the project-wide `FEMALE_ONLY` character policy.
