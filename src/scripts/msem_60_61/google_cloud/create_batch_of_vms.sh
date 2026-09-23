#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# ----------------------------------------------------------------------------
# Creates one render-ws-with-mongodb VM for each letter in a range by calling
# create_compute_instance_vm.sh.
#
# VMs are lettered in IP order (a is the first IP, b is the second, ...), matching the
# letter to IP mapping that load_data/setup_load_data_variables.sh uses to identify VMs.

VM_LETTERS=({a..z})
IP_PREFIX="10.150.0"

# the first two addresses in the subnet are reserved, so VM a starts at 10.150.0.2
FIRST_IP_OCTET=2

LAST_VM_LETTER="${VM_LETTERS[${#VM_LETTERS[@]}-1]}"

CREATE_VM_SCRIPT="${SCRIPT_DIR}/create_compute_instance_vm.sh"

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_MIN_VM=""
ARG_MAX_VM=""

usage() {
  echo "
USAGE $0 --min-vm <letter> --max-vm <letter>

  --min-vm  first VM letter to create, from a to ${LAST_VM_LETTER} (required)
  --max-vm  last VM letter to create, from a to ${LAST_VM_LETTER} (required)

Examples:
  $0 --min-vm a --max-vm f
  $0 --min-vm g --max-vm l
  $0 --min-vm c --max-vm c
"
  exit 1
}

if (( $# < 1 )); then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --min-vm)
      ARG_MIN_VM="${2:?'--min-vm requires a value'}"
      shift 2
      ;;
    --max-vm)
      ARG_MAX_VM="${2:?'--max-vm requires a value'}"
      shift 2
      ;;
    *)
      echo "ERROR: unrecognized parameter '${1}'"
      usage
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Validate parameters

if [ -z "${ARG_MIN_VM}" ]; then
  echo "ERROR: --min-vm is required"
  usage
fi

if [ -z "${ARG_MAX_VM}" ]; then
  echo "ERROR: --max-vm is required"
  usage
fi

# setup_load_data_variables.sh identifies the same VMs with upper case letters,
# so accept either case here and use the lower case form the VM names need
ARG_MIN_VM="${ARG_MIN_VM,,}"
ARG_MAX_VM="${ARG_MAX_VM,,}"

validateVmLetter() {
  local NAME="$1"
  local VALUE="$2"
  if [[ ! "${VALUE}" =~ ^[a-${LAST_VM_LETTER}]$ ]]; then
    echo "ERROR: ${NAME} must be a single letter from a to ${LAST_VM_LETTER} (not '${VALUE}')"
    exit 1
  fi
}

validateVmLetter "--min-vm" "${ARG_MIN_VM}"
validateVmLetter "--max-vm" "${ARG_MAX_VM}"

# convert each letter to its index in VM_LETTERS (the "'a" form gives the character's numeric value)
printf -v MIN_INDEX '%d' "'${ARG_MIN_VM}"
printf -v MAX_INDEX '%d' "'${ARG_MAX_VM}"
printf -v FIRST_LETTER_CODE '%d' "'${VM_LETTERS[0]}"
MIN_INDEX=$(( MIN_INDEX - FIRST_LETTER_CODE ))
MAX_INDEX=$(( MAX_INDEX - FIRST_LETTER_CODE ))

if (( MIN_INDEX > MAX_INDEX )); then
  echo "ERROR: --min-vm '${ARG_MIN_VM}' must not come after --max-vm '${ARG_MAX_VM}'"
  exit 1
fi

if [ ! -x "${CREATE_VM_SCRIPT}" ]; then
  echo "ERROR: ${CREATE_VM_SCRIPT} does not exist or is not executable"
  exit 1
fi

NUMBER_OF_VMS=$(( MAX_INDEX - MIN_INDEX + 1 ))

# ----------------------------------------------------------------------------
# Show the plan and confirm before creating anything

echo "
The following ${NUMBER_OF_VMS} VM(s) will be created:
"

for (( I=MIN_INDEX; I<=MAX_INDEX; I++ )); do
  printf "  %s --suffix %s --private-network-ip %s.%d\n" \
         "$(basename "${CREATE_VM_SCRIPT}")" "${VM_LETTERS[I]}" "${IP_PREFIX}" $(( FIRST_IP_OCTET + I ))
done

echo
read -rp "Do you want to create these VMs? (y/n): " CONFIRM
if [[ ! ${CONFIRM} =~ ^[Yy]$ ]]; then
  echo
  exit 0
fi

# ----------------------------------------------------------------------------
# Create the VMs
#
# A failure for one VM (e.g. a quota error) does not stop the others, so that a single
# bad letter can be retried on its own afterwards instead of rerunning everything.

FAILED_SUFFIXES=()

for (( I=MIN_INDEX; I<=MAX_INDEX; I++ )); do

  SUFFIX="aa${VM_LETTERS[I]}"
  PRIVATE_NETWORK_IP="${IP_PREFIX}.$(( FIRST_IP_OCTET + I ))"

  echo "
# ----------------------------------------------------------------------------
# Creating VM ${SUFFIX} with private network ip ${PRIVATE_NETWORK_IP}
"

  if ! "${CREATE_VM_SCRIPT}" --suffix "${SUFFIX}" --private-network-ip "${PRIVATE_NETWORK_IP}"; then
    echo "
ERROR: failed to create VM for suffix ${SUFFIX}, continuing with the remaining VMs
"
    FAILED_SUFFIXES+=("${SUFFIX}")
  fi

done

# ----------------------------------------------------------------------------
# Summarize

if (( ${#FAILED_SUFFIXES[@]} == 0 )); then
  echo "
Created ${NUMBER_OF_VMS} VM(s).
"
else
  echo "
Created $(( NUMBER_OF_VMS - ${#FAILED_SUFFIXES[@]} )) of ${NUMBER_OF_VMS} VM(s).

Failed suffixes: ${FAILED_SUFFIXES[*]}
"
  exit 1
fi
