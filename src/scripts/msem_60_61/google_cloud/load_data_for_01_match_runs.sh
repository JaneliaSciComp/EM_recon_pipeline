#!/bin/bash

# NOTE: readlink -m is a GNU extension that the BSD readlink on macOS does not support,
#       so derive the absolute script directory with cd and pwd instead
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Batch identifier appended to each slab group name (edit this for each round of runs).
SLAB_GROUP_SUFFIX="20260918"
STAGE="01_match"

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
BATCH_NAME="match-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"
CREEP_BATCH_NAME="creep-w${WAFER}-s${FIRST_SERIAL}-to-s${LAST_SERIAL}"
CREEP_SLAB_GROUP="${SLAB_GROUP}_creep"
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

./db-restore-collections.sh --pattern '00_par.*s${FIRST_SERIAL}.*${SLAB_GROUP_SUFFIX}/'
# load takes 8? minutes

./list-stacks.sh
./list-match-collections.sh

# -------------------------------------
On launch box, run:

# 300 4-core executor run  took  40 minutes for w61-s125-to-129
# 100 4-core executor runs take ~90 minutes and  7 concurrent runs will use 2828 cores (404 cores per run)
#  25 4-core executor runs take  ~6 hours   and 26 concurrent runs will use 2704 cores (104 cores per run)

./02_run_pipeline.sh  ${VM_IP}  ${STAGE}/pipe.01a.w6n.diff-mfov-match-patch.json  25  4  premium  25  ${BATCH_NAME}  disableDynamic

# launch information:
...


# if run fails, use the following to download the driver log:
${SCRIPT_DIR}/download-driver-log.sh rp-<launch-time>-${BATCH_NAME}

# -------------------------------------
After the run completes (typically 2 hours), on ${VM_LABEL}, run:

# render collection dump takes 30 seconds
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern 'bc_par(?!_cc)'

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/render

# match collection dump takes 10 minutes
./db-dump-google-collections.sh --db match --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${SLAB_GROUP} --pattern 'bc_par(?!_cc)'

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${SLAB_GROUP}/match


# -------------------------------------
On launch box, run:

#  25 4-core executor runs take  ? minutes   and 26 concurrent runs will use 2704 cores (104 cores per run)

./02_run_pipeline.sh  ${VM_IP}  ${STAGE}/pipe.01b.w6n.creep-correct.json  25  4  premium  25  ${CREEP_BATCH_NAME}  disableDynamic

# launch information:
...



# -------------------------------------
After the run completes (typically 2 hours), on ${VM_LABEL}, run:

# render collection dump takes 30 seconds
./db-dump-google-collections.sh --db render --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${CREEP_SLAB_GROUP} --pattern bc_par_cc

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${CREEP_SLAB_GROUP}/render

# match collection dump takes 10 minutes
./db-dump-google-collections.sh --db match --stage ${STAGE} --project ${PROJECT_GROUP} --slab-group ${CREEP_SLAB_GROUP} --pattern bc_par_cc

# Should dump collections to:
#  /mnt/disks/mongodb_dump_fs/dump/google/${STAGE}/${PROJECT_GROUP}/${CREEP_SLAB_GROUP}/match

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"