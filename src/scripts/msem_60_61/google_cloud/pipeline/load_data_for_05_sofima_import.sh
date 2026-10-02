#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="05_sofima"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

PIPELINE_JSON="05_import_sofima/pipe.05.w6n.import-sofima.json"

RUN_DUMP_DIR="${VM_BASE_DUMP_DIR}/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}"
RUN_PARMS="--stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi_3d_s"

BATCH_NAME="import-sofima-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

echo "
# ============================================================================
# Run $(date)

VM ${VM_LABEL}, slab group ${SLAB_GROUP}, project group ${PROJECT_GROUP}

Run file: ${RUN_FILE}

cd ${GOOGLE_CLOUD_DIR}

# -------------------------------------
# Setup VM:

# Load the 04b_3d_align results (typically takes 1 to 2 minutes, for the dump directories prompt, enter: 1):
${RIC_CMD} './db-restore-collections.sh --pattern \"04b_3d_align.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/\"'

# Check what is loaded:
${RIC_CMD} './list-stacks.sh'

# -------------------------------------
# Run pipeline batch job:

#  25 4-core executor runs take 10 minutes to complete and 26 concurrent runs will use 2704 cores (104 cores per run)

./02_run_pipeline.sh  ${VM_IP}  ${PIPELINE_JSON}  25  4  premium  25  ${BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# If needed, use the following to download the driver log:
./dataproc/download_driver_log.sh --batch-id ${BATCH_NAME}

# -------------------------------------
# After the run completes, save result data:

# The sofima render collection dump takes 2 to 3 minutes, dump directory is: ${RUN_DUMP_DIR}/render

# The dump will prompt for confirmation before continuing.
${DUMP_DB_CMD} render ${RUN_PARMS}'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
