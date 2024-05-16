set -x
if [[ "$megabuild" == true ]]; then
  source $RECIPE_DIR/build.sh
  pushd $SP_DIR/torch
  for f in bin/* lib/* share/* include/*; do
    if [[ -e "$PREFIX/$f" ]]; then
      rm -rf $f
      ln -sf $PREFIX/$f $PWD/$f
    fi
  done
else
  %PYTHON% -m pip install --no-deps torch-*.whl
fi
