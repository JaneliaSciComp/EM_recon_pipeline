#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="06_ic3d"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

PIPELINE_JSON="06_correct_intensity_3d/pipe.06.w6n.ic3d.json"

RUN_DUMP_DIR="${VM_BASE_DUMP_DIR}/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}"
RUN_PARMS="--stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi_3d_s3i"

BATCH_NAME="ic3d-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

echo "
# ============================================================================
# Run $(date)

VM ${VM_LABEL}, slab group ${SLAB_GROUP}, project group ${PROJECT_GROUP}

Run file: ${RUN_FILE}

cd ${GOOGLE_CLOUD_DIR}

# -------------------------------------
# Setup VM:

# Remove the collections from the previous run:
${RIC_CMD} './remove-collections.sh --db render --method remove --items all'

# Load the 05_sofima results (only render collections are dumped for that stage):
${RIC_CMD} './db-restore-collections.sh --pattern \"05_sofima.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/\"'

# Check what is loaded:
${RIC_CMD} './list-stacks.sh'

# -------------------------------------
# Run pipeline batch job:

#  20  4-core executor runs take 17 hours to complete
#  20 16-core executor runs take 10 hours to complete

./02_run_pipeline.sh  ${VM_IP}  ${PIPELINE_JSON}  20  4  premium  20  ${BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# If needed, use the following to download the driver log:
./dataproc/download_driver_log.sh --batch-id ${BATCH_NAME}

# -------------------------------------
# After the run completes, save result data:

# The render collection dump directory is: ${RUN_DUMP_DIR}/render

# The dump will prompt for confirmation before continuing.
${DUMP_DB_CMD} render ${RUN_PARMS}'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
