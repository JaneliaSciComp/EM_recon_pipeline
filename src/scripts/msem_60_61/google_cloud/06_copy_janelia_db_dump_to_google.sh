#!/bin/bash

# ----------------------------------------------------------------------------
# Copy Janelia MongoDB dump data to
# /mnt/disks/mongodb_dump_fs/dump/janelia on a Google Cloud VM.

set -e

if (( $# != 2 )); then
  echo "
Usage:    $0 <collection dump directory> <google VM>

Examples: $0  mongodb_janelia/dump_render_w61_s070_to_079_r0n_gc  render-ws-mongodb-16c-64gb-aaa
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