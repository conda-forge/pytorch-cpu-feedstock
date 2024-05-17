set -x
if [[ "$megabuild" == true ]]; then
  source $RECIPE_DIR/build_libtorch.sh
  mkdir -p $SP_DIR/torch
  pushd $SP_DIR/torch
  for f in bin/* lib/* share/* include/*; do
    if [[ -e "$PREFIX/$f" ]]; then
      rm -rf $f
      ln -sf $PREFIX/$f $PWD/$f
    fi
  done
else
  $PREFIX/bin/python -m pip install --no-deps torch-*.whl
fi
