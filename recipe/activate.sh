#!/bin/bash

if [[ ! -v CF_TORCH_CUDA_ARCH_LIST ]]
then
    export CF_TORCH_CUDA_ARCH_LIST="@cf_torch_cuda_arch_list@"
    # "NOT_SET" is used as the value because it is clearer (explicit) that the activation
    # script was run and found no previous value for "CF_TORCH_CUDA_ARCH_LIST".
    export CF_TORCH_CUDA_ARCH_LIST_BACKUP="NOT_SET"
fi
