#!/bin/bash

set -e

# ----------------------------------------------------------------------------
# Copies local files into the render-ws-with-mongodb container on a Google Cloud VM,
# e.g. to update a container script before a new VM image with the fix is deployed.
#
# The files are copied to a timestamped directory in the VM's home directory with gcloud compute
# scp and then into the running container with docker cp.  The directory is removed after a
# successful copy and left in place after a failure so that the files can be checked.  Changes only last as long as the container does, so a
# recreated container (e.g. after a VM restart) is back to the scripts in its image.

ZONE="us-east4-c"

# create_compute_instance_vm.sh names VMs render-ws-mongodb-<cores>c-<memory>gb-<suffix>,
# so match on the suffix instead of assuming a core count
VM_NAME_PREFIX="render-ws-mongodb"

# the VM letter is prefixed with this to form the name suffix (letter a -> suffix aaa)
VM_SUFFIX_PREFIX="aa"

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_VM=""
ARG_FILES=()
ARG_TARGET_DIR="/var/www/render"
ARG_DRY_RUN="false"

usage() {
  echo "
USAGE $0 --vm <letter> --file <path> [--file <path> ...] [--target-dir <dir>] [--dry-run]

  --vm          letter of the VM to copy to (required, e.g. a for the ${VM_SUFFIX_PREFIX}a VM)
  --file        local file to copy (required, can be specified more than once)
  --target-dir  directory in the container to copy the files to
                (default: ${ARG_TARGET_DIR}, where the image puts the db scripts)
  --dry-run     print the gcloud commands instead of running them

Examples:
  $0 --vm c --file /path/to/render/render-ws-with-mongo-db/db-restore-collections.sh
  $0 --vm c --file db-restore-collections.sh --file remove-collections.sh --dry-run
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
    --file)
      ARG_FILES+=("${2:?'--file requires a value'}")
      shift 2
      ;;
    --target-dir)
      ARG_TARGET_DIR="${2:?'--target-dir requires a value'}"
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

if (( ${#ARG_FILES[@]} == 0 )); then
  echo "ERROR: at least one --file is required"
  usage
fi

# The names end up unquoted in the command run on the VM, so they are limited to characters
# that no shell treats specially.
FILE_NAMES=()
for FILE in "${ARG_FILES[@]}"; do
  if [ ! -f "${FILE}" ]; then
    echo "ERROR: --file ${FILE} does not exist or is not a regular file"
    exit 1
  fi
  FILE_NAME=$(basename "${FILE}")
  if [[ ! "${FILE_NAME}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: --file name '${FILE_NAME}' may only contain letters, digits, '.', '_', and '-'"
    exit 1
  fi
  for EXISTING_NAME in "${FILE_NAMES[@]}"; do
    if [ "${EXISTING_NAME}" = "${FILE_NAME}" ]; then
      echo "ERROR: more than one --file is named ${FILE_NAME}, but they are all copied to the same directory"
      exit 1
    fi
  done
  FILE_NAMES+=("${FILE_NAME}")
done

if [[ ! "${ARG_TARGET_DIR}" =~ ^/[A-Za-z0-9._/-]*$ ]]; then
  echo "ERROR: --target-dir must be an absolute path of letters, digits, '.', '_', '-', and '/' (not '${ARG_TARGET_DIR}')"
  exit 1
fi

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
# Run by the login shell on the VM after the files have been copied to the staging directory.
# Scripts are made executable the same way the Dockerfile does (chmod 755 *.sh).
#
# The copy steps run in a subshell so that any failure (including the exits in it) falls
# through to the message about where the files were left instead of ending the remote shell.

# e.g. copy_to_container.20261002-201500 (relative to the home directory of the ssh user)
STAGING_DIR="copy_to_container.$(date '+%Y%m%d-%H%M%S')"

TARGET_FILES=()
CHMOD_FILES=()
for FILE_NAME in "${FILE_NAMES[@]}"; do
  TARGET_FILES+=("${ARG_TARGET_DIR}/${FILE_NAME}")
  if [[ "${FILE_NAME}" == *.sh ]]; then
    CHMOD_FILES+=("${ARG_TARGET_DIR}/${FILE_NAME}")
  fi
done

CHMOD_COMMAND=""
if (( ${#CHMOD_FILES[@]} > 0 )); then
  CHMOD_COMMAND="docker exec \"\${C}\" chmod 755 ${CHMOD_FILES[*]} &&"
fi

REMOTE_COMMAND="if ! (
  cd ${STAGING_DIR} &&
  C=\$(docker ps -q) &&
  if [ -z \"\${C}\" ] || [ \$(echo \"\${C}\" | wc -l) -ne 1 ]; then echo 'ERROR: expected exactly one running container'; exit 1; fi &&
  for F in ${FILE_NAMES[*]}; do docker cp \"\${F}\" \"\${C}:${ARG_TARGET_DIR}/\${F}\" || exit 1; done &&
  ${CHMOD_COMMAND}
  docker exec \"\${C}\" ls -l ${TARGET_FILES[*]}
); then
  echo \"ERROR: copy failed, the files were left in \${HOME}/${STAGING_DIR} on the VM\"
  exit 1
fi
rm -r ${STAGING_DIR}"

# ----------------------------------------------------------------------------
# Copy

if [ "${ARG_DRY_RUN}" = "true" ]; then
  echo "
Would copy to ${VM_NAME} in ${ZONE} with:

  gcloud compute scp --recurse <local copy of ${STAGING_DIR}> ${VM_NAME}: --zone=${ZONE}

where ${STAGING_DIR} has: ${FILE_NAMES[*]}

and then have its shell run:

${REMOTE_COMMAND}
"
  exit 0
fi

# gcloud compute scp cannot create a directory on the VM, so the staging directory is built
# locally and copied with --recurse (the trailing colon copies it into the ssh user's home)
LOCAL_STAGING_PARENT=$(mktemp -d)
trap 'rm -rf "${LOCAL_STAGING_PARENT}"' EXIT
mkdir "${LOCAL_STAGING_PARENT}/${STAGING_DIR}"
cp -p "${ARG_FILES[@]}" "${LOCAL_STAGING_PARENT}/${STAGING_DIR}/"

printf "\ncopying %d file(s) to ~/%s on %s in %s ...\n\n" "${#ARG_FILES[@]}" "${STAGING_DIR}" "${VM_NAME}" "${ZONE}"

gcloud compute scp --recurse "${LOCAL_STAGING_PARENT}/${STAGING_DIR}" "${VM_NAME}:" --zone="${ZONE}"

printf "\ncopying into the container's %s directory ...\n\n" "${ARG_TARGET_DIR}"

gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --command="${REMOTE_COMMAND}"

printf "\ndone\n\n"
