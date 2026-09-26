@echo off

if not defined CF_TORCH_CUDA_ARCH_LIST (
    set "CF_TORCH_CUDA_ARCH_LIST=@cf_torch_cuda_arch_list@"
    @REM "NOT_SET" is used as the value because it is clearer (explicit) that the activation
    @REM script was run and found no previous value for "CF_TORCH_CUDA_ARCH_LIST".
    set "CF_TORCH_CUDA_ARCH_LIST_BACKUP=NOT_SET"
)

