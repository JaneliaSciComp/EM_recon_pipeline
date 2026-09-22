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

# The janelia dumps are organized by project, so a five slab run would restore a whole project's
# worth of stacks (ten slabs).  db-restore-collections.sh greps --exclude-pattern against each
# collection dump file name (e.g. hess_wafers_60_61__w61_serial_170_to_179__w61_s175_r00_gc__tile.bson.gz),
# so the other half of the project's slabs can be skipped instead of being loaded and then removed.
#
# A ten slab run wants the whole project, so it needs no exclusion.
EXCLUDE_PATTERN_ARG=""
if (( SLABS_PER_RUN == 5 )); then

  # project serials share their first two digits (e.g. 170 to 179), so the excluded half is
  # the other five last digits
  if (( FIRST_SERIAL_NUMBER == FIRST_PROJECT_NUMBER )); then
    EXCLUDED_LAST_DIGITS="[5-9]"   # keeping the first half, so skip the second
  else
    EXCLUDED_LAST_DIGITS="[0-4]"   # keeping the second half, so skip the first
  fi

  EXCLUDE_PATTERN_ARG=" --exclude-pattern '_s${FIRST_PROJECT:0:2}${EXCLUDED_LAST_DIGITS}_'"

fi

echo "
# ----------------------------------------------------------------------------
# Run $(date)


Set up for slab group ${SLAB_GROUP} from project group ${PROJECT_GROUP}:

# -------------------------------------
On ${VM_LABEL}, run:

docker exec --interactive --tty \"\$(docker ps -q)\" /bin/bash

# remove collections from previous 02_align run
./remove-collections.sh --db match --method remove --items 'all'
./remove-collections.sh --db render --method remove --items 'all'

# load janelia stacks:
./db-restore-collections.sh --pattern 'janelia/00_gc/.*s${FIRST_PROJECT}'${EXCLUDE_PATTERN_ARG}


# -------------------------------------
On launch box, run:

# 120 4-core executor runs take ~7 hours to complete and 6 concurrent runs will use 2904 cores (484 cores per run)

./02_run_pipeline.sh  ${VM_IP}  ${PIPELINE_JSON}  120  4  premium  120  ${BATCH_NAME}  disableDynamic

# launch information:
...

# if run fails, use the following to download the driver log:
${GOOGLE_CLOUD_DIR}/download-driver-log.sh rp-<launch-time>-${BATCH_NAME}

# if mfov-as-tile processing needs to be rerun, launch:
# ./02_run_pipeline.sh  ${VM_IP}  ${MAT_RERUN_PIPELINE_JSON}  120  4  premium  120  ${MAT_RERUN_BATCH_NAME}  disableDynamic


# -------------------------------------
After the run completes, on ${VM_LABEL}, run:

# par render collection dump takes 30 seconds, dump directory is: /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern '_gc_bc_par'

# par match collection dump takes 10 minutes, dump directory is: /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/match
./db-dump-google-collections.sh --db match --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern '_gc_bc_par'

# mfov-as-tile render collection dump takes 1 minute, dump directory is: /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${MAT_SLAB_GROUP}/render
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${MAT_SLAB_GROUP} --pattern '_gc_bc(?!_par)'

# mfov-as-tile match collection dump takes 1 minute, dump directory is: /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${MAT_SLAB_GROUP}/match
./db-dump-google-collections.sh --db match --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${MAT_SLAB_GROUP} --pattern '_gc_bc(?!_par)'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
