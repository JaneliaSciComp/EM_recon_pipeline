#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="05_sofima"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

BATCH_NAME="import-sofima-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

echo "
# ============================================================================
# Run $(date)

Set up for slab group ${SLAB_GROUP} from project group ${PROJECT_GROUP}:

# -------------------------------------
On ${VM_LABEL}, run:

docker exec --interactive --tty \"\$(docker ps -q)\" /bin/bash

# 3d align data load typically takes 1 to 2 minutes
./db-restore-collections.sh --pattern '04b_3d_align.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/'

# for dump directories prompt, enter:         1

./list-stacks.sh

# -------------------------------------
On launch box, run:

#  25 4-core executor runs take 10 minutes to complete and 26 concurrent runs will use 2704 cores (104 cores per run)

./02_run_pipeline.sh  ${VM_IP}  05_import_sofima/pipe.05.w6n.import-sofima.json  25  4  premium  25  ${BATCH_NAME}  disableDynamic

# launch information:
...



# -------------------------------------
After the run completes, on ${VM_LABEL}, run:

# sofima render collection dump takes 2 to 3 minutes, dump directory is: /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi_3d_s

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
