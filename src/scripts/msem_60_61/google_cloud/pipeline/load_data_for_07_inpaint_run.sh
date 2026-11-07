#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="07_inpaint"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

# the xlog differs for each wafer, so each wafer has its own pipeline json
PIPELINE_JSON="07_inpaint/pipe.07.w${WAFER}.inpaint.json"

N5_PATH="gs://janelia-spark-test/hess_wafers_60_61_export"
FIRST_PIXEL_GROUP="${N5_PATH}/render/${PROJECT_GROUP}/w${WAFER}_s${FIRST_SERIAL}_r00_gc_bc_par_cc_aso_3d_s3i___pixel"

BATCH_NAME="inpaint-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

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

# Load the 06_ic3d results (the inpaint step only reads the _s3i stacks' z values and first layer tile bounds):
${RIC_CMD} './db-restore-collections.sh --pattern \"06_ic3d.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/\"'

# Check what is loaded (each slab should have an _aso_3d_s3i stack for every region):
${RIC_CMD} './list-stacks.sh'

# -------------------------------------
# Run pipeline batch job:

# Each stack is inpainted by one task, so 5 4-core executors run all of a project's stacks at once.
# TODO: add run times once they are known

./02_run_pipeline.sh  ${VM_IP}  ${PIPELINE_JSON}  5  4  standard  5  ${BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# If needed, use the following to download the driver log:
./dataproc/download_driver_log.sh --batch-id ${BATCH_NAME}

# -------------------------------------
# After the run completes, check the results:

# The inpaint step does not change any render data, so there is nothing to dump.
# Each inpainted stack's pixel group gets an 'inpaint' attribute, e.g.:
gcloud storage cat ${FIRST_PIXEL_GROUP}/attributes.json | jq .inpaint

# The original version of each changed block is in the ___pixel_no_paint group next to each pixel group.
# A rerun skips stacks that have the 'inpaint' attribute.

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
