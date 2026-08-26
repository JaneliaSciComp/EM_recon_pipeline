#!/bin/bash

# Batch identifier appended to each slab group name (edit this for each round of runs).
SLAB_GROUP_SUFFIX="20260811b"
STAGE="02_align"

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
read -rp "Enter the first serial number (a multiple of 5 between 0 and 410): " FIRST_SERIAL_NUMBER

if [[ ! ${FIRST_SERIAL_NUMBER} =~ ^[0-9]+$ ]]; then
  printf "\nExiting, '%s' is not a number\n\n" "${FIRST_SERIAL_NUMBER}"
  exit 1
fi

# force base 10 so that zero padded values (e.g. 070) are not treated as octal
FIRST_SERIAL_NUMBER=$(( 10#${FIRST_SERIAL_NUMBER} ))

if (( FIRST_SERIAL_NUMBER > 410 )) || (( FIRST_SERIAL_NUMBER % 5 != 0 )); then
  printf "\nExiting, %d is not a multiple of 5 between 0 and 410\n\n" "${FIRST_SERIAL_NUMBER}"
  exit 1
fi

LAST_SERIAL_NUMBER=$(( FIRST_SERIAL_NUMBER + 4 ))

# even serial numbers are the first half of a project's slabs, odd ones are the second half
if (( FIRST_SERIAL_NUMBER % 2 == 0 )); then
  KEEP_OR_REMOVE="[k]ept"
  FIRST_PROJECT_NUMBER=${FIRST_SERIAL_NUMBER}
else
  KEEP_OR_REMOVE="[r]emoved"
  FIRST_PROJECT_NUMBER=$(( FIRST_SERIAL_NUMBER - 5 ))
fi

LAST_PROJECT_NUMBER=$(( FIRST_PROJECT_NUMBER + 9 ))

FIRST_SERIAL=$(printf "%03d" "${FIRST_SERIAL_NUMBER}")
LAST_SERIAL=$(printf "%03d" "${LAST_SERIAL_NUMBER}")
FIRST_PROJECT=$(printf "%03d" "${FIRST_PROJECT_NUMBER}")
LAST_PROJECT=$(printf "%03d" "${LAST_PROJECT_NUMBER}")

SLAB_GROUP="s${FIRST_SERIAL}_to_s${LAST_SERIAL}_${SLAB_GROUP_SUFFIX}"
BATCH_NAME="aso-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"
PROJECT_GROUP="w${WAFER}_serial_${FIRST_PROJECT}_to_${LAST_PROJECT}"

echo "
# ----------------------------------------------------------------------------
# Run $(date)

Set up for slab group ${SLAB_GROUP} from project group ${PROJECT_GROUP}:

# -------------------------------------
On ${VM_LABEL}, run:

# remove collections from previous run

./other/remove-match-collections.sh
# for match number prompt, enter:    1 2 3 4 5 6 7 8 9 10

./other/remove-stacks.sh
# for [r]emoved or [k]ept prompt, enter:  k
# for stack number prompt, enter:         1

./other/remove-stacks.sh

./db-restore-collections.sh --pattern '01_match.*s${FIRST_SERIAL}.*${SLAB_GROUP_SUFFIX}'

# select 1 2
# for match restore prompts, enter:    y y   y y   y y   y y   y y
# load takes 5 to 8 minutes

./list-match-collections.sh
./list-stacks.sh

# -------------------------------------
On launch box, run:

# 50-executor runs take ~90 minutes to complete, 200-executor run on w61-s170-to-174 took 20 minutes to complete
./02_run_pipeline.sh  ${VM_IP}  ${STAGE}/pipe.02.w6n.align-stitch-only.json  50  4  premium  50  ${BATCH_NAME}  disableDynamic

# launch information:
...



# -------------------------------------
After the run completes (typically 2 hours), on ${VM_LABEL}, run:

# render collection dump takes 30 seconds
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern aso

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render

"
