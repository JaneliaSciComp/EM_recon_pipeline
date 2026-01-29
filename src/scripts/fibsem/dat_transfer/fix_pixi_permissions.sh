#!/bin/bash

# This script fixes permissions within the pixi fibsem environment
# so that users other than fibsemxfer can use commands like:
#
#   pixi run --manifest-path ${EMRP_ROOT}/pyproject.toml --environment fibsem --frozen python
#
# without getting 'failed to collect prefix records from ... Permission denied ...' errors

FIBSEMXFER_DIR="/groups/fibsem/home/fibsemxfer"
EMRP_ROOT="${FIBSEMXFER_DIR}/git/EM_recon_pipeline"
PIXI_FIBSEM_CONDA_META_DIR="${EMRP_ROOT}/.pixi/envs/fibsem/conda-meta"

# make library json files group readable (the rattler/libconda stack used by pixi makes these 600 by default)
chmod g+r ${PIXI_FIBSEM_CONDA_META_DIR}/*.json

# make history file group read/write (pixi makes this 640 by default, but it needs to be group writable for some reason)
chmod g+rw ${PIXI_FIBSEM_CONDA_META_DIR}/history