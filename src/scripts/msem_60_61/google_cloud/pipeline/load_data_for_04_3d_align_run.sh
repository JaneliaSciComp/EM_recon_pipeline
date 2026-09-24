#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="04b_3d_align"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

LAYER_AS_TILE_STAGE="04a_layer_as_tile"
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

# ic2d data load typically takes 1 to 2 minutes
./db-restore-collections.sh --pattern '03_ic2d_nc4_hist_rs0p5.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/'
# for dump directories prompt, enter:         1

./list-stacks.sh



# -------------------------------------
On launch box, run:

# 250 executor run for w61-s190-to-s199 (only has r00)     took 15 minutes
#  50 4-core executor runs take 60 minutes to complete and 14 concurrent runs will use 2856 cores (204 cores per run)

./02_run_pipeline.sh  ${VM_IP}  04_3d_align/pipe.04.w6n.layer-as-tile.json  50  4  premium  50  ${BATCH_NAME}  disableDynamic

# launch information:
...


# if run fails, use the following to download the driver log:
${GOOGLE_CLOUD_DIR}/download-driver-log.sh rp-<launch-time>-${BATCH_NAME}

# -------------------------------------
After the run completes (typically 4 to 5 hours), on ${VM_LABEL}, run:

# layer-as-tile render collection dump takes 15 seconds, dump directory is: /mnt/disks/mongodb_dump_fs/dump/google/${LAYER_AS_TILE_STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render
./db-dump-google-collections.sh --db render --stage ${LAYER_AS_TILE_STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi_lat

# layer-as-tile match collection dump takes 1 to 2 minutes, dump directory is: /mnt/disks/mongodb_dump_fs/dump/google/${LAYER_AS_TILE_STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/match
./db-dump-google-collections.sh --db match --stage ${LAYER_AS_TILE_STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi_lat

# 3d render collection dump takes 2 to 3 minutes, dump directory is: /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi_3d

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
