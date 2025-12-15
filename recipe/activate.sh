#!/bin/bash

if [[ ! -v CF_TORCH_CUDA_ARCH_LIST ]]
then
    export CF_TORCH_CUDA_ARCH_LIST="@cf_torch_cuda_arch_list@"
    export CF_TORCH_CUDA_ARCH_LIST_BACKUP="NOT_SET"
fi
