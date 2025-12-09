#!/bin/bash

if [[ "${CF_TORCH_CUDA_ARCH_LIST_BACKUP}" == "UNSET" ]]
then
  unset CF_TORCH_CUDA_ARCH_LIST
  unset CF_TORCH_CUDA_ARCH_LIST_BACKUP
fi
