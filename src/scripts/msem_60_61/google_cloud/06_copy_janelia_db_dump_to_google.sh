#!/bin/bash

# ----------------------------------------------------------------------------
# Copy Janelia MongoDB dump data to
# /mnt/disks/mongodb_dump_fs/dump/janelia on a Google Cloud VM.

set -e

if (( $# != 2 )); then
  echo "
Usage:    $0 <collection dump directory> <google VM>

Examples: $0 dump_20250220_155604 render-ws-mongodb-8c-32gb-abd
"
  exit 1
fi

LOCAL_DUMP_DIR="${1}"
GOOGLE_VM="${2}"

if [ ! -d "${LOCAL_DUMP_DIR}" ]; then
  echo "ERROR: ${LOCAL_DUMP_DIR} not found"
  exit 1
fi

GOOGLE_BASE_JANELIA_DUMP_DIR="/mnt/disks/mongodb_dump_fs/dump/janelia"
ZONE="us-east4-c"

echo "
Running:
  gcloud compute scp --recurse ${LOCAL_DUMP_DIR} ${GOOGLE_VM}:${GOOGLE_BASE_JANELIA_DUMP_DIR} --zone=${ZONE}
"
gcloud compute scp --recurse "${LOCAL_DUMP_DIR}" "${GOOGLE_VM}:${GOOGLE_BASE_JANELIA_DUMP_DIR}" --zone=${ZONE}