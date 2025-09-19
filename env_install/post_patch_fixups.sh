#!/usr/bin/env bash
# Open gaussian_splatting/submodules/diff-gaussian-rasterization/cuda_rasterizer/rasterizer_impl.h and add an include directive for cstdint
# Forcefully create a symbolic soft link between system libstdc++.so.6 and conda environment libstdc++.so.6 e.g. `ln -sf /usr/lib/x86_64-linux-gnu/libstdc++.so.6 {CONDA_PATH}/envs/phystwin/bin/../lib/libstdc++.so.6`
set -euo pipefail

# 1) add #include <cstdint> for rasterizer_impl.h
RFILE="gaussian_splatting/submodules/diff-gaussian-rasterization/cuda_rasterizer/rasterizer_impl.h"
if [ -f "$RFILE" ] && ! grep -q "^\s*#include <cstdint>" "$RFILE"; then
  sed -i '1i #include <cstdint>' "$RFILE"
  echo "[fixups] Inserted #include <cstdint> into $RFILE"
fi

# 2) libstdc++.so.6 soft link to conda env
#   （some PyTorch/cuda may need higher libstdc++ ver）
CONDA_LIB="$(python - <<'PY'
import sys,os
print(os.path.join(os.path.dirname(sys.executable),'..','lib'))
PY
)"
SYS_LIB="/usr/lib/x86_64-linux-gnu/libstdc++.so.6"
if [ -e "$SYS_LIB" ] && [ -d "$CONDA_LIB" ]; then
  ln -sf "$SYS_LIB" "$CONDA_LIB/libstdc++.so.6"
  echo "[fixups] Symlinked system libstdc++.so.6 -> $CONDA_LIB/libstdc++.so.6"
fi

# 3) debug
echo "[fixups] nvcc:"
nvcc --version || true
echo "[fixups] gcc:"
gcc --version || true
