#!/usr/env/bin bash

set -ex

docker system prune --force
configs=$(find .ci_support/ -type f -name '*mkl*cuda_compiler_version[^nN]*' -printf "%p ")

# Assuming a powerful enough machine with many cores
# 10 seems to be a good point where things don't run out of RAM too much.
export CPU_COUNT=10

mkdir -p build_artifacts

for config_filename in $configs; do
    filename=$(basename ${config_filename})
    config=${filename%.*}
    if [ -f build_artifacts/conda-forge-build-done-${config} ]; then
        echo skipped $config
        continue
    fi

    python build-locally.py $config | tee build_artifacts/${config}-log.txt
    # docker images get quite big clean them up after each build to save your disk....
    docker system prune --force
done

zip build_artifacts/log_files.zip build_artifacts/*-log.txt
