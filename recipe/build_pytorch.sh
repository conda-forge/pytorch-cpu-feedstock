set -x
source $RECIPE_DIR/build.sh

# if $SP_DIR/torch doesn't exist here, the installation
# of pytorch (see build_libtorch.sh call above) failed
pushd $SP_DIR/torch

# Make symlinks for libraries and headers from libtorch into $SP_DIR/torch
# Also remove the vendorered libraries they seem to include
# https://github.com/conda-forge/pytorch-cpu-feedstock/issues/243
# https://github.com/pytorch/pytorch/blob/v2.3.1/setup.py#L341
for f in bin/* lib/* share/* include/*; do
  if [[ -e "$PREFIX/$f" ]]; then
    rm -rf $f
    ln -sf $PREFIX/$f $PWD/$f
  fi
done
