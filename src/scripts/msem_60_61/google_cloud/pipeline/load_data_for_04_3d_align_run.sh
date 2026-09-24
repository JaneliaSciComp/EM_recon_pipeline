#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="04b_3d_align"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

LAT_STAGE="04a_layer_as_tile"
LAT_DUMP_DIR="${VM_BASE_DUMP_DIR}/${LAT_STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}"
LAT_PARMS="--stage ${LAT_STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi_lat"

RUN_DUMP_DIR="${VM_BASE_DUMP_DIR}/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}"
RUN_PARMS="--stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi_3d"

BATCH_NAME="a3d-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

echo "
# ============================================================================
# Run $(date)

VM ${VM_LABEL}, slab group ${SLAB_GROUP}, project group ${PROJECT_GROUP}

Run file: ${RUN_FILE}

# -------------------------------------
# Setup VM:

# Typical case: prior 03_correct_intensity run creates 20 _asoi stacks from 20 _aso stacks.
# The _aso stacks can be left in the database for this run, but if you want to remove them run:
#   ${RIC_CMD} './remove-collections.sh --db render --method remove --items \"1 3 5 7 9 11 13 15 17 19 21 23 25 27 29 31 33 35 37 39\"'

# To setup new VM (ic2d data load typically takes 1 to 2 minutes), run:
#   ${RIC_CMD} './db-restore-collections.sh --pattern \"03_ic2d_nc4_hist_rs0p5.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/\"'

# -------------------------------------
# Run pipeline batch job:

# 250 executor run for w61-s190-to-s199 (only has r00) took 15 minutes
#  50 4-core executor runs take 60 minutes to complete and 14 concurrent runs will use 2856 cores (204 cores per run)

./02_run_pipeline.sh  ${VM_IP}  04_3d_align/pipe.04.w6n.layer-as-tile.json 50  4  premium  50  ${BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# If needed, use the following to download the driver log:
./download-driver-log.sh ${BATCH_NAME}

# -------------------------------------
# After the run completes, save result data:

# The layer-as-tile render collection dump takes 15 seconds, dump directory is: ${LAT_DUMP_DIR}/render
${RIC_CMD} './db-dump-google-collections.sh --db render ${LAT_PARMS}'

# The layer-as-tile match collection dump takes 1 to 2 minutes, dump directory is: ${LAT_DUMP_DIR}/match
${RIC_CMD} './db-dump-google-collections.sh --db match ${LAT_PARMS}'

# The 3d render collection dump takes 2 to 3 minutes, dump directory is: ${RUN_DUMP_DIR}/render
${RIC_CMD} './db-dump-google-collections.sh --db render ${RUN_PARMS}'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
