#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="03_ic2d_nc4_hist_rs0p5"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

PIPELINE_JSON="03_correct_intensity/pipe.03.w6n.ic2d-stitch-only.json"

RUN_DUMP_DIR="${VM_BASE_DUMP_DIR}/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}"
RUN_PARMS="--stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi"

BATCH_NAME="ic2d-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

echo "
# ============================================================================
# Run $(date)

VM ${VM_LABEL}, slab group ${SLAB_GROUP}, project group ${PROJECT_GROUP}

Run file: ${RUN_FILE}

cd ${GOOGLE_CLOUD_DIR}

# -------------------------------------
# Setup VM:

# Remove the collections from the previous run:
${RIC_CMD} './remove-collections.sh --db match --method remove --items all'
${RIC_CMD} './remove-collections.sh --db render --method remove --items all'

# Load the 02_align results (for the dump directories prompt, enter: 1 2):
${RIC_CMD} './db-restore-collections.sh --pattern \"02_align.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/\"'

# Check what is loaded:
${RIC_CMD} './list-stacks.sh'

# -------------------------------------
# Run pipeline batch job:

# 400 4-core executor run  took 2 hours to complete for w61-s170-to-s179
#  50 4-core executor runs take 2 to 5 hours to complete and 14 concurrent runs will use 2856 cores (204 cores per run)

./02_run_pipeline.sh  ${VM_IP}  ${PIPELINE_JSON}  50  4  premium  50  ${BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# If needed, use the following to download the driver log:
./dataproc/download_driver_log.sh --batch-id ${BATCH_NAME}

# -------------------------------------
# After the run completes (typically 4 to 5 hours), save result data:

# The render collection dump takes 3 minutes, dump directory is: ${RUN_DUMP_DIR}/render

# The dump will prompt for confirmation before continuing.
${DUMP_DB_CMD} render ${RUN_PARMS}'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
