#!/bin/bash

# Batch identifier appended to each slab group name (edit this for each round of runs).
SLAB_GROUP_SUFFIX="20260811b"
LAYER_AS_TILE_STAGE="04a_layer_as_tile"
STAGE="04b_3d_align"

VM_IPS=(10.150.0.2 10.150.0.3 10.150.0.4 10.150.0.5 10.150.0.6 10.150.0.7
        10.150.0.8 10.150.0.9 10.150.0.10 10.150.0.11)

# VMs are lettered in IP order (A is the first IP, B is the second, ...)
VM_LETTERS=({A..Z})
VM_LABELS=()
for I in "${!VM_IPS[@]}"; do
  VM_LABELS+=("${VM_LETTERS[I]} - ${VM_IPS[I]}")
done

printf "\nWhich VM do you want to use?\n\n"
select VM_LABEL in "${VM_LABELS[@]}"; do
  if [ -n "${VM_LABEL}" ]; then
    VM_IP="${VM_IPS[REPLY-1]}"
    break
  else
    echo "Invalid selection, try again."
  fi
done

printf "\nWhich wafer do you want to use?\n\n"
select WAFER in 60 61; do
  if [ -n "${WAFER}" ]; then
    break
  else
    echo "Invalid selection, try again."
  fi
done

echo
read -rp "Enter the first serial number (a multiple of 10 between 0 and 410): " FIRST_SERIAL_NUMBER

if [[ ! ${FIRST_SERIAL_NUMBER} =~ ^[0-9]+$ ]]; then
  printf "\nExiting, '%s' is not a number\n\n" "${FIRST_SERIAL_NUMBER}"
  exit 1
fi

# force base 10 so that zero padded values (e.g. 070) are not treated as octal
FIRST_SERIAL_NUMBER=$(( 10#${FIRST_SERIAL_NUMBER} ))

if (( FIRST_SERIAL_NUMBER > 410 )) || (( FIRST_SERIAL_NUMBER % 10 != 0 )); then
  printf "\nExiting, %d is not a multiple of 10 between 0 and 410\n\n" "${FIRST_SERIAL_NUMBER}"
  exit 1
fi

SECOND_SERIAL_NUMBER=$(( FIRST_SERIAL_NUMBER + 5 ))
LAST_SERIAL_NUMBER=$(( SECOND_SERIAL_NUMBER + 4 ))

FIRST_PROJECT_NUMBER=${FIRST_SERIAL_NUMBER}
LAST_PROJECT_NUMBER=$(( FIRST_PROJECT_NUMBER + 9 ))

FIRST_SERIAL=$(printf "%03d" "${FIRST_SERIAL_NUMBER}")
SECOND_SERIAL=$(printf "%03d" "${SECOND_SERIAL_NUMBER}")
LAST_SERIAL=$(printf "%03d" "${LAST_SERIAL_NUMBER}")
FIRST_PROJECT=$(printf "%03d" "${FIRST_PROJECT_NUMBER}")
LAST_PROJECT=$(printf "%03d" "${LAST_PROJECT_NUMBER}")

# matches both serials with one pattern (e.g. s08[05] for serials 080 and 085)
SERIAL_PATTERN="s${FIRST_SERIAL:0:2}[${FIRST_SERIAL:2:1}${SECOND_SERIAL:2:1}]"

SLAB_GROUP="s${FIRST_SERIAL}_to_s${LAST_SERIAL}_${SLAB_GROUP_SUFFIX}"
BATCH_NAME="a3d-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"
PROJECT_GROUP="w${WAFER}_serial_${FIRST_PROJECT}_to_${LAST_PROJECT}"

echo "
# ============================================================================
# Run $(date)

Set up for slab group ${SLAB_GROUP} from project group ${PROJECT_GROUP}:

# -------------------------------------
On ${VM_LABEL}, run:

# remove collections from previous run

./other/remove-match-collections.sh
# for match number prompt, enter:    1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20

./other/remove-stacks.sh
# for [r]emoved or [k]ept prompt, enter:  k
# for stack number prompt, enter:         1

./other/remove-stacks.sh

# ic2d data load typically takes 1 to 2 minutes
./db-restore-collections.sh --pattern '03_ic2d_nc4_hist_rs0p5.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}'
# for dump directories prompt, enter:         1

./list-stacks.sh



# -------------------------------------
On launch box, run:

# 250 executor run for w61-s190-to-s199 (only has r00)     took 15 minutes
#  50 executor run for w61-s080-to-s089 (with r00 and r01) took 60 minutes
./02_run_pipeline.sh  ${VM_IP}  04_3d_align/pipe.04.w6n.layer-as-tile.json  50  4  premium  50  ${BATCH_NAME}  disableDynamic

# launch information:
...



# -------------------------------------
After the run completes (typically 4 to 5 hours), on ${VM_LABEL}, run:

# layer-as-tile render collection dump takes 15 seconds
./db-dump-google-collections.sh --db render --stage ${LAYER_AS_TILE_STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi_lat

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${LAYER_AS_TILE_STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render

# layer-as-tile match collection dump takes ?
./db-dump-google-collections.sh --db match --stage ${LAYER_AS_TILE_STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi_lat

# 3d render collection dump takes 2 to 3 minutes
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi_3d

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render


"
