#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
CONFIG_SCRIPT=$(readlink -m "${SCRIPT_DIR}"/../00_config.sh)
source "${CONFIG_SCRIPT}"

# shellcheck source=???
source "${SOURCE_MINIFORGE3_SCRIPT}"

conda activate cellmap-n5-to-zarr

GITHUB_DIR="/groups/fibsem/home/fibsemxfer/git/cellmap-n5-to-zarr"

# need this to avoid module not found errors
export PYTHONPATH="${GITHUB_DIR}"

echo "
Host:              ${HOSTNAME}
Working Directory: ${PWD}
Config Script:     ${CONFIG_SCRIPT}

Miniforge Script:  ${SOURCE_MINIFORGE3_SCRIPT}
Conda Environment: ${CONDA_DEFAULT_ENV}

Running:
  python to_cellmap_zarr.py $*
"

# shellcheck disable=SC2086
# shellcheck disable=SC2048
# shellcheck disable=SC2086
python ${GITHUB_DIR}/src/to_cellmap_zarr.py $*