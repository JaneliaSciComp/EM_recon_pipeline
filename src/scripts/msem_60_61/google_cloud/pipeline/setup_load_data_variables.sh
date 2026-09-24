#!/bin/bash

# ----------------------------------------------------------------------------
# Common setup for the load_data_for_*.sh scripts.
#
# Source this after setting STAGE and SLABS_PER_RUN, e.g.
#
#   SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
#   STAGE="02_align"
#   SLABS_PER_RUN=5
#   source "${SCRIPT_DIR}/setup_load_data_variables.sh"
#
# It parses <wafer> <first serial number> <VM letter> from the sourcing script's parameters,
# validates them, and derives the variables the run instructions need:
#
#   WAFER  FIRST_SERIAL_NUMBER  VM_LETTER  VM_IP  VM_LABEL  GOOGLE_CLOUD_DIR
#   FIRST_SERIAL  LAST_SERIAL  FIRST_PROJECT  LAST_PROJECT
#   SLAB_GROUP  PROJECT_GROUP  RUN_FILE
#
# SLABS_PER_RUN picks the run shape:
#
#     5   half a project per run
#    10   a whole project per run, also sets SECOND_SERIAL and SERIAL_PATTERN
#  auto   derive 5 or 10 from the wafer and first serial number (see deriveSlabsPerRun below)
#
# The 00 - 02 stages use auto because their run size depends on how many regions each slab has,
# while the 03 - 05 stages always process a whole project at a time.
#
# The sourcing script is responsible for BATCH_NAME and anything else stage specific.

# Batch identifier appended to each slab group name (edit this for each round of runs).
SLAB_GROUP_SUFFIX="20260918"

OUTPUT_DIR="/Users/trautmane/Desktop/msem-2026-09/00-runs"
VM_BASE_DUMP_DIR="/mnt/disks/mongodb_dump_fs/dump/google"

# These scripts live in google_cloud/pipeline while the tools the run instructions reference
# (e.g. download-driver-log.sh) live in google_cloud, so keep an absolute path to the parent.
GOOGLE_CLOUD_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

# ----------------------------------------------------------------------------
# Validate what the sourcing script must define

if [ -z "${STAGE}" ]; then
  printf "\nExiting, STAGE must be set before sourcing %s\n\n" "$(basename "${BASH_SOURCE[0]}")"
  exit 1
fi

case "${SLABS_PER_RUN}" in
  5|10|auto)
    ;;
  *)
    printf "\nExiting, SLABS_PER_RUN must be 5, 10, or auto (not '%s') before sourcing %s\n\n" \
           "${SLABS_PER_RUN}" "$(basename "${BASH_SOURCE[0]}")"
    exit 1
    ;;
esac

# Each run is sized to cover ten stacks, so the number of slabs per run depends on how many
# regions each slab has:
#
#   wafer 61, serial slabs 000 to 179:  two regions (r00 and r01), so  5 slabs per run
#   wafer 61, serial slabs 180 and up:  one region  (r00),         so 10 slabs per run
#   wafer 60:                           region counts are not known yet
#
# NOTE: slab 179 has one region but is still processed in the 175 to 179 group of five,
#       so that group covers nine stacks instead of ten.
deriveSlabsPerRun() {
  case "${WAFER}" in
    61)
      if (( FIRST_SERIAL_NUMBER < 180 )); then
        echo 5
      else
        echo 10
      fi
      ;;
    *)
      # TODO: replace this with the wafer 60 group sizes once the region counts are known
      echo 5
      ;;
  esac
}

# ----------------------------------------------------------------------------
# Parse and validate the sourcing script's parameters

WAFER="$1"
FIRST_SERIAL_NUMBER="$2"
VM_LETTER="$3"

if (( $# != 3 )); then
  printf "\nUSAGE: %s <wafer> <first serial number> <VM letter>\n\n" "$(basename "$0")"
  exit 1
fi

case "${WAFER}" in
  60|61)
    ;;
  *)
    printf "\nExiting, wafer '%s' is not 60 or 61\n\n" "${WAFER}"
    exit 1
    ;;
esac

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

# the derivation needs the wafer and the parsed serial number, so it happens after both are known
# but before the multiple-of check below
if [ "${SLABS_PER_RUN}" = "auto" ]; then
  SLABS_PER_RUN=$(deriveSlabsPerRun)
fi

if (( FIRST_SERIAL_NUMBER > 410 )) || (( FIRST_SERIAL_NUMBER % SLABS_PER_RUN != 0 )); then
  printf "\nExiting, %d is not a multiple of %d between 0 and 410\n\n" \
         "${FIRST_SERIAL_NUMBER}" "${SLABS_PER_RUN}"
  exit 1
fi

# ----------------------------------------------------------------------------
# Derive the serial and project numbers

if (( SLABS_PER_RUN == 5 )); then

  LAST_SERIAL_NUMBER=$(( FIRST_SERIAL_NUMBER + 4 ))

  # even serial numbers are the first half of a project's slabs, odd ones are the second half
  if (( FIRST_SERIAL_NUMBER % 2 == 0 )); then
    FIRST_PROJECT_NUMBER=${FIRST_SERIAL_NUMBER}
  else
    FIRST_PROJECT_NUMBER=$(( FIRST_SERIAL_NUMBER - 5 ))
  fi

else

  SECOND_SERIAL_NUMBER=$(( FIRST_SERIAL_NUMBER + 5 ))
  LAST_SERIAL_NUMBER=$(( SECOND_SERIAL_NUMBER + 4 ))
  FIRST_PROJECT_NUMBER=${FIRST_SERIAL_NUMBER}

fi

LAST_PROJECT_NUMBER=$(( FIRST_PROJECT_NUMBER + 9 ))

FIRST_SERIAL=$(printf "%03d" "${FIRST_SERIAL_NUMBER}")
LAST_SERIAL=$(printf "%03d" "${LAST_SERIAL_NUMBER}")
FIRST_PROJECT=$(printf "%03d" "${FIRST_PROJECT_NUMBER}")
LAST_PROJECT=$(printf "%03d" "${LAST_PROJECT_NUMBER}")

if (( SLABS_PER_RUN == 10 )); then
  SECOND_SERIAL=$(printf "%03d" "${SECOND_SERIAL_NUMBER}")
  # matches both serials with one pattern (e.g. s08[05] for serials 080 and 085)
  SERIAL_PATTERN="s${FIRST_SERIAL:0:2}[${FIRST_SERIAL:2:1}${SECOND_SERIAL:2:1}]"
fi

# ----------------------------------------------------------------------------
# Derive the names used throughout the run instructions

SLAB_GROUP="s${FIRST_SERIAL}_to_s${LAST_SERIAL}_${SLAB_GROUP_SUFFIX}"
PROJECT_GROUP="w${WAFER}_serial_${FIRST_PROJECT}_to_${LAST_PROJECT}"

RUN_FILE="${OUTPUT_DIR}/run.$(date '+%Y%m%d').${STAGE}.vm${VM_LETTER}.txt"
RIC_CMD="./run_in_container.sh --vm ${VM_LETTER} --command"

# NOTE: the opening quote in the following command needs to be closed after the parameters are added
DUMP_DB_CMD="${RIC_CMD} './db-dump-google-collections.sh --db"
