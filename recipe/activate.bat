@echo on

if not defined CF_TORCH_CUDA_ARCH_LIST (
    set "CF_TORCH_CUDA_ARCH_LIST=@cf_torch_cuda_arch_list@"
    set "CF_TORCH_CUDA_ARCH_LIST_BACKUP=UNSET"
)

