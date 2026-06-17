#!/bin/bash

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

if (( $# < 1 )); then
  echo "USAGE $0 <vm suffix> [private-network-ip]

Examples:
  $0 aaa 10.150.0.2
  $0 aab 10.150.0.3
  $0 aac 10.150.0.4
  $0 aad 10.150.0.5
  $0 aae 10.150.0.6
  $0 abm
"
  exit 1
fi

VM_NAME="render-ws-mongodb-16c-64gb-${1}"

NETWORK_INTERFACE="address=,stack-type=IPV4_ONLY"
if (( $# > 1 )); then
  NETWORK_INTERFACE="${NETWORK_INTERFACE},subnet=default,private-network-ip=${2}"
fi

# see https://github.com/JaneliaSciComp/containers/pkgs/container/render-ws-with-mongodb
CONTAINER_IMAGE_VERSION="0.0.19"
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

# See https://cloud.google.com/sdk/gcloud/reference/compute/instances/create
#
# Notes:
# > the --image-project=cos-cloud parameter references Google's dedicated GCP project that publishes all Container-Optimized OS images
# > to see image family options, use gcloud compute images list --project=cos-cloud --no-standard-images
#   > and select something like 'cos-117-lts' or 'cos-125-lts'
#   > the 'cos-stable' family is the latest family, but recommendation is to choose a specific version to ensure consistency
gcloud compute instances create "${VM_NAME}" \
  --boot-disk-auto-delete --boot-disk-device-name=render-ws-mongodb-boot-disk --boot-disk-interface=SCSI \
  --boot-disk-size="${BOOT_DISK_SIZE}" --boot-disk-type=pd-balanced \
  --description='' \
  --labels=container-vm="${VM_NAME}" \
  --machine-type=n2-standard-16 \
  --image-project=cos-cloud \
  --image-family=cos-125-lts \
  --metadata-from-file=user-data="${VM_METADATA_FILE}" \
  --network-interface="${NETWORK_INTERFACE}" \
  --tags=http-server,https-server,lb-health-check,https-egress \
  --zone=us-east4-c

rm "${VM_METADATA_FILE}"

echo "
To open a shell in the container, wait a minute or two for setup and then go to:
  https://console.cloud.google.com/compute/instances?project=janelia-ibeam

Click on the SSH link for the VM and then run:
  docker exec --interactive --tty \"\$(docker ps -q)\" /bin/bash

Finally, to load mongodb data from the shared storage within the container, run
  ./db-restore-collection.sh

To verify that the data was loaded correctly, from within the container or the VM run:
  curl \"http://localhost:8080/render-ws/v1/versionInfo\" | jq '.'
  curl \"http://localhost:8080/render-ws/v1/owners\"
"