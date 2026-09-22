#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="02_align"
SLABS_PER_RUN=5

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

BATCH_NAME="aso-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

echo "
# ----------------------------------------------------------------------------
# Run $(date)

Set up for slab group ${SLAB_GROUP} from project group ${PROJECT_GROUP}:

# -------------------------------------
On ${VM_LABEL}, run:

docker exec --interactive --tty \"\$(docker ps -q)\" /bin/bash

# remove collections from 01_match run

./other/remove-stacks.sh
# for [r]emoved or [k]ept prompt, enter:  k
# for stack number prompt, enter:         2 4 6 8 10 12 14 16 18 20

# to restore on new VM:
#   ./db-restore-collections.sh --pattern '01_match.*s${FIRST_SERIAL}.*${SLAB_GROUP_SUFFIX}_creep/'

# -------------------------------------
On launch box, run:

# 200 4-core executor run  took  20 minutes to complete for w61-s170-to-s174
# 120 4-core executor runs take ~90 minutes to complete and  6 concurrent runs will use 2904 cores (484 cores per run)
#  20 4-core executor runs take  ~5 hours   to complete and 26 concurrent runs will use 2184 cores ( 84 cores per run)

./02_run_pipeline.sh  ${VM_IP}  ${STAGE}/pipe.02.w6n.align-stitch-only.json  120  4  premium  120  ${BATCH_NAME}  disableDynamic

# launch information:
...


# if run fails, use the following to download the driver log:
${SCRIPT_DIR}/download-driver-log.sh rp-<launch-time>-${BATCH_NAME}

# -------------------------------------
After the run completes, on ${VM_LABEL}, run:

# render collection dump takes 30 seconds
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern aso

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"