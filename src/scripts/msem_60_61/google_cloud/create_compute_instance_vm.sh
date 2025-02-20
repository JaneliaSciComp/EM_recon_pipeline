#!/bin/bash

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

if (( $# < 1 )); then
  echo "USAGE $0 <vm suffix>   (e.g. abc)"
  exit 1
fi

VM_NAME="render-ws-mongodb-8c-32gb-${1}"

# see https://github.com/JaneliaSciComp/containers/pkgs/container/render-ws-with-mongodb
CONTAINER_IMAGE_VERSION="0.0.5"
CONTAINER_IMAGE="ghcr.io/janeliascicomp/render-ws-with-mongodb:${CONTAINER_IMAGE_VERSION}"

# The boot disk needs to be big enough to hold the container image and any MongoDB data.
# If boot-disk-size > 10GB, the following warning will be printed but the warning can be ignored:
# - Disk size: '50 GB' is larger than image size: '10 GB'. ...
BOOT_DISK_SIZE="50GB"

# Create vm_metadata.txt with current container image id.
# The template mounts the shared dump disk from 10.138.206.2 and restarts the container
# if it was started before the dump disk was mounted.
VM_METADATA_FILE="/tmp/vm_metadata.$$.txt"
sed "s@CONTAINER_IMAGE@${CONTAINER_IMAGE}@g" "${SCRIPT_DIR}"/vm_metadata_template.txt > ${VM_METADATA_FILE}

echo "
Creating Google Cloud VM ${VM_NAME} with:
  container image: ${CONTAINER_IMAGE}
  boot disk size:  ${BOOT_DISK_SIZE}
  metadata file:   ${VM_METADATA_FILE}

Metadata is:
$(cat ${VM_METADATA_FILE})

"

# see https://cloud.google.com/sdk/gcloud/reference/compute/instances/create-with-container
gcloud compute instances create-with-container "${VM_NAME}" \
  --boot-disk-auto-delete --boot-disk-device-name=render-ws-mongodb-boot-disk --boot-disk-interface=SCSI \
  --boot-disk-size="${BOOT_DISK_SIZE}" --boot-disk-type=pd-balanced \
  --container-image="${CONTAINER_IMAGE}" \
  --container-mount-host-path=host-path=/mnt/disks/mongodb_dump_fs,mount-path=/mnt/disks/mongodb_dump_fs,mode=rw \
  --container-privileged --container-restart-policy=never --container-stdin --container-tty \
  --description='' \
  --labels=container-vm="${VM_NAME}" \
  --machine-type=n2-standard-8 \
  --metadata-from-file=user-data="${VM_METADATA_FILE}" \
  --network-interface=address=,stack-type=IPV4_ONLY \
  --tags=http-server,https-server,lb-health-check,https-egress \
  --zone=us-east4-c

rm "${VM_METADATA_FILE}"

echo "
To open a shell in the container, wait a minute or two for setup and then go to:
  https://console.cloud.google.com/compute/instances?project=janelia-ibeam

Click on the SSH link for the VM and then run:
  docker exec --interactive --tty \"\$(docker ps -q)\" /bin/bash

Finally, to load mongodb data from the shared storage within the container, run
  ./db-restore-janelia.sh
or:
  ./db-restore-google.sh

To verify that the data was loaded correctly, from within the container or the VM run:
  curl \"http://localhost:8080/render-ws/v1/versionInfo\"
  curl \"http://localhost:8080/render-ws/v1/owners\"
"