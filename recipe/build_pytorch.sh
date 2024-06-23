set -x
# https://github.com/conda-forge/pytorch-cpu-feedstock/issues/243
# https://github.com/pytorch/pytorch/blob/v2.3.1/setup.py#L341
export PACKAGE_TYPE=conda

if [[ "$megabuild" == true ]]; then
  source $RECIPE_DIR/build.sh
  # if $SP_DIR/torch doesn't exist here, the installation
  # of pytorch (see build_libtorch.sh call above) failed
  pushd $SP_DIR/torch
  for f in bin/* lib/* share/* include/*; do
    if [[ -e "$PREFIX/$f" ]]; then
      rm -rf $f
      ln -sf $PREFIX/$f $PWD/$f
    fi
  done
else
  $PREFIX/bin/python -m pip install --no-deps --no-cache-dir torch-*.whl
fi
