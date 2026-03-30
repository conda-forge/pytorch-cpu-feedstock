"""Write $PREFIX/etc/conda/env_vars.d/libtorch.json with build-time env vars."""
import json
import os
import pathlib

prefix = os.environ["PREFIX"]
torch_cuda_arch_list = os.environ["TORCH_CUDA_ARCH_LIST"]

env_vars_d = pathlib.Path(prefix) / "etc" / "conda" / "env_vars.d"
env_vars_d.mkdir(parents=True, exist_ok=True)

output = {"CF_TORCH_CUDA_ARCH_LIST": torch_cuda_arch_list}
(env_vars_d / "libtorch.json").write_text(json.dumps(output, indent=2))
print(f"Wrote {env_vars_d / 'libtorch.json'}: {output}")
