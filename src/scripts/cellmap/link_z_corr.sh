#!/bin/bash

#  To run every 10 minutes on renderer-data4 without trying to mail stdout/stderr:
#
#    crontab -e
#      */10 * * * * /groups/fibsem/home/fibsemxfer/git/EM_recon_pipeline/src/scripts/cellmap/link_z_corr.sh >/dev/null 2>&1
#
#  Crontab file is saved to /var/spool/cron/trautmane

set -e

BASE_PLOT_DIR="/opt/local/jetty_base/webapps/z_corr_plots"

for GROUP in cellmap fibsem reiser; do
  cd "${BASE_PLOT_DIR}/${GROUP}"
  for Z_CORR_BASE_DIR in /nrs/"${GROUP}"/data/*/z_corr/"${GROUP}"/*; do
    NAME=$(basename "${Z_CORR_BASE_DIR}")
    if [ -e "${NAME}" ]; then
      echo "${NAME} already exists"
    else
      ln -s "${Z_CORR_BASE_DIR}" .
      ls -ald "${NAME}"
    fi
  done
done
