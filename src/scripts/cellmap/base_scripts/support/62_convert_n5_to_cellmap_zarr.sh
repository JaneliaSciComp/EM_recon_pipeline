#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/../00_config.sh

# shellcheck source=???
source "${SOURCE_MINIFORGE3_SCRIPT}"

conda activate cellmap-n5-to-zarr

cd /groups/fibsem/home/fibsemxfer/git/cellmap-n5-to-zarr

# shellcheck disable=SC2086
# shellcheck disable=SC2048
# shellcheck disable=SC2086
python src/to_cellmap_zarr.py $*