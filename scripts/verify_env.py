# varify the env install

import os, sys, subprocess
def sh(cmd): 
    try: 
        return subprocess.check_output(cmd, shell=True, text=True).strip()
    except Exception as e:
        return f"[ERR] {e}"

print("Python:", sys.version)
try:
    import torch
    print("Torch:", torch.__version__, "| CUDA:", torch.version.cuda, "| torch.cuda.is_available:", torch.cuda.is_available())
except Exception as e:
    print("Torch import failed:", e)

print("nvcc:", sh("nvcc --version || true"))
print("nvidia-smi:", sh("nvidia-smi || true"))

# check if the headfile of diff-gaussian-rasterization has changed
hdr = "gaussian_splatting/submodules/diff-gaussian-rasterization/cuda_rasterizer/rasterizer_impl.h"
if os.path.exists(hdr):
    with open(hdr, 'r') as f:
        head = ''.join([next(f) for _ in range(10)])
    print("#include <cstdint> present:", "#include <cstdint>" in head)
else:
    print("Header not found:", hdr)
