#!/bin/bash

set -e

umask 0002

NUM_WORKERS="1"

#TRANSFER_INFO="/groups/flyem/home/flyem/bin/dat_transfer/2022/config/volume_transfer_info.jrc_sepia_MPI-S-DEC_5A.json"
#PARENT_WORK_DIR="/groups/reiser/reiserlab/data/jrc_sepia_MPI-S-DEC_5A/dat/logs/fix"
#FIRST_DAT="Merlin-6285_24-05-13_161357_0-0-0.dat"
#LAST_DAT="Merlin-6285_24-07-10_113208_0-1-2.dat"

#TRANSFER_INFO="/groups/flyem/home/flyem/bin/dat_transfer/2022/config/complete/volume_transfer_info.jrc_liu-nih_ips-draq5-test-2.json"
#PARENT_WORK_DIR="/groups/fibsem/fibsem/data/jrc_liu-nih_ips-draq5-test-2/dat/logs/fix"
#FIRST_DAT="Merlin-6281_24-08-22_163046_0-0-0.dat"
#LAST_DAT="Merlin-6281_24-08-22_163046_0-0-2.dat"

TRANSFER_INFO="/groups/flyem/home/flyem/bin/dat_transfer/2022/config/volume_transfer_info.jrc_pri_neuron_0710Dish4.json"
PARENT_WORK_DIR="/groups/fibsem/fibsem/data/jrc_pri-neuron_0710Dish4/dat/logs/fix"
FIRST_DAT="Merlin-6285_24-09-24_093827_0-0-0.dat"
LAST_DAT="Merlin-6285_24-09-24_094238_0-0-0.dat"

mkdir -p ${PARENT_WORK_DIR}

RUN_DATE_AND_TIME=$(date +"%Y%m%d_%H%M%S")

source /groups/flyem/data/render/bin/miniconda3/source_me.sh

conda activate janelia_emrp

# need this to avoid errors from dask
export OPENBLAS_NUM_THREADS=1

EMRP_ROOT="/groups/flyem/data/render/git/EM_recon_pipeline"

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
