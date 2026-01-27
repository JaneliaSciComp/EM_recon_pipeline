#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

# only list recently modified volumes (default is 70 days)
MODIFICATION_DAYS="${1:-70}"
GROUP="${2:-cellmap}"

BASE_ALIGNMENT_DIR="/groups/${GROUP}/${GROUP}/render/alignment"

printf "\nsearching for %s volumes\nwith log files modified in the past %s days\n" "${BASE_ALIGNMENT_DIR}" "${MODIFICATION_DAYS}"

mapfile -t VOLUMES < <(
  find ${BASE_ALIGNMENT_DIR}/*/logs -type f -mtime -${MODIFICATION_DAYS} -printf '%p\n' \
  | awk -F'/logs/' '{split($1,a,"/"); print a[length(a)]}' \
  | sort -u
)

printf "\nWhich volume would you like to clean-up?\n"
select VOLUME in "${VOLUMES[@]}"; do
  [[ -n "${VOLUME}" ]] && break
done

VOLUME_NRS_DIR="/nrs/${GROUP}/data/${VOLUME}"

printf "\nContents of %s:\n" "${VOLUME_NRS_DIR}"
ls -l "${VOLUME_NRS_DIR}"

for DIR in align ${VOLUME}.n5 raw tiles_destreak; do

  FULL_DIR="${VOLUME_NRS_DIR}/${DIR}"

  if [ -d "${FULL_DIR}" ]; then
    printf "\nContents of %s:\n" "${FULL_DIR}"
    ls -l "${FULL_DIR}"
    echo
    read -r -p "Do you want to REMOVE ${FULL_DIR}? [y/n] " REPLY
    if [[ "${REPLY}" == "y" || "${REPLY}" == "Y" ]]; then
        nohup rm -rf "${FULL_DIR}" &
    fi
  else
    printf "\nWARNING: %s not found\n" "${FULL_DIR}"
  fi

done

printf "\nThe following removals are now running in the background:\n"
ps -ef | grep "${VOLUME}"

echo