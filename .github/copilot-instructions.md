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

The repo includes `start.sh` — a bash auto-installer **and** ComfyUI launcher in one script (it installs on first run, then always starts ComfyUI).

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

**Critical constraints:**
- The Linux wheels in this repo are `cp312` only — Python 3.12 is required.
- Do **not** reinstall torch unless explicitly needed; every startup syncs only non-torch ComfyUI deps to avoid multi-GB CUDA wheel re-downloads.

**Reinstall / upgrade mechanism:**
- First-run detection uses `$WORKSPACE/.comfy_installed_v3`. The script skips setup if this flag exists.
- To force a full reinstall after major changes, bump the `INSTALL_FLAG` variable to a new version string (e.g., `.comfy_installed_v4`).
- To force a full dependency sync on startup without triggering a full reinstall: `COMFY_FULL_REQ_SYNC=1 ./start.sh`

**Adding a new custom node:**
Use the `get_node <GIT_URL> <FOLDER_NAME>` pattern already in `start.sh`. This clones the repo and installs its `requirements.txt` and `install.py` automatically.

## Local Docker/WSL test mode

- The `Dockerfile` is a **CPU-only base image** (Ubuntu 22.04 + Python + GitHub CLI). GPU access comes from `gpus: all` in `docker-compose.yml`, which requires NVIDIA Container Toolkit on the host.
- `HF_TOKEN` is forwarded from the host environment (or a `.env` file) via the compose `environment` block.
- On first `docker compose up`, the repo is copied from the read-only `/seed-repo` mount into `/workspace/comfysetuper`.

**Validation sequence** (from `AGENT_INSTRUCTIONS.txt`):
```bash
docker compose up -d --build
docker exec -it comfy-test bash
nvidia-smi                          # must succeed before proceeding
export HF_TOKEN="<your_token>"
cd /workspace/comfysetuper && ./start.sh
# Watch for: "Starting ComfyUI on 0.0.0.0:8188"
# On failure: tail -n 200 /workspace/comfy_setup.log
```

**Persistence check:** Exit container, run `docker compose restart comfy-test`, re-enter and re-run `./start.sh`. Expected: fast startup with no reinstall.

**Cleanup:**
```bash
docker compose down
docker volume rm comfysetuper_comfy_workspace
```

## Shell script conventions

- Shell files (`start.sh`) must use **LF line endings and UTF-8 without BOM**.
- When ComfyUI adds new Python deps, sync core deps first by filtering out `torch`/`torchvision`/`torchaudio` lines — never trigger a full torch reinstall unless the CUDA version changes.
