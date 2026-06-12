#!/usr/bin/env python
"""Run the conda-forge subset of PyTorch's test suite.

This replaces the giant ``{% set skips %}`` Jinja block that used to live in
``meta.yaml``. The whole point is readability: the list of test files and the
list of skipped tests are plain Python data, and every platform selector that
used to be a ``# [aarch64]`` / ``# [osx and arm64]`` comment is now an ordinary
boolean expression next to the entry it guards.

The recipe passes the build variant through environment variables (set via
rattler-build interpolation in the test ``script.env``):

* ``PYTORCH_VARIANT_TARGET_PLATFORM`` -> e.g. ``linux-64``, ``osx-arm64``
* ``PYTORCH_VARIANT_BLAS``            -> ``mkl`` or ``generic``
* ``PYTORCH_VARIANT_CUDA``            -> ``None`` or e.g. ``12.9`` / ``13.0``

When those are absent (e.g. running this script by hand), we fall back to
detecting the flavor from the interpreter and from ``torch`` itself.
"""

from __future__ import annotations

import os
import platform
import subprocess
import sys

import torch

# --------------------------------------------------------------------------- #
# Resolve the platform / build flavor we are testing -- from the variant env
# vars the recipe passes in, falling back to runtime detection.
# --------------------------------------------------------------------------- #
py = f"{sys.version_info.major}.{sys.version_info.minor}"

target_platform = os.environ.get("PYTORCH_VARIANT_TARGET_PLATFORM", "")
blas_impl = os.environ.get("PYTORCH_VARIANT_BLAS", "")
cuda_version = os.environ.get("PYTORCH_VARIANT_CUDA", "")

if target_platform:
    linux = target_platform.startswith("linux")
    osx = target_platform.startswith("osx")
    win = target_platform.startswith("win")
    aarch64 = target_platform == "linux-aarch64"
    arm64 = target_platform == "osx-arm64"
    x86_64 = target_platform in ("linux-64", "osx-64", "win-64")
else:
    _machine = platform.machine().lower()
    linux = sys.platform.startswith("linux")
    osx = sys.platform == "darwin"
    win = sys.platform.startswith("win")
    aarch64 = linux and _machine in ("aarch64", "arm64")
    arm64 = osx and _machine in ("arm64", "aarch64")
    x86_64 = _machine in ("x86_64", "amd64")

unix = linux or osx
linux64 = linux and x86_64

if cuda_version:
    cuda = cuda_version not in ("None", "")
    cuda_13 = cuda_version.startswith("13")
else:
    cuda = torch.version.cuda is not None
    cuda_13 = cuda and torch.version.cuda.startswith("13")

mkl = (blas_impl == "mkl") if blas_impl else torch.backends.mkl.is_available()

print(
    "run_pytorch_tests: "
    f"target_platform={target_platform or '(detected)'} "
    f"py={py} blas={'mkl' if mkl else 'generic'} cuda={cuda_version or torch.version.cuda}",
    flush=True,
)

# --------------------------------------------------------------------------- #
# Which test files to run.
#
# The whole suite takes forever; this fixed subset gives good coverage for
# packaging problems. torch.compile (inductor) tests are expensive and only run
# on one python version on x86 desktop platforms (never under aarch emulation
# or on macOS).
# --------------------------------------------------------------------------- #
TEST_FILES = [
    "test/test_autograd.py",
    "test/test_autograd_fallback.py",
    "test/test_custom_ops.py",
    "test/test_linalg.py",
    "test/test_mkldnn.py",
    "test/test_modules.py",
    "test/test_nn.py",
    "test/test_torch.py",
    "test/test_xnnpack_integration.py",
]
if py == "3.12" and not (aarch64 or osx):
    TEST_FILES.append("test/inductor/test_torchinductor.py")

# --------------------------------------------------------------------------- #
# Tests to skip, as (pytest -k expression fragment, include?) pairs.
#
# Each fragment is OR-ed together into a single ``-k "not (...)"`` expression,
# exactly like the old Jinja concatenation -- but here the second element is a
# plain boolean so the platform gating reads top-to-bottom.
# --------------------------------------------------------------------------- #
SKIPS: list[tuple[str, bool]] = [
    ("(TestTorch and test_print)", True),
    # downloads a legacy module from download.pytorch.org; fails on network/SSL flakes
    ("(TestNN and test_module_backcompat)", True),
    # minor tolerance violations
    ("test_1_sized_with_0_strided_cpu_float32", osx),
    ("test_batchnorm_nhwc_cpu", unix),
    ("test_layer_norm_backwards_eps", unix),
    # onednn errors ("unsupported {isa, datatype, datatype combination, sparse md configuration}")
    ("test__int4_mm_m", aarch64),
    ("test_lstm_cpu", aarch64),
    ("test_remove_no_ops_cpu", aarch64),
    ("test_weight_norm_bwd_cpu", aarch64),
    # ... onednn errors for float16 (group of matmul/conv kernels)
    (
        "(_cpu_float16 and ("
        "test_activations_bfloat16_half_cpu or test_addbmm or test_addmm or test_addmv"
        " or test_baddbmm or test_bmm or test_conv_deconv or test_conv_nhwc_lower_precision"
        " or test_conv_transpose_nhwc_lower_precision or test_dot_vs_numpy"
        " or test_grouped_mm_cpu_unaligned or test_linear_lowp or test_matmul_lower_precision))",
        aarch64,
    ),
    # ... onednn errors for complex32 (ConvTranspose modules)
    (
        "(_cpu_complex32 and ("
        "test_forward_nn_ConvTranspose or test_if_train_and_eval_modes_differ_nn_ConvTr"
        " or test_memory_format_nn_ConvTranspose1d or test_non_contiguous_tensors_nn_ConvTranspo"
        " or test_save_load_nn_ConvTranspose))",
        aarch64,
    ),
    # timeouts and failures on aarch, see
    # https://github.com/conda-forge/pytorch-cpu-feedstock/pull/298#issuecomment-2555888508
    ("test_pynode_destruction_deadlock", aarch64),
    ("(TestLinalgCPU and test_cholesky_cpu_float32)", aarch64),
    ("(TestLinalgCPU and test_pca_lowrank_cpu)", aarch64),
    ("(TestLinalgCPU and test_svd_lowrank_cpu)", aarch64),
    ("(TestMkldnnCPU and test_lstm_cpu)", aarch64),
    # very long-running tests in emulation
    ("test_eigh_lwork_lapack", aarch64),
    ("test_gradgrad_nn_LSTM", aarch64),
    ("test_grad_nn_Transformer", aarch64),
    ("test_inverse_errors_large", aarch64),
    ("(TestXNNPACKConv1dTransformPass and test_conv1d_basic)", aarch64),
    # gross cholesky reconstruction error on aarch64 (openblas/QEMU)
    ("(TestLinalgCPU and test_cholesky_upper_reconstructs_cpu_float32)", aarch64),
    # debug=True checkpoint path raises ValueError: stoi from C++ traceback symbolization
    ("(TestAutograd and test_checkpoint_detects_non_determinism)", aarch64),
    # doesn't crash, but gets different result on aarch + CUDA
    ("illcondition_matrix_input_should_not_crash_cpu", aarch64 and cuda),
    # may crash spuriously
    ("(TestAutograd and test_profiler_seq_nr)", True),
    ("(TestAutograd and test_profiler_propagation)", True),
    # tests that fail due to resource clean-up issues (non-unique temporary libraries), see
    # https://github.com/conda-forge/pytorch-cpu-feedstock/pull/318#issuecomment-2620080859
    ("test_mutable_custom_op_fixed_layout", True),
    # minor inaccuracy on aarch64 (emulation?)
    ("(TestNN and test_upsampling_bfloat16)", aarch64),
    ("(TestLinalgCPU and test_qr_cpu_float32)", aarch64),
    # flaky failure: `Exec format error: '$PREFIX/bin/python3.12'`
    ("test_terminate_handler_on_crash", aarch64),
    # trivial accuracy problems (CUDA)
    ("test_BCELoss_weights_no_reduce_cuda", linux and cuda),
    ("test_ctc_loss_cudnn_tensor_cuda", linux and cuda),
    ("(TestTorch and test_index_add_correctness)", linux and cuda),
    # These tests require higher-resource or more recent GPUs than the CI provides
    ("test_sdpa_inference_mode_aot_compile", linux and cuda),
    ("(TestNN and test_grid_sample)", linux and cuda),
    # don't mess with tests that rely on GPU failure handling
    ("test_cublas_config_nondeterministic_alert_cuda", linux and cuda),
    ("test_cross_entropy_loss_2d_out_of_bounds_class", linux and cuda),
    ("test_indirect_device_assert", linux and cuda),
    ("test_reentrant_parent_error_on_cpu_cuda", linux and cuda),
    # test that fails to find temporary resource
    ("(GPUTests and test_scatter_reduce2)", linux and cuda),
    # ROCM test whose skip doesn't trigger
    ("test_ck_blas_library_cpu", linux and cuda),
    # problem with finding output of `torch.cuda.tunable.write_file()`
    ("test_matmul_offline_tunableop_cuda_float16", linux and cuda),
    # catastrophic accuracy failure in convolution
    ("test_Conv3d_1x1x1_no_bias_cuda", linux and cuda),
    # some triton errors that appeared in #391
    ("test_isinf_cuda", linux and cuda),
    ("test_donated_buffer_inplace_gpt", linux and cuda),
    ("test_linear_dynamic_maxautotune_cuda", linux and cuda),
    # skip some very long-running groups of tests (~30 minutes total)
    ("(test_gradgrad_nn_Transformer and _cuda_)", linux and cuda),
    ("test_avg_pool3d_backward2", linux and cuda),
    # MKL problems
    ("(TestLinalgCPU and test_inverse_errors_large_cpu)", linux and mkl and cuda),
    # non-MKL problems
    ("test_gather_scatter_cpu or test_index_put2_cpu", linux and not mkl and cuda),
    # these tests are failing with low -n values
    ("test_base_does_not_require_grad_mode_nothing", unix),
    ("test_base_does_not_require_grad_mode_warn", unix),
    ("test_composite_registered_to_cpu_mode_nothing", unix),
    # these tests are failing on windows
    ("(TestMkldnnCPU and test_batch_norm_2d_cpu)", win),
    # flaky test, fragile to GC behavior
    ("(TestTorch and test_tensor_cycle_via_slots)", True),
    # unexpected success
    ("test_forward_nn_Bilinear_mps_float16", arm64),
    # "quantized engine NoQEngine is not supported"
    ("test_qengine", arm64),
    # flaky failure on osx
    ("test_LayerNorm_numeric_mps", arm64),
    # precision errors (MPS / osx-arm64)
    ("test_forward_nn_Linear", arm64),
    ("test_forward_nn_TransformerEncoderLayer_train_mode_mps_float16", arm64),
    ("test_non_contiguous_tensors_nn_GRUCell_mps", arm64),
    ("test_non_contiguous_tensors_nn_GRU_eval_mode_mps", arm64),
    ("test_non_contiguous_tensors_nn_GRU_train_mode_mps", arm64),
    ("test_non_contiguous_tensors_nn_LSTMCell_mps", arm64),
    ("test_non_contiguous_tensors_nn_Linear_mps", arm64),
    ("test_non_contiguous_tensors_nn_MultiheadAttention_eval_mode_mps_float16", arm64),
    ("test_non_contiguous_tensors_nn_MultiheadAttention_train_mode_mps_float16", arm64),
    # MPS float16 precision deltas on newer Apple Silicon (skipped tactically for
    # robustness across macOS/hardware versions)
    ("test_non_contiguous_tensors_nn_TransformerDecoderLayer_mps_float16", arm64),
    ("test_non_contiguous_tensors_nn_TransformerEncoder_eval_mode_mps_float16", arm64),
    ("test_non_contiguous_tensors_nn_TransformerEncoder_train_mode_mps_float16", arm64),
    ("test_non_contiguous_tensors_nn_TransformerEncoderLayer_train_mode_mps_float16", arm64),
    ("test_non_contiguous_tensors_nn_RNNCell_mps", arm64),
    # MPS MultiheadAttention non-contiguous float32 precision deltas on osx-arm64 CI
    ("test_non_contiguous_tensors_nn_MultiheadAttention_train_mode_mps_float32", arm64),
    ("test_non_contiguous_tensors_nn_MultiheadAttention_eval_mode_mps_float32", arm64),
    ("test_non_contiguous_tensors_nn_RNN_eval_mode_mps", arm64),
    ("test_non_contiguous_tensors_nn_RNN_train_mode_mps", arm64),
    ("test_transformerencoderlayer_mps_float32", arm64),
    ("test_transformerencoderlayer_gelu_mps_float32", arm64),
    ("test_grad_nn_MultiheadAttention_eval_mode_cpu_float64", arm64),
    ("test_non_contiguous_tensors_nn_CrossEntropyLoss_mps_float32", arm64),
    # some warning-related failure, maybe it's broken by --disable-warnings?
    ("test_cpp_warnings_have_python_context_cpu", True),
    ("test_cpp_warnings_have_python_context_cuda", True),
    # "Attempt to trace generator"
    ("test_lite_regional_compile_flex_attention_cuda", True),
    # Regressions in 2.11.0 (windows + CUDA 13.0)
    ("test_compile_dyn_quant_matmul_4bit", win and cuda_13),
    ("test__int8_mm_m", win and cuda_13),
    ("test_pdist_cuda_gradgrad_unimplemented", win and cuda_13),
    ("test_inverse_errors_large_cpu", win and cuda_13),
    ("test_torchinductor", win and cuda_13),
    ("test_eigh_svd_illcondition_matrix_input_should_not_crash_cpu_float32", aarch64),
]


def main() -> int:
    # test only one python version on aarch because emulation is super-slow
    if aarch64 and py != "3.12":
        print(f"run_pytorch_tests: skipping suite on aarch64 for py{py} (only py3.12 runs).")
        return 0

    os.environ["OMP_NUM_THREADS"] = "4"
    os.environ["ONEDNN_VERBOSE"] = "all"

    skip_expr = " or ".join(expr for expr, include in SKIPS if include)

    # reduced parallelism to avoid OOM for CUDA builds
    jobs = ["-n", "1"] if (linux64 and cuda) else ["-n", "2"]

    cmd = [
        sys.executable,
        "-m",
        "pytest",
        *jobs,
        *TEST_FILES,
        "-k",
        f"not ({skip_expr})",
        # disable hypothesis because it randomly yields health check errors
        "-m",
        "not hypothesis",
        "--durations=50",
        "--timeout=1200",
        "--disable-warnings",
        "--force-short-summary",
    ]
    print("run_pytorch_tests:", " ".join(cmd), flush=True)
    return subprocess.call(cmd)


if __name__ == "__main__":
    sys.exit(main())
