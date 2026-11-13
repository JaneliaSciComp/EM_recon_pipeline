#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="06_ic3d"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

PIPELINE_JSON="06_correct_intensity_3d/pipe.06.w6n.ic3d.json"

RUN_DUMP_DIR="${VM_BASE_DUMP_DIR}/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}"
RUN_PARMS="--stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern aso_3d_s3i"

BATCH_NAME="ic3d-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

# The 05 import leaves four stacks for each region (_aso, _aso_3d_s, _asoi_3d, and _asoi_3d_s),
# but only the _aso_3d_s stacks are needed here.  remove-collections.sh selects stacks by their
# numbers in its sorted list, so the container numbers the stacks the same way it does
# (stackIds names piped to sort, in the container's locale) and passes the _aso_3d_s numbers to --items.
# The command is in single quotes here so that it is printed as is and only run in the container
# (paste joins the numbers instead of tr "\n" because echo turns that backslash into a line break).
STACK_IDS_URL="http://localhost:8080/render-ws/v1/owner/hess_wafers_60_61/project/${PROJECT_GROUP}/stackIds"
KEEP_ITEMS='$(curl -s "'"${STACK_IDS_URL}"'" | jq -r ".[].stack" | sort | grep -n "_aso_3d_s$" | cut -d: -f1 | paste -s -d " " -)'

echo "
# ============================================================================
# Run $(date)

VM ${VM_LABEL}, slab group ${SLAB_GROUP}, project group ${PROJECT_GROUP}

Run file: ${RUN_FILE}

cd ${GOOGLE_CLOUD_DIR}

# -------------------------------------
# Setup VM:

# If the 05 import was run on this VM, remove everything except its _aso_3d_s stacks
# (check the list of stacks to keep before confirming):
${RIC_CMD} './remove-collections.sh --db render --method keep --items \"${KEEP_ITEMS}\"'

# Otherwise, on a new VM, load the 05_sofima results instead (only render collections are dumped for that stage):
#   ${RIC_CMD} './db-restore-collections.sh --pattern \"05_sofima.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/\"'
#
# and check what is loaded:
#   ${RIC_CMD} './list-stacks.sh'

# -------------------------------------
# Run pipeline batch job:

#  20 16-core executor runs take 12 hours to complete and  9 concurrent runs will use 2916 cores (324 cores per run)

./02_run_pipeline.sh  ${VM_IP}  ${PIPELINE_JSON}  20  16  premium  20  ${BATCH_NAME}  disableDynamic | tee -a \"${RUN_FILE}\"

# If needed, use the following to download the driver log:
./dataproc/download_driver_log.sh --batch-id ${BATCH_NAME}

# -------------------------------------
# After the run completes, save result data:

# The ic3d render collection dump takes 2 to 3 minutes, dump directory is: ${RUN_DUMP_DIR}/render

# The dump will prompt for confirmation before continuing.
${DUMP_DB_CMD} render ${RUN_PARMS}'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
