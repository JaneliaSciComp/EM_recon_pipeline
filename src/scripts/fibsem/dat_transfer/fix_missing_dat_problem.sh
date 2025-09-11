#!/bin/bash

set -e

umask 0002

NUM_WORKERS="1"

# -------------------------------
# jrc_mus_liver-8

# succeeded: Merlin-6285_25-05-30_160202_0-0-0.dat Merlin-6285_25-05-30_160202_0-0-1.dat
# failed:    Merlin-6285_25-06-17_111155_0-0-0.dat Merlin-6285_25-06-17_111155_0-0-1.dat
# succeeded: Merlin-6285_25-06-21_085833_0-0-0.dat Merlin-6285_25-06-21_085833_0-0-1.dat (but realized much later timestamp than prior dat, so left it out)
# succeeded: Merlin-6285_25-06-14_070928_0-0-0.dat Merlin-6285_25-06-14_070928_0-0-1.dat
# ???: Merlin-6285_25-06-17_111827_0-0-0.dat

#FIRST_DAT="Merlin-6285_25-06-17_111827_0-0-0.dat"
#LAST_DAT="Merlin-6285_25-06-17_111827_0-0-1.dat"

#TRANSFER_INFO="/groups/fibsem/home/fibsemxfer/config/volume_transfer_info.jrc_mus_liver-8.json"
#PARENT_WORK_DIR="/groups/cellmap/cellmap/data/jrc_mus_liver-8/dat/logs/fix"

# -------------------------------
# jrc_hum-glioblastoma-1

#FIRST_DAT="Merlin-6257_25-08-22_085444_0-0-0.dat"
#LAST_DAT="Merlin-4238_25-09-01_131829_0-0-1.dat"

#TRANSFER_INFO="/groups/cellmap/cellmap/render/align/jrc_hum-glioblastoma-1/volume_transfer_info.jrc_hum-glioblastoma-1.json"
#PARENT_WORK_DIR="/groups/cellmap/cellmap/data/jrc_hum-glioblastoma-1/dat/logs/fix"

# -------------------------------

# jrc_pristi-20250718

FIRST_DAT="Merlin-4238_25-08-12_134120_0-0-0.dat"
LAST_DAT="Merlin-4238_25-08-26_111225_0-0-1.dat"

TRANSFER_INFO="/groups/shroff/shrofflab/render/align/jrc_pristi-20250718/volume_transfer_info.jrc_pristi-20250718.json"
PARENT_WORK_DIR="/groups/shroff/shrofflab/data/jrc_pristi-20250718/dat/logs/fix"


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
