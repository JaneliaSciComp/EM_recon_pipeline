#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="04b_3d_align"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

# 12_run_n5_export_batch.sh derives its stack names from the two digit prefix of the first serial
STACK_PREFIX="${FIRST_SERIAL:0:2}"

GO_FILE="go.$(date '+%Y%m%d')-export-batch.sh"

echo "
# ============================================================================
# Run $(date)

VM ${VM_LABEL}, slab group ${SLAB_GROUP}, project group ${PROJECT_GROUP}

Run file: ${RUN_FILE}

# -------------------------------------
# Setup VM:

# remove collections from previous run
${RIC_CMD} './remove-collections.sh --db render --method remove --items \"all\"'

# 3d align data load typically takes 1 to 2 minutes
${RIC_CMD} './db-restore-collections.sh --pattern \"${STAGE}.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/\"'

# confirm the expected stacks were loaded
${RIC_CMD} './list-stacks.sh'

# -------------------------------------
# Run export jobs:

cp  12_run_n5_export_batch.sh  ${GO_FILE}

# edit ${GO_FILE} and set:
#   MAX_EXECUTORS   (see the timing notes in the file)
#   IP=\"${VM_IP}\"
#   STACK_PREFIX=\"${STACK_PREFIX}\"
#   PIXEL_OR_MASK   pixel or mask
#
# leave LAUNCH_JOBS=n and run ./${GO_FILE} to print the commands without launching them,
# then set LAUNCH_JOBS=y and run it again to launch
#
# NOTE: for serial slabs 179 and higher, remove the r01 entries from STACK_NAMES

# -------------------------------------
# If needed, download the driver log for one of the export jobs:

# export batch ids are rex-<launch-time>-<stack name with dashes>-<pixel|mask>,
# so a pattern is enough to find the most recent one
./download_driver_log.sh 'w${WAFER}-s${FIRST_SERIAL}-r00-.*-pixel'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
