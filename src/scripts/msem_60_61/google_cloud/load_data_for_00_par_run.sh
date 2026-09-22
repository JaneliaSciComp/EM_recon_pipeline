#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="00_par"
SLABS_PER_RUN=auto

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

PIPELINE_JSON="00_rough_align/pipe.00a.w${WAFER}.bc-match-mat.json"
MAT_RERUN_PIPELINE_JSON="00_rough_align/pipe.00b.w6n.rerun-mat.json"
MAT_SLAB_GROUP="${SLAB_GROUP}_mat"
BATCH_NAME="rough-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"
MAT_RERUN_BATCH_NAME="rough-mat-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"

# Wafer 61 slabs below 179 have two regions each, so a five slab run restores a whole project's
# worth of janelia stacks and half of them have to be removed before the run.  Every other case
# (e.g. the ten slab runs for wafer 61 slabs 180 and up) restores exactly what it needs.
REMOVE_EXTRA_STACKS=""
if [ "${WAFER}" = "61" ] && (( FIRST_SERIAL_NUMBER < 179 )); then

  # even serial numbers are the first half of a project's slabs, odd ones are the second half
  if (( FIRST_SERIAL_NUMBER % 2 == 0 )); then
    KEEP_OR_REMOVE="[k]ept"
  else
    KEEP_OR_REMOVE="[r]emoved"
  fi

  REMOVE_EXTRA_STACKS="./other/remove-stacks.sh

# you want stacks to be ${KEEP_OR_REMOVE}
# then enter ' 1 2 3 4 5 6 7 8 9 10 '"

fi

echo "
# ----------------------------------------------------------------------------
# Run $(date)


Set up for slab group ${SLAB_GROUP} from project group ${PROJECT_GROUP}:

# -------------------------------------
On ${VM_LABEL}, run:

docker exec --interactive --tty \"\$(docker ps -q)\" /bin/bash

# remove collections from previous 02_align run

./other/remove-match-collections.sh
# for match number prompt, enter:    1 2 3 4 5 6 7 8 9 10

./other/remove-stacks.sh
# for [r]emoved or [k]ept prompt, enter:  k
# for stack number prompt, enter:         1

./other/remove-stacks.sh

# nothing should be in the database at this point ...

# load janelia stacks:
./db-restore-collections.sh --pattern 'janelia/00_gc/.*s${FIRST_PROJECT}'

${REMOVE_EXTRA_STACKS}


# -------------------------------------
On launch box, run:

# 120 4-core executor runs take ~7 hours to complete and 6 concurrent runs will use 2904 cores (484 cores per run)

./02_run_pipeline.sh  ${VM_IP}  ${PIPELINE_JSON}  120  4  premium  120  ${BATCH_NAME}  disableDynamic

# launch information:
...

# if run fails, use the following to download the driver log:
${SCRIPT_DIR}/download-driver-log.sh rp-<launch-time>-${BATCH_NAME}

# if mfov-as-tile processing needs to be rerun, launch:
# ./02_run_pipeline.sh  ${VM_IP}  ${MAT_RERUN_PIPELINE_JSON}  120  4  premium  120  ${MAT_RERUN_BATCH_NAME}  disableDynamic


# -------------------------------------
After the run completes, on ${VM_LABEL}, run:

# par render collection dump takes 30 seconds
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern '_gc_bc_par'

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render

# par match collection dump takes 10 minutes
./db-dump-google-collections.sh --db match --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern '_gc_bc_par'

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/match

# mfov-as-tile render collection dump takes 1 minute
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${MAT_SLAB_GROUP} --pattern '_gc_bc(?!_par)'

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${MAT_SLAB_GROUP}/render

# mfov-as-tile match collection dump takes 1 minute
./db-dump-google-collections.sh --db match --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${MAT_SLAB_GROUP} --pattern '_gc_bc(?!_par)'

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${MAT_SLAB_GROUP}/match

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
