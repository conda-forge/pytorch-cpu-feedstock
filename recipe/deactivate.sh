#!/bin/bash

if [[ "${CF_TORCH_CUDA_ARCH_LIST_BACKUP}" == "NOT_SET" ]]
then
  unset CF_TORCH_CUDA_ARCH_LIST
  unset CF_TORCH_CUDA_ARCH_LIST_BACKUP
fi
