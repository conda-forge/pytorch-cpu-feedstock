#!/bin/bash
# Check the Metal libraries in libtorch_cpu.dylib: pytorch drops the accelerated
# kernels without an error if it cannot compile them, and virtualized CI GPUs take
# the fallback path, so a runtime test on CI would not notice.
#
#     bash check_metal_kernels.sh /path/to/libtorch_cpu.dylib
set -eu

workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT
xcrun segedit "$1" -extract __TEXT metal_basic "${workdir}/basic.metallib" \
    -extract __TEXT metal_40 "${workdir}/40.metallib"

check_target() {  # check_target <metallib> <macOS version>
    targets=$(LC_ALL=C grep -aoE 'apple-macosx[0-9.]+' "$1" | sort -u)
    if [[ "${targets}" != "apple-macosx$2" ]]; then
        echo "FAIL: ${1##*/} should target only macOS $2, found: ${targets}"
        exit 1
    fi
    echo "PASS: ${1##*/} targets macOS $2"
}

check_kernel() {  # check_kernel <name> <operation>
    if ! LC_ALL=C grep -aq "$1" "${workdir}/40.metallib"; then
        echo "FAIL: metal_40 has no $1 kernels, for $2"
        exit 1
    fi
    echo "PASS: metal_40 has $1 kernels, for $2"
}

check_target "${workdir}/basic.metallib" 14.0.0
check_target "${workdir}/40.metallib" 26.2.0
check_kernel prefill_attention_mpp_a10_bfloat16 "attention on M5"
check_kernel prefill_attention_mpp_a9_float16 "attention on M4"
check_kernel applySYRKTrailingL "cholesky"
check_kernel gemmLU "solve, inv and lu_factor"
check_kernel conv3d_mpp_bfloat "convolution"
