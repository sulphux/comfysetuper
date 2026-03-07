#!/bin/bash
# =============================================================================
# ComfyUI + Trellis2 — RunPod Installer
# Based on ComfyUI-Easy-Install by Tavris1 / VenimK (MAC-Linux branch)
# Adapted for RunPod (RTX 4090, Ubuntu, /workspace Network Volume)
# =============================================================================
#
# HARDWARE REQUIREMENTS
#   GPU  : RTX 4090 (24 GB VRAM)
#   RAM  : 64 GB recommended (mesh operations are CPU-heavy)
#   Base image: runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04
#   Network Volume : ≥50 GB mounted at /workspace
#
# REQUIRED ENVIRONMENT VARIABLES (set in RunPod pod settings)
#   HF_TOKEN — HuggingFace access token
#              ⚠ Request access to gated model before first run:
#                https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m
#
# HOW TO USE ON RUNPOD
#   Option A — Startup command (RunPod "On-Start Script" field):
#     bash -c "cd /workspace && git clone https://github.com/YOUR_USER/YOUR_REPO comfysetuper 2>/dev/null || true && bash /workspace/comfysetuper/start.sh"
#
#   Option B — After SSH into pod:
#     cd /workspace
#     git clone https://github.com/YOUR_USER/YOUR_REPO comfysetuper
#     bash /workspace/comfysetuper/start.sh
#
#   First run: ~45 min (mainly model downloads)
#   Subsequent starts: ~30 seconds
# =============================================================================

# ── Colors (same as CEI) ─────────────────────────────────────────────────────
WARNING='\033[33m'
RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Paths ─────────────────────────────────────────────────────────────────────
WORKSPACE="/workspace"
INSTALL_DIR="$WORKSPACE/ComfyUI-Easy-Install"
COMFY_DIR="$INSTALL_DIR/ComfyUI"
VENV_DIR="$INSTALL_DIR/venv"
MODELS_DIR="$COMFY_DIR/models"
CUSTOM_NODES_DIR="$COMFY_DIR/custom_nodes"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$WORKSPACE/comfy_setup.log"

# Bump this string to force reinstall after major changes
INSTALL_FLAG="$WORKSPACE/.comfy_installed_v3"

# ── pip / uv args (same as CEI) ───────────────────────────────────────────────
PIP_ARGS="--no-cache-dir --no-warn-script-location --timeout=120 --retries 3 --progress-bar on --root-user-action=ignore"
UV_ARGS="--no-cache --link-mode=copy"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo -e "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
ok()   { log "${GREEN}✓${RESET} $*"; }
warn() { log "${WARNING}⚠${RESET} $*"; }

# ── get_node — clone + install requirements + run install.py (CEI pattern) ────
get_node() {
    local GIT_URL=$1
    local GIT_FOLDER=$2
    echo -e "${GREEN}::::::::::::::: Installing${YELLOW} ${GIT_FOLDER} ${GREEN}:::::::::::::::${RESET}"
    echo ""
    git clone "$GIT_URL" "$CUSTOM_NODES_DIR/$GIT_FOLDER"

    if [ -f "$CUSTOM_NODES_DIR/$GIT_FOLDER/requirements.txt" ]; then
        if [ -s "$CUSTOM_NODES_DIR/$GIT_FOLDER/requirements.txt" ]; then
            $EMBEDDED_PYTHON -m uv pip install \
                -r "$CUSTOM_NODES_DIR/$GIT_FOLDER/requirements.txt" \
                $UV_ARGS || warn "Some requirements for $GIT_FOLDER failed (non-fatal)"
        fi
    fi

    if [ -f "$CUSTOM_NODES_DIR/$GIT_FOLDER/install.py" ]; then
        if [ -s "$CUSTOM_NODES_DIR/$GIT_FOLDER/install.py" ]; then
            $EMBEDDED_PYTHON "$CUSTOM_NODES_DIR/$GIT_FOLDER/install.py"
        fi
    fi
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# FIRST-RUN SETUP
# ─────────────────────────────────────────────────────────────────────────────
if [ ! -f "$INSTALL_FLAG" ]; then

    START_TIME=$(date +%s)
    # Clean previous (possibly broken) install before fresh setup
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR" "$WORKSPACE"

    log ""
    log "${GREEN}═══════════════════════════════════════════${RESET}"
    log "${GREEN} FIRST RUN — FULL SETUP                   ${RESET}"
    log "${GREEN}═══════════════════════════════════════════${RESET}"

    # Disable IPv6 to prevent hangs (same as CEI Linux)
    sysctl -w net.ipv6.conf.all.disable_ipv6=1     >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true

    # ── 1. Python 3.12 ────────────────────────────────────────────────────────
    if ! command -v python3.12 &>/dev/null; then
        log "Installing Python 3.12..."
        apt-get update -qq
        # Try direct install (Ubuntu 22.04 universe usually has 3.12)
        if ! apt-get install -y python3.12 python3.12-venv python3.12-dev 2>/dev/null; then
            apt-get install -y software-properties-common
            apt-get install --reinstall -y python3-apt 2>/dev/null || true
            add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null || {
                echo "deb https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu jammy main" \
                    > /etc/apt/sources.list.d/deadsnakes.list
                gpg --keyserver hkp://keyserver.ubuntu.com:80 \
                    --recv-keys F23C5A6CF475977595C89F51BA6932366A755776 2>/dev/null || true
            }
            apt-get update -qq
            apt-get install -y python3.12 python3.12-venv python3.12-dev
        fi
    fi
    ok "Python 3.12: $(python3.12 --version)"

    # ── 2. Build tools (needed for some pip packages) ─────────────────────────
    apt-get install -y git build-essential sox unzip curl 2>/dev/null || true

    # ── 3. Virtual environment ────────────────────────────────────────────────
    if [ ! -d "$VENV_DIR" ]; then
        python3.12 -m venv "$VENV_DIR"
    fi
    EMBEDDED_PYTHON="$VENV_DIR/bin/python"
    export PATH="$VENV_DIR/bin:$PATH"
    ok "venv at $VENV_DIR"

    # ── 4. uv package manager (CEI uses uv for speed) ─────────────────────────
    log "${YELLOW}[1/7]${RESET} Installing uv..."
    $EMBEDDED_PYTHON -m pip install uv==0.9.7 $PIP_ARGS
    UV_ARGS="$UV_ARGS --python $EMBEDDED_PYTHON"
    ok "uv installed"

    # ── 5. PyTorch 2.7.0 + CUDA 12.4 (matches RunPod template cuda12.4.1) ───────
    log "${YELLOW}[2/7]${RESET} Installing PyTorch 2.7.0 (CUDA 12.4)..."
    $EMBEDDED_PYTHON -m uv pip install \
        torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 \
        --index-url https://download.pytorch.org/whl/cu124 \
        $UV_ARGS
    ok "PyTorch $($EMBEDDED_PYTHON -c 'import torch; print(torch.__version__)')"

    # ── 6. Pre-install shared packages (CEI pattern) ──────────────────────────
    log "${YELLOW}[3/7]${RESET} Pre-installing shared packages..."
    $EMBEDDED_PYTHON -m uv pip install scikit-build-core  $UV_ARGS
    $EMBEDDED_PYTHON -m uv pip install onnxruntime-gpu    $UV_ARGS
    $EMBEDDED_PYTHON -m uv pip install onnx               $UV_ARGS
    $EMBEDDED_PYTHON -m uv pip install chardet==5.2.0     $UV_ARGS
    $EMBEDDED_PYTHON -m uv pip install stringzilla==3.12.6 $UV_ARGS
    $EMBEDDED_PYTHON -m uv pip install transformers==4.57.6 $UV_ARGS
    $EMBEDDED_PYTHON -m uv pip install av==16.0.1          $UV_ARGS
    $EMBEDDED_PYTHON -m uv pip install pygit2              $UV_ARGS
    $EMBEDDED_PYTHON -m uv pip install flet                $UV_ARGS
    $EMBEDDED_PYTHON -m uv pip install sqlalchemy          $UV_ARGS
    $EMBEDDED_PYTHON -m uv pip install "huggingface_hub[cli]" $UV_ARGS
    ok "Shared packages done"

    # ── 7. Clone ComfyUI ──────────────────────────────────────────────────────
    log "${YELLOW}[4/7]${RESET} Cloning ComfyUI..."
    git clone --quiet https://github.com/Comfy-Org/ComfyUI "$COMFY_DIR"
    cd "$COMFY_DIR"
    $EMBEDDED_PYTHON -m uv pip install -r requirements.txt $UV_ARGS
    cd "$INSTALL_DIR"
    ok "ComfyUI ready"

    mkdir -p "$CUSTOM_NODES_DIR"

    # ── 8. Pixaroma nodes (same list as CEI) ──────────────────────────────────
    log "${YELLOW}[5/7]${RESET} Installing Pixaroma nodes..."
    get_node https://github.com/Comfy-Org/ComfyUI-Manager             comfyui-manager
    get_node https://github.com/yolain/ComfyUI-Easy-Use               ComfyUI-Easy-Use
    get_node https://github.com/Fannovel16/comfyui_controlnet_aux     comfyui_controlnet_aux
    get_node https://github.com/rgthree/rgthree-comfy                 rgthree-comfy
    get_node https://github.com/MohammadAboulEla/ComfyUI-iTools       comfyui-itools
    get_node https://github.com/city96/ComfyUI-GGUF                   ComfyUI-GGUF
    get_node https://github.com/gseth/ControlAltAI-Nodes              controlaltai-nodes
    get_node https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch comfyui-inpaint-cropandstitch
    get_node https://github.com/1038lab/ComfyUI-RMBG                  comfyui-rmbg
    get_node https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite  comfyui-videohelpersuite
    get_node https://github.com/shiimizu/ComfyUI-TiledDiffusion       ComfyUI-TiledDiffusion
    get_node https://github.com/kijai/ComfyUI-KJNodes                 comfyui-kjnodes
    get_node https://github.com/kijai/ComfyUI-WanVideoWrapper         ComfyUI-WanVideoWrapper
    get_node https://github.com/1038lab/ComfyUI-QwenVL                ComfyUI-QwenVL
    get_node https://github.com/flybirdxx/ComfyUI-Qwen-TTS            qwen3-tts-comfyui
    get_node https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler   seedvr2_videoupscaler
    get_node https://github.com/chflame163/ComfyUI_LayerStyle         comfyui_layerstyle
    get_node https://github.com/kijai/ComfyUI-WanAnimatePreprocess    ComfyUI-WanAnimatePreprocess
    get_node https://github.com/yolain/ComfyUI-Easy-Sam3              comfyui-easy-sam3
    get_node https://github.com/kijai/ComfyUI-SCAIL-Pose              ComfyUI-SCAIL-Pose
    get_node https://github.com/kijai/ComfyUI-MelBandRoFormer         ComfyUI-MelBandRoFormer
    ok "Pixaroma nodes done"

    # ── 9. Trellis2 nodes ─────────────────────────────────────────────────────
    log "${YELLOW}[6/7]${RESET} Installing Trellis2 nodes..."

    # Main Trellis2 node (do NOT use get_node — wheels must be installed first)
    git clone --quiet https://github.com/visualbruno/ComfyUI-Trellis2.git \
        "$CUSTOM_NODES_DIR/ComfyUI-Trellis2"

    # Custom wheels for Torch 2.7.0 / Python 3.12 / Linux
    # Includes: cumesh, nvdiffrast, flex_gemm, o_voxel
    WHEELS_DIR="$CUSTOM_NODES_DIR/ComfyUI-Trellis2/wheels/Linux/Torch270"
    log "  Installing Trellis2 CUDA extension wheels (Torch270/cp312)..."
    $EMBEDDED_PYTHON -m uv pip install "$WHEELS_DIR"/*.whl $UV_ARGS

    # Trellis2 pip requirements (meshlib, pymeshlab, open3d, rembg, etc.)
    $EMBEDDED_PYTHON -m uv pip install \
        -r "$CUSTOM_NODES_DIR/ComfyUI-Trellis2/requirements.txt" \
        $UV_ARGS

    # StableX depth node (DownloadAndLoadStableXModel, StableXProcessImage)
    # Install Hi3DGen requirements first (filter out torch/torchvision pins)
    git clone --quiet https://github.com/Stable-X/ComfyUI-Hi3DGen.git \
        "$CUSTOM_NODES_DIR/ComfyUI-Hi3DGen"
    TMPFILE=$(mktemp)
    grep -vE "^(torch|torchvision)==" \
        "$CUSTOM_NODES_DIR/ComfyUI-Hi3DGen/linux_requirements.txt" > "$TMPFILE"
    $EMBEDDED_PYTHON -m uv pip install -r "$TMPFILE" $UV_ARGS || true
    rm -f "$TMPFILE"
    # spconv for CUDA 12.x/13.x
    $EMBEDDED_PYTHON -m uv pip install "spconv-cu124>=2.3.6" $UV_ARGS || \
    $EMBEDDED_PYTHON -m uv pip install "spconv-cu120>=2.3.6" $UV_ARGS || \
    warn "spconv install failed — StableX depth node may not work"

    # Triton (CEI installs this at the end)
    $EMBEDDED_PYTHON -m pip install --upgrade --force-reinstall triton $PIP_ARGS \
        || warn "triton install failed (non-fatal)"

    ok "Trellis2 nodes done"

    # ── 10. HuggingFace login + model downloads ───────────────────────────────
    log "${YELLOW}[7/7]${RESET} Downloading models..."

    if [ -n "${HF_TOKEN:-}" ]; then
        $EMBEDDED_PYTHON -m huggingface_hub login --token "$HF_TOKEN" 2>/dev/null || \
        $VENV_DIR/bin/huggingface-cli login --token "$HF_TOKEN"
        ok "HuggingFace authenticated"
    else
        warn "HF_TOKEN not set — gated models will fail. Set it in RunPod env vars."
    fi

    mkdir -p "$MODELS_DIR/microsoft" "$MODELS_DIR/facebook"

    # TRELLIS.2-4B (~30 GB)
    if [ ! -d "$MODELS_DIR/microsoft/TRELLIS.2-4B" ] || \
       [ -z "$(ls -A "$MODELS_DIR/microsoft/TRELLIS.2-4B" 2>/dev/null)" ]; then
        log "  Downloading microsoft/TRELLIS.2-4B (~30 GB)..."
        $VENV_DIR/bin/huggingface-cli download microsoft/TRELLIS.2-4B \
            --local-dir "$MODELS_DIR/microsoft/TRELLIS.2-4B" \
            --local-dir-use-symlinks False \
            || { warn "TRELLIS.2-4B download failed"; }
    fi
    ok "TRELLIS.2-4B ready"

    # Facebook DINOv3 — GATED (needs prior access approval on HuggingFace)
    DINO_DIR="$MODELS_DIR/facebook/dinov3-vitl16-pretrain-lvd1689m"
    if [ ! -f "$DINO_DIR/model.safetensors" ]; then
        log "  Downloading facebook/dinov3-vitl16-pretrain-lvd1689m (GATED)..."
        log "  ⚠ If this fails: https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m"
        $VENV_DIR/bin/huggingface-cli download facebook/dinov3-vitl16-pretrain-lvd1689m \
            --local-dir "$DINO_DIR" \
            --local-dir-use-symlinks False \
            || warn "DINOv3 download failed — request access and re-run"
    fi
    ok "DINOv3 ready"

    # TRELLIS-image-large (legacy ckpts used by Trellis2 node internally)
    if [ ! -d "$MODELS_DIR/microsoft/TRELLIS-image-large" ] || \
       [ -z "$(ls -A "$MODELS_DIR/microsoft/TRELLIS-image-large" 2>/dev/null)" ]; then
        log "  Downloading microsoft/TRELLIS-image-large..."
        $VENV_DIR/bin/huggingface-cli download microsoft/TRELLIS-image-large \
            --local-dir "$MODELS_DIR/microsoft/TRELLIS-image-large" \
            --local-dir-use-symlinks False \
            || warn "TRELLIS-image-large download failed (non-fatal, node may auto-retry)"
    fi
    ok "TRELLIS-image-large ready"

    # ── 11. Copy workflows ────────────────────────────────────────────────────
    mkdir -p "$COMFY_DIR/user/default/workflows"
    if ls "$SCRIPT_DIR"/Trellis2_MV_*.json &>/dev/null; then
        cp "$SCRIPT_DIR"/Trellis2_MV_*.json "$COMFY_DIR/user/default/workflows/"
        ok "Workflows copied to ComfyUI"
    else
        warn "Trellis2_MV_*.json not found in $SCRIPT_DIR"
    fi

    # ── Done ──────────────────────────────────────────────────────────────────
    END_TIME=$(date +%s)
    DIFF=$((END_TIME - START_TIME))
    touch "$INSTALL_FLAG"
    echo ""
    echo -e "${GREEN}::::::::::::::: Installation Complete :::::::::::::::${RESET}"
    echo -e "${GREEN}::::::::::::::: Total time:${RED} ${DIFF}s${GREEN} :::::::::::::::${RESET}"
    echo ""
fi

# ─────────────────────────────────────────────────────────────────────────────
# START COMFYUI
# ─────────────────────────────────────────────────────────────────────────────
EMBEDDED_PYTHON="$VENV_DIR/bin/python"
cd "$COMFY_DIR"

# Keep existing installs in sync with latest ComfyUI runtime deps
# (e.g. alembic/sqlalchemy required by newer ComfyUI releases).
log "${YELLOW}Syncing ComfyUI requirements before start...${RESET}"
if [ -f "$COMFY_DIR/requirements.txt" ]; then
    if ! "$EMBEDDED_PYTHON" -m pip install \
        -r "$COMFY_DIR/requirements.txt" \
        --disable-pip-version-check \
        --root-user-action=ignore \
        --no-cache-dir \
        >> "$LOG" 2>&1; then
        log "${RED}✗ Failed to sync ComfyUI requirements. Check: $LOG${RESET}"
        exit 1
    fi
    ok "ComfyUI requirements synced"
else
    warn "ComfyUI requirements.txt missing at $COMFY_DIR"
fi

log ""
log "${GREEN}Starting ComfyUI on 0.0.0.0:8188${RESET}"
log "Access: RunPod → Connect → HTTP Service → Port 8188"
log "Log: $LOG"

exec $EMBEDDED_PYTHON main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    2>&1 | tee -a "$LOG"
