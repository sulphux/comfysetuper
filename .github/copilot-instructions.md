# Copilot Instructions

## What this repository is

A set of **ComfyUI workflow JSON files** for AI-powered 3D model generation using the [visualbruno/ComfyUI-Trellis2](https://github.com/visualbruno/ComfyUI-Trellis2) custom node pack. The workflows take multi-view 2D images (front, back, left, right) and produce textured 3D meshes exported as `.glb`.

## The three workflows

| File | Purpose |
|------|---------|
| `Trellis2_MV_MeshOnly.json` | Geometry-only pipeline — generates an untextured mesh from multi-view images |
| `Trellis2_MV_TextureMesh.json` | Texturing-only pipeline — applies textures to an existing mesh using multi-view images |
| `Trellis2_MV_Combined.json` | Full pipeline — geometry + texturing in one graph, with optional StableX depth estimation and background removal |

## Node pipeline architecture

### Geometry pipeline (MeshOnly / Combined)
```
Trellis2LoadModel
  └─ Trellis2MeshWithVoxelMultiViewGenerator   ← takes preprocessed multi-view images
       └─ Trellis2MeshWithVoxelToTrimesh
            └─ Trellis2RemeshWithQuad
                 └─ Trellis2FillHolesWithMeshlib
                      └─ Trellis2SimplifyMesh
                           └─ Trellis2ExportMesh  → .glb output
```

### Texture pipeline (TextureMesh / Combined)
```
Trellis2LoadModel + Trellis2LoadMesh (existing geometry)
  └─ Trellis2MeshTexturingMultiView   ← takes preprocessed multi-view images
       └─ Trellis2ExportMesh  → .glb output
```

### Image preprocessing (all workflows)
Every view image goes through:
```
Trellis2LoadImageWithTransparency  →  Trellis2PreProcessImage  →  [geometry or texture node]
```
The `TextureMesh` workflow uses the raw `image` output; `MeshOnly`/`Combined` use `image_with_alpha`.

## Key conventions

- **Model**: All workflows load `TRELLIS.2-4B` via `Trellis2LoadModel` with `flash_attn` attention, on `cuda`.
- **Image ratio**: Input images must be **1:1 (square)**; non-square inputs cause mesh distortions (noted in MarkdownNote nodes throughout the graphs).
- **Output filenames**: Export nodes use descriptive prefixes (`TexturedMeshMV`, etc.) in `.glb` format with `simplify_mesh = true`.
- **Combined workflow extras**: Includes `easy imageRemBg` (from `yolain/ComfyUI-Easy-Use`) for background removal and `DownloadAndLoadStableXModel` + `StableXProcessImage` (from `Stable-X/ComfyUI-Hi3DGen`) for optional depth-guided geometry. A `Fast Groups Bypasser (rgthree)` node controls whether the StableX branch is active.
- **Node versioning**: Each custom node's `properties` object contains `aux_id` (e.g. `visualbruno/ComfyUI-Trellis2`) and `ver` (a commit SHA) for reproducibility.
- **Seed/sampler**: The texturing node (`Trellis2MeshTexturingMultiView`) uses seed `12345`, `fixed` mode, 25 steps, CFG 3, denoise 0.2, texture resolution 1024×4096.

## Editing workflows

These files are consumed by the ComfyUI web UI (drag-and-drop onto the canvas) or loaded via the **Load** button. Edit them as JSON or directly in the ComfyUI graph editor. The `extra.frontendVersion` field reflects the ComfyUI version the workflow was saved with (`1.38.13`).

When modifying JSON directly:
- `nodes[].widgets_values` order matches the visual widget order in the ComfyUI node — refer to the node's `inputs` array for named mappings.
- `links` array entries follow the format `[link_id, src_node_id, src_slot, dst_node_id, dst_slot, type]`.
- `last_node_id` and `last_link_id` must be updated if nodes/links are added.

## RunPod deployment (`start.sh`)

The repo includes `start.sh` — a bash auto-installer targeting RunPod with an RTX 4090.

**What it installs on first run:**
- Python 3.12 (required — custom wheels are `cp312` only)
- PyTorch 2.7.0 + CUDA 12.4 wheels
- ComfyUI + custom node stack (CEI-style list + Trellis2/Hi3DGen)
- Custom C++ wheels from `wheels/Linux/Torch270/` (cumesh, nvdiffrast, flex_gemm, o_voxel)
- Models: `microsoft/TRELLIS.2-4B`, `facebook/dinov3-vitl16-pretrain-lvd1689m`, `microsoft/TRELLIS-image-large`

**Required setup before running:**
- Set `HF_TOKEN` env var in the RunPod pod (gated model access needed for `facebook/dinov3`)
- Request HuggingFace access at `https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m`
- Network Volume ≥50 GB mounted at `/workspace`

**Critical constraint:** The Linux wheels in this repo are `cp312` only. Any Python version other than 3.12 will fail at the wheel install step.

## Local Docker/WSL test mode

- Use `Dockerfile` + `docker-compose.yml` from repo root to run an Ubuntu 22.04 GPU container.
- Start with `docker compose up -d --build` and enter with `docker exec -it comfy-test bash`.
- Use `/workspace` as persistent volume inside container (mirrors RunPod workflow).
- Follow `AGENT_INSTRUCTIONS.txt` for the exact validation sequence.
