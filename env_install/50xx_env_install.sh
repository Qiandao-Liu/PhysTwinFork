#!/usr/bin/env bash
set -euo pipefail

# ---------- Blackwell / RTX 50xx: 架构固定为 SM 12.0 ----------
export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-12.0}"

echo "[step] ensure base tooling"
python -m pip install -U pip setuptools wheel packaging ninja cmake

echo "[step] basic python deps"
conda install -y numpy==1.26.4
pip install warp-lang
pip install usd-core matplotlib
pip install "pyglet<2"
pip install open3d
pip install trimesh
pip install rtree 
pip install pyrender

echo "[step] pin torch/cu128 exactly (match flash-attn)"
pip3 install \
  torch==2.7.0+cu128 \
  torchvision==0.22.0+cu128 \
  torchaudio==2.7.0 \
  --index-url https://download.pytorch.org/whl/cu128

pip install stannum termcolor fvcore wandb moviepy imageio
conda install -y opencv
pip install cma

echo "[step] realsense stack"
pip install Cython pyrealsense2 atomics pynput

echo "[step] grounded-sam-2 (+checkpoints, idempotent)"
if [ -d Grounded-SAM-2/.git ]; then
  git -C Grounded-SAM-2 pull --ff-only || true
else
  git clone https://github.com/IDEA-Research/Grounded-SAM-2.git
fi
bash Grounded-SAM-2/checkpoints/download_ckpts.sh || true
bash Grounded-SAM-2/gdino_checkpoints/download_ckpts.sh || true

# 安装 SAM-2 主包
pip install -e Grounded-SAM-2

# 关键修复：grounding_dino 用“非隔离 + 兼容可编辑”安装；失败则兜底 legacy develop
python -m ensurepip --upgrade || true
python -m pip install -U pip setuptools wheel packaging
if ! PIP_NO_BUILD_ISOLATION=1 \
     pip install -e Grounded-SAM-2/grounding_dino \
       --config-settings editable_mode=compat \
       --no-build-isolation; then
  echo "[warn] grounding_dino PEP517 editable failed; falling back to legacy develop"
  pushd Grounded-SAM-2/grounding_dino >/dev/null
  python setup.py develop || true
  popd >/dev/null
fi

echo "[step] SDXL upscaler deps"
pip install diffusers accelerate

echo "[step] gaussian splatting submodules (idempotent + torch2.7 fix)"

# 先安装纯 Python 依赖
pip install gsplat==1.4.0
pip install kornia

# ---------- 在构建 dgr 之前：补 include，防止 uintptr_t/uint32_t 等未定义 ----------
# 如果你有独立的 fixups 脚本，也可以在这里先执行
if [ -x ./env_install/post_patch_fixups.sh ]; then
  echo "[step] post_patch_fixups (cstdint include + libstdc++.so.6 symlink)"
  bash ./env_install/post_patch_fixups.sh || true
else
  # 幂等地在头文件首部插入 <cstdint>/<cinttypes>
  sed -i '1{/^#include <cstdint>/!s/^/#include <cstdint>\n/}' \
    gaussian_splatting/submodules/diff-gaussian-rasterization/cuda_rasterizer/rasterizer_impl.h || true
  sed -i '1{/^#include <cinttypes>/!s/^/#include <cinttypes>\n/}' \
    gaussian_splatting/submodules/diff-gaussian-rasterization/cuda_rasterizer/rasterizer_impl.h || true
fi

# ---------- diff-gaussian-rasterization: 适配 Torch 2.7 C++ API ----------
pushd gaussian_splatting/submodules/diff-gaussian-rasterization/ >/dev/null

# .data<T>() -> .data_ptr<T>()（幂等替换）
find . -type f \( -name "*.cu" -o -name "*.cpp" -o -name "*.cuh" -o -name "*.h" \) \
  -exec sed -i 's/\.data<\([^>]*\)>()/.data_ptr<\1>()/g' {} +

# 指定算力并构建（继承上面的 TORCH_CUDA_ARCH_LIST=12.0）
TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST" python setup.py build_ext --inplace
PIP_NO_BUILD_ISOLATION=1 pip install -e . --config-settings editable_mode=compat --no-build-isolation
popd >/dev/null

# simple-knn
pushd gaussian_splatting/submodules/simple-knn/ >/dev/null
PIP_NO_BUILD_ISOLATION=1 pip install -e . --config-settings editable_mode=compat --no-build-isolation
popd >/dev/null

pip install plyfile

echo "[step] pytorch3d (idempotent)"
if [ -d pytorch3d/.git ]; then
  git -C pytorch3d pull --ff-only || true
else
  git clone https://github.com/facebookresearch/pytorch3d.git
fi
# pytorch3d 里有部分 CUDA 扩展，确保也拿到正确的算力
TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST" \
PIP_NO_BUILD_ISOLATION=1 \
pip install -e pytorch3d --config-settings editable_mode=compat --no-build-isolation

pip install einops

echo "[step] TRELLIS (idempotent, with extras)"
mkdir -p data_process
if [ -d data_process/TRELLIS/.git ]; then
  git -C data_process/TRELLIS pull --recurse-submodules --ff-only || true
else
  git clone --recurse-submodules https://github.com/microsoft/TRELLIS.git data_process/TRELLIS
fi
bash data_process/TRELLIS/setup.sh \
  --basic --xformers --flash-attn --diffoctreerast --spconv --mipgaussian --kaolin --nvdiffrast || true

echo "[step] flash-attn pinned build (most reliable; match torch==2.7.0+cu128)"
if ! python -c "import flash_attn" 2>/dev/null; then
  pip install "flash-attn==2.7.4.post1" --no-build-isolation -v || {
    echo "[warn] flash-attn build failed; trying source fallback"
    rm -rf /tmp/flash-attention || true
    git clone https://github.com/Dao-AILab/flash-attention.git /tmp/flash-attention
    pushd /tmp/flash-attention >/dev/null
    git checkout v2.7.4.post1
    TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST" pip install -v --no-build-isolation .
    popd >/dev/null
  }
fi

echo "[step] quick smoke (non-fatal)"
python - <<'PY' || true
import sys, subprocess as sp, torch
print("python:", sys.version.split()[0])
print("torch:", torch.__version__, "cuda:", torch.version.cuda, "avail:", torch.cuda.is_available())
try: print("device cc =", torch.cuda.get_device_capability())
except Exception as e: print("get_device_capability err:", e)
for mod in ["flash_attn","pytorch3d","diff_gaussian_rasterization","simple_knn","cv2"]:
  try: __import__(mod); print(f"[OK] {mod}")
  except Exception as e: print(f"[WARN] {mod} -> {e}")
print(sp.check_output("nvcc --version || true", shell=True, text=True))
PY

echo "[done] 50xx env install complete."
