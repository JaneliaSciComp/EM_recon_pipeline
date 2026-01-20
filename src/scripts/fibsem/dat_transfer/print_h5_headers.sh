#!/bin/bash

if (( $# < 1 )); then
  echo "
USAGE: $0 <h5 path> [h5 path] ...
"
  exit 1
fi

FIBSEMXFER_DIR="/groups/fibsem/home/fibsemxfer"
EMRP_ROOT="${FIBSEMXFER_DIR}/git/EM_recon_pipeline"
PIXI_RUN="${FIBSEMXFER_DIR}/.pixi/bin/pixi run --manifest-path ${EMRP_ROOT}/pyproject.toml --enviornment janelia_emrp"

export PYTHONPATH="${EMRP_ROOT}/src/python"

# shellcheck disable=SC2086
# shellcheck disable=SC2048
${PIXI_RUN} ${EMRP_ROOT}/src/python/janelia_emrp/fibsem/print_h5_headers.py --h5_path $*