#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# ----------------------------------------------------------------------------
# Creates one render-ws-with-mongodb VM per letter by calling create_compute_instance_vm.sh.
#
# VMs are lettered in IP order (a is the first IP, b is the second, ...), matching the
# letter to IP mapping that load_data/setup_load_data_variables.sh uses to identify VMs.

VM_LETTERS=({a..z})
IP_PREFIX="10.150.0"

# the first two addresses in the subnet are reserved, so VM a starts at 10.150.0.2
FIRST_IP_OCTET=2

CREATE_VM_SCRIPT="${SCRIPT_DIR}/create_compute_instance_vm.sh"

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_MAX_NUMBER_OF_VMS="6"

usage() {
  echo "
USAGE $0 [--max-number-of-vms <count>]

  --max-number-of-vms  number of VMs to create, from 1 to ${#VM_LETTERS[@]} (default: ${ARG_MAX_NUMBER_OF_VMS})

Examples:
  $0
  $0 --max-number-of-vms 26
"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --max-number-of-vms)
      ARG_MAX_NUMBER_OF_VMS="${2:?'--max-number-of-vms requires a value'}"
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

if [[ ! "${ARG_MAX_NUMBER_OF_VMS}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --max-number-of-vms must be an integer (not '${ARG_MAX_NUMBER_OF_VMS}')"
  exit 1
fi

if (( ARG_MAX_NUMBER_OF_VMS < 1 || ARG_MAX_NUMBER_OF_VMS > ${#VM_LETTERS[@]} )); then
  echo "ERROR: --max-number-of-vms must be between 1 and ${#VM_LETTERS[@]} (not ${ARG_MAX_NUMBER_OF_VMS})"
  exit 1
fi

if [ ! -x "${CREATE_VM_SCRIPT}" ]; then
  echo "ERROR: ${CREATE_VM_SCRIPT} does not exist or is not executable"
  exit 1
fi

# ----------------------------------------------------------------------------
# Show the plan and confirm before creating anything

echo "
The following ${ARG_MAX_NUMBER_OF_VMS} VM(s) will be created:
"

for (( I=0; I<ARG_MAX_NUMBER_OF_VMS; I++ )); do
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

for (( I=0; I<ARG_MAX_NUMBER_OF_VMS; I++ )); do

  SUFFIX="${VM_LETTERS[I]}"
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
Created ${ARG_MAX_NUMBER_OF_VMS} VM(s).
"
else
  echo "
Created $(( ARG_MAX_NUMBER_OF_VMS - ${#FAILED_SUFFIXES[@]} )) of ${ARG_MAX_NUMBER_OF_VMS} VM(s).

Failed suffixes: ${FAILED_SUFFIXES[*]}
"
  exit 1
fi
