#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="04b_3d_align"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

BATCH_NAME="a3d-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

echo "
# ============================================================================
# Run $(date)

Set up for slab group ${SLAB_GROUP} from project group ${PROJECT_GROUP}:

# -------------------------------------
On ${VM_LABEL}, run:

docker exec --interactive --tty \"\$(docker ps -q)\" /bin/bash

# remove collections from previous run
./remove-collections.sh --db render --method remove --items 'all'

# 3d align data load typically takes 1 to 2 minutes
./db-restore-collections.sh --pattern '04b_3d_align.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/'

# for dump directories prompt, enter:         1

./list-stacks.sh

# -------------------------------------
On launch box:

cp  12_run_n5_export_batch.sh  go.$(date '+%Y%m%d')-export-batch.sh

# edit go file and specify MAX_EXECUTORS, IP, and STACK_PREFIX
# leave LAUNCH_JOBS=n and launch a quick test
# once test looks good, change LAUNCH_JOBS=y and run

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
