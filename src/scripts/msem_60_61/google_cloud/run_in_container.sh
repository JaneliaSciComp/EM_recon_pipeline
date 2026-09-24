#!/bin/bash

# ----------------------------------------------------------------------------
# Runs a command inside the render-ws-with-mongodb container on a Google Cloud VM
# without going through the Cloud Console SSH window.
#
# A pseudo-terminal is allocated end to end (ssh -t plus docker exec -it) so that
# scripts which prompt for input (e.g. remove-collections.sh, db-restore-collections.sh)
# behave exactly as they do in a browser SSH session.

ZONE="us-east4-c"

# create_compute_instance_vm.sh names VMs render-ws-mongodb-<cores>c-<memory>gb-<suffix>,
# so match on the suffix instead of assuming a core count
VM_NAME_PREFIX="render-ws-mongodb"

# the VM letter is prefixed with this to form the name suffix (letter a -> suffix aaa)
VM_SUFFIX_PREFIX="aa"

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_VM=""
ARG_COMMAND=""
ARG_DRY_RUN="false"

usage() {
  echo "
USAGE $0 --vm <letter> [--command <command>] [--dry-run]

  --vm       letter of the VM to connect to (required, e.g. a for the ${VM_SUFFIX_PREFIX}a VM)
  --command  command to run inside the container (optional, opens a shell when omitted)
  --dry-run  print the gcloud command instead of running it

Examples:
  $0 --vm a
  $0 --vm a --command './list-stacks.sh'
  $0 --vm c --command './remove-collections.sh --db render --method remove --items \"1 3 5\"'
  $0 --vm c --command './db-restore-collections.sh --pattern \"janelia/00_gc/.*s170\"' --dry-run
"
  exit 1
}

if (( $# < 1 )); then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --vm)
      ARG_VM="${2:?'--vm requires a value'}"
      shift 2
      ;;
    --command)
      ARG_COMMAND="${2:?'--command requires a value'}"
      shift 2
      ;;
    --dry-run)
      ARG_DRY_RUN="true"
      shift
      ;;
    *)
      echo "ERROR: unrecognized parameter '${1}'"
      usage
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Validate parameters

# create_batch_of_vms.sh accepts either case for VM letters, so do the same here
# (tr instead of ${ARG_VM,,} because macOS still ships bash 3.2)
ARG_VM=$(printf '%s' "${ARG_VM}" | tr '[:upper:]' '[:lower:]')

if [[ ! "${ARG_VM}" =~ ^[a-z]$ ]]; then
  echo "ERROR: --vm must be a single letter from a to z (not '${ARG_VM}')"
  exit 1
fi

VM_SUFFIX="${VM_SUFFIX_PREFIX}${ARG_VM}"

# ----------------------------------------------------------------------------
# Find the VM

# a read loop instead of mapfile because macOS still ships bash 3.2
MATCHING_VM_NAMES=()
while IFS= read -r MATCHING_VM_NAME; do
  if [ -n "${MATCHING_VM_NAME}" ]; then
    MATCHING_VM_NAMES+=("${MATCHING_VM_NAME}")
  fi
done < <(
  gcloud compute instances list \
    --zones="${ZONE}" \
    --filter="name ~ ^${VM_NAME_PREFIX}-.*-${VM_SUFFIX}\$" \
    --format="value(name)")

if (( ${#MATCHING_VM_NAMES[@]} == 0 )); then
  echo "ERROR: no ${VM_NAME_PREFIX} VM with suffix '${VM_SUFFIX}' exists in zone ${ZONE}"
  exit 1
fi

if (( ${#MATCHING_VM_NAMES[@]} > 1 )); then
  printf "ERROR: %d VMs have suffix '%s' in zone %s:\n" "${#MATCHING_VM_NAMES[@]}" "${VM_SUFFIX}" "${ZONE}"
  printf "  %s\n" "${MATCHING_VM_NAMES[@]}"
  exit 1
fi

VM_NAME="${MATCHING_VM_NAMES[0]}"

# ----------------------------------------------------------------------------
# Build the remote command
#
# The command is evaluated by three shells: the login shell on the VM, then bash inside
# the container.  Single quoting it for the VM shell keeps it as one argument for
# 'docker exec ... /bin/bash -c', and any single quotes it contains are escaped as '\''
# so that values like --items 'all' survive.

if [ -z "${ARG_COMMAND}" ]; then
  REMOTE_COMMAND="docker exec -it \"\$(docker ps -q)\" /bin/bash"
else
  ESCAPED_COMMAND="${ARG_COMMAND//\'/\'\\\'\'}"
  REMOTE_COMMAND="docker exec -it \"\$(docker ps -q)\" /bin/bash -c '${ESCAPED_COMMAND}'"
fi

# ----------------------------------------------------------------------------
# Connect
#
# '-- -t' passes -t to ssh, which does not allocate a pseudo-terminal on its own
# when a command is given.

if [ "${ARG_DRY_RUN}" = "true" ]; then
  echo "
Would connect to ${VM_NAME} in ${ZONE} with 'gcloud compute ssh ... -- -t'
and have its shell run:

  ${REMOTE_COMMAND}
"
  exit 0
fi

echo "
Connecting to ${VM_NAME} in ${ZONE} ...
"

exec gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --command="${REMOTE_COMMAND}" -- -t
