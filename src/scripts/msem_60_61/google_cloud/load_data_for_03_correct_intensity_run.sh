#!/bin/bash

# Batch identifier appended to each slab group name (edit this for each round of runs).
SLAB_GROUP_SUFFIX="20260901"
STAGE="03_ic2d_nc4_hist_rs0p5"

OUTPUT_DIR="/Users/trautmane/Desktop/msem-2026-09/00-runs"
WAFER=61
FIRST_SERIAL_NUMBER="$1"
VM_LETTER="$2"

if (( $# != 2 )); then
  printf "\nUSAGE: %s <first serial number> <VM letter>\n\n" "$(basename "$0")"
  exit 1
fi

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
  VM_LABEL_FOR_INDEX="${VM_LETTERS[I]} - ${VM_IPS[I]}"
  VM_LABELS+=("${VM_LABEL_FOR_INDEX}")
  if [[ "${VM_LETTERS[I]}" == "${VM_LETTER}" ]]; then
    VM_IP="${VM_IPS[I]}"
    VM_LABEL="${VM_LABEL_FOR_INDEX}"
  fi
done

if [[ ! ${VM_LETTER} =~ ^[A-Z]$ ]]; then
  printf "\nExiting, VM letter '%s' is not a single upper case letter from A to Z\n\n" "${VM_LETTER}"
  exit 1
fi

# only letters with a corresponding IP are matched above, so an unset VM_IP means the letter is out of range
if [[ -z "${VM_IP}" ]]; then
  printf "\nExiting, VM letter '%s' is not one of the %d defined VMs (A to %s)\n\n" \
         "${VM_LETTER}" "${#VM_IPS[@]}" "${VM_LETTERS[${#VM_IPS[@]}-1]}"
  exit 1
fi

#printf "\nWhich VM do you want to use?\n\n"
#select VM_LABEL in "${VM_LABELS[@]}"; do
#  if [ -n "${VM_LABEL}" ]; then
#    VM_IP="${VM_IPS[REPLY-1]}"
#    VM_LETTER="${VM_LETTERS[REPLY-1]}"
#    break
#  else
#    echo "Invalid selection, try again."
#  fi
#done

#printf "\nWhich wafer do you want to use?\n\n"
#select WAFER in 60 61; do
#  if [ -n "${WAFER}" ]; then
#    break
#  else
#    echo "Invalid selection, try again."
#  fi
#done

#echo
#read -rp "Enter the first serial number (a multiple of 10 between 0 and 410): " FIRST_SERIAL_NUMBER

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
BATCH_NAME="ic2d-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"
PROJECT_GROUP="w${WAFER}_serial_${FIRST_PROJECT}_to_${LAST_PROJECT}"

RUN_FILE="${OUTPUT_DIR}/run.$(date '+%Y%m%d').${STAGE}.vm${VM_LETTER}.txt"

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

./db-restore-collections.sh --pattern '02_align.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}'
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

# render collection dump takes 3 minutes
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern asoi

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
