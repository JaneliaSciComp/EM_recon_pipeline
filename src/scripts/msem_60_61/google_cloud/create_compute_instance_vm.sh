#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_SUFFIX=""
ARG_PRIVATE_NETWORK_IP=""
ARG_CORES="16"
ARG_BOOT_DISK_GB="50"

usage() {
  echo "
USAGE $0 --suffix <vm-suffix> [--private-network-ip <ip>] [--cores <16|32|48>] [--boot-disk-gb <gb>]

  --suffix              suffix for the VM name (required, e.g. aaa)
  --private-network-ip  static private ip for the default subnet (optional, e.g. 10.150.0.2)
  --cores               number of vCPUs: 16, 32, or 48 (default: ${ARG_CORES})
  --boot-disk-gb        boot disk size in GB, minimum 50 (default: ${ARG_BOOT_DISK_GB})

Examples:
  $0 --suffix aaa --private-network-ip 10.150.0.2
  $0 --suffix aab --private-network-ip 10.150.0.3
  $0 --suffix abm
  $0 --suffix abn --cores 32
  $0 --suffix abo --cores 48 --boot-disk-gb 200
"
  exit 1
}

if (( $# < 1 )); then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --suffix)
      ARG_SUFFIX="${2:?'--suffix requires a value'}"
      shift 2
      ;;
    --private-network-ip)
      ARG_PRIVATE_NETWORK_IP="${2:?'--private-network-ip requires a value'}"
      shift 2
      ;;
    --cores)
      ARG_CORES="${2:?'--cores requires a value'}"
      shift 2
      ;;
    --boot-disk-gb)
      ARG_BOOT_DISK_GB="${2:?'--boot-disk-gb requires a value'}"
      shift 2
      ;;
    *)
      # Unlike db-dump-google-collections.sh, an unrecognized parameter is an error here because
      # ignoring it would quietly create a VM with the wrong size (and the wrong name).
      echo "ERROR: unrecognized parameter '${1}'"
      usage
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Validate parameters

if [ -z "${ARG_SUFFIX}" ]; then
  echo "ERROR: --suffix is required"
  usage
fi

# The n2-standard machine types have 4GB of memory per vCPU, so the memory size below is derived
# from the core count instead of being a separate parameter.
case "${ARG_CORES}" in
  16|32|48)
    ;;
  *)
    echo "ERROR: --cores must be 16, 32, or 48 (not '${ARG_CORES}')"
    exit 1
    ;;
esac

if [[ ! "${ARG_BOOT_DISK_GB}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --boot-disk-gb must be an integer (not '${ARG_BOOT_DISK_GB}')"
  exit 1
fi

# 50GB is the minimum because the disk needs to hold the container image and any MongoDB data.
if (( ARG_BOOT_DISK_GB < 50 )); then
  echo "ERROR: --boot-disk-gb must be at least 50 (not ${ARG_BOOT_DISK_GB})"
  exit 1
fi

# ----------------------------------------------------------------------------
# Derive VM configuration

# For the vCPU and memory sizes of the n2-standard (4GB per vCPU), n2-highmem (8GB per vCPU),
# and n2-highcpu (1GB per vCPU) machine types, see
#   https://cloud.google.com/compute/docs/general-purpose-machines
# To see what is actually available in this script's zone, use
#   gcloud compute machine-types list --filter="zone:us-east4-c AND name~'^n2-'" --sort-by=guestCpus
MACHINE_TYPE="n2-standard-${ARG_CORES}"
MEMORY_GB=$(( ARG_CORES * 4 ))

VM_NAME="render-ws-mongodb-${ARG_CORES}c-${MEMORY_GB}gb-${ARG_SUFFIX}"

NETWORK_INTERFACE="address=,stack-type=IPV4_ONLY"
if [ -n "${ARG_PRIVATE_NETWORK_IP}" ]; then
  NETWORK_INTERFACE="${NETWORK_INTERFACE},subnet=default,private-network-ip=${ARG_PRIVATE_NETWORK_IP}"
fi

# see https://github.com/JaneliaSciComp/containers/pkgs/container/render-ws-with-mongodb
CONTAINER_IMAGE_VERSION="1.0.6"
CONTAINER_IMAGE="ghcr.io/janeliascicomp/render-ws-with-mongodb:${CONTAINER_IMAGE_VERSION}"

# If boot-disk-size > 10GB, the following warning will be printed but the warning can be ignored:
# - Disk size: '50 GB' is larger than image size: '10 GB'. ...
BOOT_DISK_SIZE="${ARG_BOOT_DISK_GB}GB"

# Create vm_metadata.txt with current container image id.
# The template mounts the shared dump disk from 10.138.206.2 and restarts the container
# if it was started before the dump disk was mounted.
VM_METADATA_FILE="/tmp/vm_metadata.$$.txt"
sed "s@CONTAINER_IMAGE@${CONTAINER_IMAGE}@g" "${SCRIPT_DIR}"/vm_metadata_template.txt > ${VM_METADATA_FILE}

echo "
Creating Google Cloud VM ${VM_NAME} with:
  container image: ${CONTAINER_IMAGE}
  machine type:    ${MACHINE_TYPE} (${ARG_CORES} vCPU, ${MEMORY_GB}GB memory)
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
  --machine-type="${MACHINE_TYPE}" \
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
