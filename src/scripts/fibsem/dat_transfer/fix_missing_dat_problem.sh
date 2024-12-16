#!/bin/bash

set -e

umask 0002

NUM_WORKERS="1"

#TRANSFER_INFO="/groups/flyem/home/flyem/bin/dat_transfer/2022/config/volume_transfer_info.jrc_pri_neuron_0710Dish4.json"
#PARENT_WORK_DIR="/groups/fibsem/fibsem/data/jrc_pri-neuron_0710Dish4/dat/logs/fix"
#FIRST_DAT="Merlin-6285_24-09-24_093827_0-0-0.dat"
#LAST_DAT="Merlin-6285_24-09-24_094238_0-0-0.dat"

TRANSFER_INFO="/groups/fibsem/home/fibsemxfer/git/EM_recon_pipeline/src/resources/transfer_info/cellmap/volume_transfer_info.jrc_mus-cerebellum-2.json"
PARENT_WORK_DIR="/groups/cellmap/cellmap/data/jrc_mus-cerebellum-2/dat/logs/fix"
FIRST_DAT="Merlin-6257_24-07-19_134020_0-0-0.dat"
LAST_DAT="Merlin-6257_24-08-13_113522_0-0-3.dat"

mkdir -p ${PARENT_WORK_DIR}

RUN_DATE_AND_TIME=$(date +"%Y%m%d_%H%M%S")

FIBSEMXFER_DIR="/groups/fibsem/home/fibsemxfer"
EMRP_ROOT="${FIBSEMXFER_DIR}/git/EM_recon_pipeline"

source ${FIBSEMXFER_DIR}/bin/source_miniforge3.sh

conda activate janelia_emrp

# need this to avoid errors from dask
export OPENBLAS_NUM_THREADS=1

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/dat_converter.py"
ARGS="${ARGS} --volume_transfer_info ${TRANSFER_INFO}"
ARGS="${ARGS} --num_workers ${NUM_WORKERS}"
ARGS="${ARGS} --parent_work_dir ${PARENT_WORK_DIR}"
ARGS="${ARGS} --first_dat ${FIRST_DAT}"
ARGS="${ARGS} --last_dat ${LAST_DAT}"
ARGS="${ARGS} --force"

echo """
On ${HOSTNAME} at ${RUN_DATE_AND_TIME}

Running:
  python ${ARGS}
"""

# The exit status of a pipeline is the exit status of the last command in the pipeline,
# unless the pipefail option is enabled (see The Set Builtin).
# If pipefail is enabled, the pipeline's return status is the value of the last (rightmost) command
# to exit with a non-zero status, or zero if all commands exit successfully.
set -o pipefail

python ${ARGS} 2>&1
RETURN_CODE="$?"

echo "python return code is ${RETURN_CODE}"
exit ${RETURN_CODE}
