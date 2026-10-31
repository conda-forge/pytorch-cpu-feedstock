#!/bin/bash
# What pytorch's MPS kernels need from the Metal compiler and the macOS SDK.
#
# The probes below repeat the calls the kernels make, with the flags the build
# uses. It matters to run them, as nothing else stops the build early: pytorch
# guards this code with __has_include, so an SDK that lacks it gives a package
# that compiles but has no accelerated kernels. Runs in seconds, and needs only
# macOS and Xcode:
#
#     [SDKROOT=/path/to/MacOSX26.5.sdk] bash check_metal_requirements.sh
#
# The compiler comes from the active Xcode or Metal Toolchain, not from the SDK.
# The SDK supplies MetalPerformancePrimitives, and `xcrun metal` finds it through
# SDKROOT or else in the active Xcode.
set -u

workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT
failures=0

report() {  # report <0 for pass> <requirement> [details file]
    if [[ $1 -eq 0 ]]; then
        echo "PASS: $2"
    else
        echo "FAIL: $2"
        failures=$((failures + 1))
        if [[ -n "${3:-}" ]]; then
            grep -m 3 'error' "$3" | sed "s#${workdir}/##; s/^/      /"
        fi
    fi
}

probe() {  # probe <name> <requirement> [metal flags...], with the source on stdin
    local name=$1 requirement=$2
    shift 2
    cat > "${workdir}/${name}.metal"
    xcrun metal -c "${workdir}/${name}.metal" -o "${workdir}/${name}.air" -fno-fast-math "$@" \
        2> "${workdir}/${name}.log"
    report $? "${requirement}" "${workdir}/${name}.log"
}

target_of() {
    strings -a "$1" 2> /dev/null | grep -oE 'apple-macosx[0-9.]+' | sort -u
}

metal_40=(-std=metal4.0 -mmacos-version-min=26.2)
sdk=${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path 2> /dev/null)}
echo "SDK: ${sdk}, version $(plutil -extract Version raw "${sdk}/SDKSettings.plist" 2> /dev/null)"
xcrun metal --version 2>&1 | head -n 1
xcrun metal --version > /dev/null 2>&1
report $? "the metal compiler runs (Xcode with the Metal Toolchain component)"

# The fallback kernels, used before macOS 26.2 and on virtual GPUs. pytorch sets
# no target here, so the compiler takes MACOSX_DEPLOYMENT_TARGET, or else the host.
MACOSX_DEPLOYMENT_TARGET=12.0 probe metal_31 "-std=metal3.1 compiles" -std=metal3.1 <<'EOF'
kernel void probe(device bfloat* p, uint i [[thread_position_in_grid]]) { p[i] += 1; }
EOF
[[ "$(target_of "${workdir}/metal_31.air")" == "apple-macosx14.0.0" ]]
report $? "fallback kernels honour MACOSX_DEPLOYMENT_TARGET, and target macOS 14.0"

probe metal_40 "-std=metal4.0 -mmacos-version-min=26.2 compiles" "${metal_40[@]}" <<'EOF'
kernel void probe(device float* p, uint i [[thread_position_in_grid]]) {
  auto fn = [](float x) { return x + 1.0; };
  p[i] = fn(p[i]);
}
EOF
[[ "$(target_of "${workdir}/metal_40.air")" == "apple-macosx26.2.0" ]]
report $? "Metal 4 kernels target macOS 26.2"

probe header "the SDK has MetalPerformancePrimitives.h and metal_cooperative_tensor" "${metal_40[@]}" <<'EOF'
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
#include <metal_cooperative_tensor>
EOF

# LinearAlgebra.metal: cholesky, solve, inv, lu_factor
probe linalg "matmul2d on tensors, with a destination cooperative tensor (linear algebra)" "${metal_40[@]}" <<'EOF'
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
using namespace metal;
kernel void probe(device float* a [[buffer(0)]], constant int& n [[buffer(1)]]) {
  constexpr auto desc = mpp::tensor_ops::matmul2d_descriptor(
      32, 64, static_cast<int>(dynamic_extent), false, true, false,
      mpp::tensor_ops::matmul2d_descriptor::mode::multiply);
  mpp::tensor_ops::matmul2d<desc, execution_simdgroups<2>> op;
  tensor<device float, dextents<int32_t, 2>, tensor_inline> t(
      a, dextents<int32_t, 2>(n, n), array<int32_t, 2>{1, n});
  auto left = t.template slice<dynamic_extent, 32>(0, 0);
  auto right = t.template slice<dynamic_extent, 64>(0, 0);
  auto out = t.template slice<64, 32>(0, 0);
  auto c = op.template get_destination_cooperative_tensor<decltype(left), decltype(right), float>();
  op.run(left, right, c);
  c.store(out);
}
EOF

# Convolution.metal: conv1d, conv2d, conv3d
probe convolution "convolution2d, with a destination cooperative tensor (convolution)" "${metal_40[@]}" <<'EOF'
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
#include <metal_cooperative_tensor>
using namespace metal;
using namespace mpp::tensor_ops;
kernel void probe(device float* a [[buffer(0)]], device float* w [[buffer(1)]], constant int& n [[buffer(2)]]) {
  constexpr auto desc = convolution2d_descriptor(
      int4(32, 8, 8, 1), int4(4, 16, 16, 1), int2(3, 3),
      convolution2d_activation_layout::nhwc, convolution2d_weights_layout::hwio,
      int2(1, 1), int2(1, 1), 1, true, convolution2d_descriptor::mode::multiply_accumulate);
  convolution2d<desc, execution_simdgroups<2>> op;
  op.set_offsets(int2(0, 0));
  tensor<device float, dextents<int32_t, 4>, tensor_inline> tw(w, dextents<int32_t, 4>(n, n, 3, 3));
  tensor<device float, dextents<int32_t, 4>, tensor_inline> ta(a, dextents<int32_t, 4>(n, n, n, 1));
  auto ma = ta.slice(0, 0, 0, 0);
  auto mw = tw.slice(0, 0, 0, 0);
  auto c = op.template get_destination_cooperative_tensor<decltype(ma), decltype(mw), float>();
  for (uint16_t i = 0; i < c.get_capacity(); ++i) {
    c[i] = 0.0f;
  }
}
EOF

# MppAttention.h: scaled_dot_product_attention. This is the one that needs SDK
# 26.2: these two input accessors are missing from 26.1, which has the framework.
for dtype in half bfloat; do
    probe "attention_${dtype}" "matmul2d left and right input cooperative tensors, ${dtype} (attention)" "${metal_40[@]}" <<EOF
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
using namespace metal;
kernel void probe(device float* p [[buffer(0)]]) {
  constexpr auto desc = mpp::tensor_ops::matmul2d_descriptor(
      16, 32, 16, false, true, true,
      mpp::tensor_ops::matmul2d_descriptor::mode::multiply_accumulate);
  mpp::tensor_ops::matmul2d<desc, execution_simdgroup> op;
  auto a = op.template get_left_input_cooperative_tensor<${dtype}, ${dtype}, float>();
  auto b = op.template get_right_input_cooperative_tensor<${dtype}, ${dtype}, float>();
  auto c = op.template get_destination_cooperative_tensor<decltype(a), decltype(b), float>();
  a[0] = ${dtype}(p[0]);
  b[0] = ${dtype}(p[1]);
  op.run(a, b, c);
  p[2] = c[0];
}
EOF
done

xcrun metallib -o "${workdir}/probe.metallib" "${workdir}/attention_bfloat.air" 2> "${workdir}/metallib.log"
report $? "metallib links the Metal 4 kernels" "${workdir}/metallib.log"

if [[ ${failures} -ne 0 ]]; then
    echo "${failures} Metal requirement(s) not met: pytorch needs a compiler that takes -std=metal4.0 and an SDK >=26.2"
    exit 1
fi
echo "All Metal requirements met"
