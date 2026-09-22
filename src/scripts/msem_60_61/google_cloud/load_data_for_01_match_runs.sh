#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="01_match"
SLABS_PER_RUN=auto

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

BATCH_NAME="match-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"
CREEP_BATCH_NAME="creep-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"
CREEP_SLAB_GROUP="${SLAB_GROUP}_creep"

echo "
# ----------------------------------------------------------------------------
# Run $(date)


Set up for slab group ${SLAB_GROUP} from project group ${PROJECT_GROUP}:

# -------------------------------------
On ${VM_LABEL}, run:

# remove collections from 00_par run

./other/remove-match-collections.sh
# for match number prompt, enter:    1 3 5 7 9 11 13 15 17 19

./other/remove-stacks.sh
# for [r]emoved or [k]ept prompt, enter:  k
# for stack number prompt, enter:         6 12 18 24 30 36 42 48 54 60

# to restore on new VM:
#   ./db-restore-collections.sh --pattern '00_par.*s${FIRST_SERIAL}.*${SLAB_GROUP_SUFFIX}/'

./list-stacks.sh
./list-match-collections.sh

# -------------------------------------
On launch box, run:

# 300 4-core executor run  took  40 minutes for w61-s125-to-129
# 120 4-core executor runs take ~90 minutes and  6 concurrent runs will use 2904 cores (484 cores per run)
#  25 4-core executor runs take  ~6 hours   and 26 concurrent runs will use 2704 cores (104 cores per run)

./02_run_pipeline.sh  ${VM_IP}  ${STAGE}/pipe.01a.w6n.diff-mfov-match-patch.json  120  4  premium  120  ${BATCH_NAME}  disableDynamic

# launch information:
...


# if run fails, use the following to download the driver log:
${SCRIPT_DIR}/download-driver-log.sh rp-<launch-time>-${BATCH_NAME}

# -------------------------------------
After the run completes, on ${VM_LABEL}, run:

# render collection dump takes 30 seconds, dump directory is: /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern 'bc_par(?!_cc)'

# match collection dump takes 10 minutes, dump directory is: /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/match
./db-dump-google-collections.sh --db match --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern 'bc_par(?!_cc)'


# -------------------------------------
On launch box, run:

#  10 4-core executor runs take  15 minutes   and 26 concurrent runs will use 1144 cores (44 cores per run)
#  25 4-core executor run takes same amount of time as 10 4-core executor run because it serially goes
#                         through each stack and then parallelizes work by z layer

./02_run_pipeline.sh  ${VM_IP}  ${STAGE}/pipe.01b.w6n.creep-correct.json  10  4  premium  10  ${CREEP_BATCH_NAME}  disableDynamic

# launch information:
...



# -------------------------------------
After the run completes, on ${VM_LABEL}, run:

# render collection dump takes 30 seconds, dump directory is: /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${CREEP_SLAB_GROUP}/render
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${CREEP_SLAB_GROUP} --pattern bc_par_cc

# match collection dump takes 10 minutes, dump directory is: /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${CREEP_SLAB_GROUP}/match
./db-dump-google-collections.sh --db match --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${CREEP_SLAB_GROUP} --pattern bc_par_cc

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"