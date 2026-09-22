#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="03_ic2d_nc4_hist_rs0p5"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

BATCH_NAME="ic2d-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

echo "
# ============================================================================
# Run $(date)

Set up for slab group ${SLAB_GROUP} from project group ${PROJECT_GROUP}:

# -------------------------------------
On ${VM_LABEL}, run:

docker exec --interactive --tty \"\$(docker ps -q)\" /bin/bash

# remove collections from previous run

./other/remove-match-collections.sh
# for match number prompt, enter:    1 2 3 4 5 6 7 8 9 10

./other/remove-stacks.sh
# for [r]emoved or [k]ept prompt, enter:  k
# for stack number prompt, enter:         1

./other/remove-stacks.sh

./db-restore-collections.sh --pattern '02_align.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/'
# for dump directories prompt, enter:         1 2

./list-stacks.sh



# -------------------------------------
On launch box, run:

# 400 4-core executor run  took 2 hours to complete for w61-s170-to-s179
#  50 4-core executor runs take 2 to 5 hours to complete and 14 concurrent runs will use 2856 cores (204 cores per run)

./02_run_pipeline.sh  ${VM_IP}  03_correct_intensity/pipe.03.w6n.ic2d-stitch-only.json  50  4  premium  50  ${BATCH_NAME}  disableDynamic

# launch information:
...



# -------------------------------------
After the run completes (typically 4 to 5 hours), on ${VM_LABEL}, run:

# render collection dump takes 3 minutes, dump directory is: /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
