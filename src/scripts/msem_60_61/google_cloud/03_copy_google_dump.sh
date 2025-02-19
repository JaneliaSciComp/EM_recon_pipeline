#!/bin/bash

# ----------------------------------------------------------------------------
# Copy MongoDB dump files from a Google VM to the local machine.

set -e

if (( $# != 1 )); then
  echo "USAGE $0 <google VM>   (e.g. render-ws-mongodb-8c-32gb-abc)"
  exit 1
fi

GOOGLE_VM="${1}"
ZONE="us-east4-c"

BASE_GOOGLE_DUMP_DIR="/mnt/disks/mongodb_dump_fs/dump"
VM_DUMP_DIR_PATTERN="${BASE_GOOGLE_DUMP_DIR}/render*"

DUMP_TYPES=("archive" "collection")
PS3="Which type of dump do you want to copy? "
select DUMP_TYPE in "${DUMP_TYPES[@]}"; do
  break
done

if [ "${DUMP_TYPE}" == "archive" ]; then
  SELECTION_NAME="archive file"
  mapfile -t VM_DUMPS < <(gcloud compute ssh "${GOOGLE_VM}" --zone=${ZONE} --command "find ${VM_DUMP_DIR_PATTERN} -name '*.dump.gz' | sort -u")
else
  SELECTION_NAME="collection directory"
  mapfile -t VM_DUMPS < <(gcloud compute ssh "${GOOGLE_VM}" --zone=${ZONE} --command "find ${VM_DUMP_DIR_PATTERN} -type d -mindepth 2 -maxdepth 2 | sort -u")
fi

if [ ${#VM_DUMPS[@]} -eq 0 ]; then
    echo "ERROR: no ${SELECTION_NAME} dumps found in ${GOOGLE_VM}:${VM_DUMP_DIR_PATTERN}"
    exit 1
fi

PS3="Please enter the number of the dump ${SELECTION_NAME} you want to download: "
select VM_DUMP in "${VM_DUMPS[@]}"; do
  break
done

# VM_DUMP=/mnt/disks/mongodb_dump_fs/dump/render-ws-mongodb-8c-32gb-abc/20250216_213836.match.dump.gz
# VM_DUMP=/mnt/disks/mongodb_dump_fs/dump/render-ws-mongodb-8c-32gb-abc/20250217_215500/match
VM_DUMP_FULL_PARENT_DIR=$(dirname "${VM_DUMP}")
VM_DUMP_PARENT_BASENAME=$(basename "${VM_DUMP_FULL_PARENT_DIR}")

if [ "${DUMP_TYPE}" == "archive" ]; then

  VM_NAME="${VM_DUMP_PARENT_BASENAME}"
  mkdir -p "${VM_NAME}"

  echo "
  Running:
    gcloud compute scp ${GOOGLE_VM}:${VM_DUMP} ${VM_NAME} --zone=${ZONE}
  "
  gcloud compute scp "${GOOGLE_VM}:${VM_DUMP}" "${VM_NAME}" --zone=${ZONE}

else

  VM_DIR=$(dirname "${VM_DUMP_FULL_PARENT_DIR}")
  VM_NAME=$(basename "${VM_DIR}")
  LOCAL_DUMP_DIR="${VM_NAME}/${VM_DUMP_PARENT_BASENAME}"

  mkdir -p "${LOCAL_DUMP_DIR}"

  echo "
  Running:
    gcloud compute scp --recurse ${GOOGLE_VM}:${VM_DUMP} ${LOCAL_DUMP_DIR} --zone=${ZONE}
  "
  gcloud compute scp --recurse "${GOOGLE_VM}:${VM_DUMP}" "${LOCAL_DUMP_DIR}" --zone=${ZONE}

fi
