#!/bin/bash

# Batch identifier appended to each slab group name (edit this for each round of runs).
ROUGH_SLAB_GROUP_SUFFIX="20260811b"
SLAB_GROUP_SUFFIX="20260901"
STAGE="01_match"

OUTPUT_DIR="/Users/trautmane/Desktop/msem-2026-09/00-runs"
WAFER=61
FIRST_SERIAL_NUMBER="$1"

VM_IPS=(10.150.0.2  10.150.0.3  10.150.0.4  10.150.0.5  10.150.0.6
        10.150.0.7  10.150.0.8  10.150.0.9  10.150.0.10 10.150.0.11
        10.150.0.12 10.150.0.13 10.150.0.14 10.150.0.15 10.150.0.16
        10.150.0.17 10.150.0.18 10.150.0.19 10.150.0.20 10.150.0.21
        10.150.0.22 10.150.0.23 10.150.0.24 10.150.0.25 10.150.0.26
        10.150.0.27)

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
    VM_LETTER="${VM_LETTERS[REPLY-1]}"
    break
  else
    echo "Invalid selection, try again."
  fi
done

#printf "\nWhich wafer do you want to use?\n\n"
#select WAFER in 60 61; do
#  if [ -n "${WAFER}" ]; then
#    break
#  else
#    echo "Invalid selection, try again."
#  fi
#done
#
#echo
#read -rp "Enter the first serial number (a multiple of 5 between 0 and 410): " FIRST_SERIAL_NUMBER

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

ROUGH_SLAB_GROUP="s${FIRST_SERIAL}_to_s${LAST_SERIAL}_${ROUGH_SLAB_GROUP_SUFFIX}"
SLAB_GROUP="s${FIRST_SERIAL}_to_s${LAST_SERIAL}_${SLAB_GROUP_SUFFIX}"
BATCH_NAME="match-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"
PROJECT_GROUP="w${WAFER}_serial_${FIRST_PROJECT}_to_${LAST_PROJECT}"

RUN_FILE="${OUTPUT_DIR}/run.$(date '+%Y%m%d').${STAGE}.vm${VM_LETTER}.txt"

echo "
# ----------------------------------------------------------------------------
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

./db-restore-collections.sh --pattern '00_par.*s${FIRST_SERIAL}.*${ROUGH_SLAB_GROUP_SUFFIX}'

# select 1 2
# for match restore prompts, enter:    n y n y   n y n y   n y n y   n y n y   n y n y
# load takes 8 minutes

# make sure no pa_mat... match collections were loaded
./list-match-collections.sh

# remove everything except icc_par stacks
./other/remove-stacks.sh
# for [r]emoved or [k]ept prompt, enter:  k
# for stack number prompt, enter:    7 14 21 28 35 42 49 56 63 70

# -------------------------------------
On launch box, run:

# 100 4-core executor runs take ~90 minutes to complete and  7 concurrent runs will use 2828 cores (404 cores per run)
#  25 4-core executor runs take  ~6 hours   to complete and 26 concurrent runs will use 2704 cores (104 cores per run)

./02_run_pipeline.sh  ${VM_IP}  ${STAGE}/pipe.01.w6n.diff-mfov-match-patch.json  25  4  premium  25  ${BATCH_NAME}  disableDynamic

# launch information:
...



# -------------------------------------
After the run completes (typically 2 hours), on ${VM_LABEL}, run:

# render collection dump takes 30 seconds
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern icc

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render

# match collection dump takes 10 minutes
./db-dump-google-collections.sh --db match --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern icc

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/match

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"