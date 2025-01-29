#!/bin/bash

set -e

FIBSEMXFER_DIR="/groups/fibsem/home/fibsemxfer"

EMRP_ROOT="${FIBSEMXFER_DIR}/git/EM_recon_pipeline"
VERSIONED_TRANSFER_INFO_DIR="${EMRP_ROOT}/src/resources/transfer_info"
TRANSFER_CONFIG_DIR="${FIBSEMXFER_DIR}/config"

if (( $# != 2 )); then
  echo "USAGE $0 <alignment-id> <first-comment-text-file>  (e.g. jrc_velella-b8-1 issue.txt)"
  exit 1
fi

ALIGNMENT_ID="$1"
RENDER_PROJECT=${ALIGNMENT_ID//-/_}  # replace all '-' with '_'
VOLUME_TRANSFER_JSON_FILE="volume_transfer_info.${ALIGNMENT_ID}.json"

FIRST_COMMENT_TEXT_FILE="${2}"
if [ ! -f "${FIRST_COMMENT_TEXT_FILE}" ]; then
  echo "ERROR: ${FIRST_COMMENT_TEXT_FILE} not found"
  exit 1
fi

if [ "${USER}" == "fibsemxfer" ]; then
  echo "ERROR: This script should be run as a user other than fibsemxfer.
The script will ask for the fibsemxfer password when it tries to connect to the scope.
"
  exit 1
fi

# ---------------------------
# parse data from GitHub issue first comment file ...

PARSED_VALUES=$(awk '
  BEGIN { previous_line = ""; }
  {
    if (previous_line ~ /Scope identifier/)                                             { scope_data_set_id = $0;
    } else if (previous_line ~ /Scope host/)                                            { scope_host = $0;
    } else if (previous_line ~ /Root directory path/)                                   { root_dat_path = $0;
    } else if (previous_line ~ /Scope first dat name/)                                  { first_dat = $0;
    } else if (previous_line ~ /Scope last dat name/)                                   { last_dat = $0;
    } else if (previous_line ~ /Number of columns of images/)                           { number_columns = $0;
    } else if (previous_line ~ /Number of rows of images/)                              { number_rows = $0;
    } else if (previous_line ~ /XY nanometers per pixel/)                               { xy_nm_per_pixel = $0;
    } else if (previous_line ~ /Z nanometers per pixel/)                                { z_nm_per_pixel = $0;
    } else if (previous_line ~ /Group that will pay for data storage/)                  { storage_group = $0;
    } else if (previous_line ~ /Group that will pay for compute cluster time/)          { compute_group = $0;
    } else if (previous_line ~ /Generate preview volumes while imaging is in progress/) { generate_preview = $0;
    }
    previous_line = $0;
  }
  END {
    printf("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n",
           scope_data_set_id, scope_host, root_dat_path, first_dat, last_dat, number_columns, number_rows,
           xy_nm_per_pixel, z_nm_per_pixel, storage_group, compute_group, generate_preview);
  }
' "${FIRST_COMMENT_TEXT_FILE}")

IFS='|' read -r -a PARSED_VALUES_ARRAY <<< "${PARSED_VALUES}"

#for VALUE in "${PARSED_VALUES_ARRAY[@]}"; do
#  echo "${VALUE}"
#done

SCOPE_DATA_SET_ID="${PARSED_VALUES_ARRAY[0]}"
SCOPE_HOST="${PARSED_VALUES_ARRAY[1]}"
ROOT_DAT_PATH="${PARSED_VALUES_ARRAY[2]}"    # /cygdrive/e/Images/Cellmap
FIRST_DAT="${PARSED_VALUES_ARRAY[3]}"

LAST_DAT="${PARSED_VALUES_ARRAY[4]}"
if [[ "${LAST_DAT}" == Merlin* ]]; then
  QUOTED_LAST_DAT="@${LAST_DAT}@"
else
  QUOTED_LAST_DAT="null"
fi

NUMBER_COLUMNS="${PARSED_VALUES_ARRAY[5]}"
NUMBER_ROWS="${PARSED_VALUES_ARRAY[6]}"
XY_NM_PER_PIXEL="${PARSED_VALUES_ARRAY[7]}"
Z_NM_PER_PIXEL="${PARSED_VALUES_ARRAY[8]}"
STORAGE_GROUP="${PARSED_VALUES_ARRAY[9]}"
COMPUTE_GROUP="${PARSED_VALUES_ARRAY[10]}"

GENERATE_PREVIEW="${PARSED_VALUES_ARRAY[11]}"
if [ "${GENERATE_PREVIEW}" == "Yes" ]; then
  LAST_TASKS="@APPLY_FIBSEM_CORRECTION_TRANSFORM@, @EXPORT_PREVIEW_VOLUME@"
else
  LAST_TASKS="@APPLY_FIBSEM_CORRECTION_TRANSFORM@"
fi

# ---------------------------
# pull data from first keep file on scope ...

echo "
Checking keep files on ${SCOPE_HOST}.  Please enter the fibsemxfer user password when prompted.
"

set +e

ALL_KEEP_FILES=$(
  su -c "ssh ${SCOPE_HOST} 'ls /cygdrive/d/UploadFlags'" fibsemxfer |
  grep "keep"
)

set -e

if [ -z "${ALL_KEEP_FILES}" ]; then
  echo "
ERROR: no keep files found on '${SCOPE_HOST}'
"
  exit 1
fi

unset FIRST_KEEP_FILE
for KEEP_FILE in ${ALL_KEEP_FILES}; do
  if [[ "${KEEP_FILE}" == "${SCOPE_DATA_SET_ID}"*"${FIRST_DAT}^keep" ]]; then
    FIRST_KEEP_FILE="${KEEP_FILE}"
    break
  fi
done

if [ -z "${FIRST_KEEP_FILE}" ]; then

  echo "
ERROR: no keep file found for data set '${SCOPE_DATA_SET_ID}' and dat file '${FIRST_DAT}' on '${SCOPE_HOST}'

Here are the first 10 files in /cygdrive/d/UploadFlags on ${SCOPE_HOST}:
$(echo "${ALL_KEEP_FILES}" | head -n 10)
"
  exit 1

else

  echo "
Using the following keep file to validate values:
  ${FIRST_KEEP_FILE}
"

fi

# rc_mosquito-stylet-1^E^^Images^Cellmap^Y2025^M01^D21^Merlin-6284_25-01-21_134947_0-0-0.dat^keep
IFS='^' read -r -a FIRST_KEEP_FILE_ARRAY <<< "${FIRST_KEEP_FILE}"
LOWER_DRIVE=$(echo "${FIRST_KEEP_FILE_ARRAY[1]}" | tr '[:upper:]' '[:lower:]')

# /cygdrive/e/Images/Cellmap
FIRST_KEEP_FILE_ROOT_PATH="/cygdrive/${LOWER_DRIVE}/${FIRST_KEEP_FILE_ARRAY[3]}/${FIRST_KEEP_FILE_ARRAY[4]}"

if [ "${FIRST_KEEP_FILE_ROOT_PATH}" != "${ROOT_DAT_PATH}" ]; then
  echo "
  ERROR: root dat paths do not match

    issue path:     '${ROOT_DAT_PATH}'
    keep file path: '${FIRST_KEEP_FILE_ROOT_PATH}'
"
else

  echo "
Root dat paths match: ${ROOT_DAT_PATH}
"

fi

# ---------------------------
# setup /groups path information ...

GROUPS_DATA_PARENT_DIR="/groups/${STORAGE_GROUP}/${STORAGE_GROUP}/data"
if [ ! -d "${GROUPS_DATA_PARENT_DIR}" ]; then
  echo "ERROR: ${GROUPS_DATA_PARENT_DIR} not found"
  exit 1
fi

GROUPS_VOLUME_DIR="${GROUPS_DATA_PARENT_DIR}/${ALIGNMENT_ID}"
if [ -d "${GROUPS_VOLUME_DIR}" ]; then
  echo "ERROR: ${GROUPS_VOLUME_DIR} already exists"
  exit 1
fi

CLUSTER_RAW_DAT_DIR="${GROUPS_VOLUME_DIR}/dat"
CLUSTER_RAW_H5_DIR="${GROUPS_VOLUME_DIR}/raw"

# ---------------------------
# setup /nrs path information ...

NRS_DATA_PARENT_DIR="/nrs/${STORAGE_GROUP}/data"
if [ ! -d "${NRS_DATA_PARENT_DIR}" ]; then
  echo "ERROR: ${NRS_DATA_PARENT_DIR} not found"
  exit 1
fi

NRS_VOLUME_DIR="${NRS_DATA_PARENT_DIR}/${ALIGNMENT_ID}"
if [ -d "${NRS_VOLUME_DIR}" ]; then
  echo "ERROR: ${NRS_VOLUME_DIR} already exists"
  exit 1
fi

ALIGN_H5_DIR="${NRS_VOLUME_DIR}/align"

unset EXPORT_N5_DIR
if [ "${GENERATE_PREVIEW}" == "Yes" ]; then
  EXPORT_N5_DIR="${NRS_VOLUME_DIR}/${ALIGNMENT_ID}.n5"
fi


# ---------------------------
# setup /nearline path information ...

NEARLINE_DATA_PARENT_DIR="/nearline/${STORAGE_GROUP}/data"
if [ ! -d "${NEARLINE_DATA_PARENT_DIR}" ]; then
  echo "ERROR: ${NEARLINE_DATA_PARENT_DIR} not found"
  exit 1
fi

NEARLINE_VOLUME_DIR="${NEARLINE_DATA_PARENT_DIR}/${ALIGNMENT_ID}"
if [ -d "${NEARLINE_VOLUME_DIR}" ]; then
  echo "ERROR: ${NEARLINE_VOLUME_DIR} already exists"
  exit 1
fi

NEARLINE_RAW_H5_DIR="${NEARLINE_VOLUME_DIR}/raw"

# ---------------------------
# create the paths ...

function setupTransferPath() {
  local TRANSFER_PATH="$1"
  TRANSFER_PATH_PARENT=$(dirname "${TRANSFER_PATH}")
  mkdir -p "${TRANSFER_PATH}"
  chmod 2775 "${TRANSFER_PATH_PARENT}" "${TRANSFER_PATH}"
  ls -ald "${TRANSFER_PATH_PARENT}" "${TRANSFER_PATH}"
  echo "created ${TRANSFER_PATH}"
}

echo "
Ready to create the following paths:

  ${CLUSTER_RAW_DAT_DIR}
  ${CLUSTER_RAW_H5_DIR}
  ${ALIGN_H5_DIR}
  ${EXPORT_N5_DIR}
  ${NEARLINE_RAW_H5_DIR}
"

read -p "Is it ok to create them (y | n)? " -n 1 -r CREATE_PATHS

  echo "
"
if [[ ! ${CREATE_PATHS} =~ ^[Yy]$ ]]; then
  exit 1
fi

setupTransferPath "${CLUSTER_RAW_DAT_DIR}"
setupTransferPath "${CLUSTER_RAW_H5_DIR}"
setupTransferPath "${ALIGN_H5_DIR}"

if [ "${GENERATE_PREVIEW}" == "Yes" ]; then
  setupTransferPath "${EXPORT_N5_DIR}"
else
  EXPORT_N5_DIR="not_applicable" # set value that gets placed in JSON but is ignored
fi

setupTransferPath "${NEARLINE_RAW_H5_DIR}"

echo "{
    @transfer_id@: @${STORAGE_GROUP}::${ALIGNMENT_ID}::${SCOPE_HOST}@,
    @scope_data_set@: {
        @host@: @${SCOPE_HOST}@,
        @root_dat_path@: @${ROOT_DAT_PATH}@,
        @root_keep_path@: @/cygdrive/d/UploadFlags@,
        @data_set_id@: @${SCOPE_DATA_SET_ID}@,
        @rows_per_z_layer@: ${NUMBER_ROWS},
        @columns_per_z_layer@: ${NUMBER_COLUMNS},
        @first_dat_name@: @${FIRST_DAT}@,
        @last_dat_name@: ${QUOTED_LAST_DAT},
        @dat_x_and_y_nm_per_pixel@: ${XY_NM_PER_PIXEL},
        @dat_z_nm_per_pixel@: ${Z_NM_PER_PIXEL},
        @dat_tile_overlap_microns@: 2
    },
    @cluster_root_paths@: {
        @raw_dat@: @${CLUSTER_RAW_DAT_DIR}@,
        @raw_h5@: @${CLUSTER_RAW_H5_DIR}@,
        @align_h5@: @${ALIGN_H5_DIR}@,
        @export_n5@: @${EXPORT_N5_DIR}@
    },
    @archive_root_paths@: {
        @raw_h5@: @${NEARLINE_VOLUME_DIR}/raw@
    },
    @max_mipmap_level@: 7,
    @render_data_set@: {
        @owner@: @${STORAGE_GROUP}@,
        @project@: @${RENDER_PROJECT}@,
        @stack@: @v1_acquire@,
        @restart_context_layer_count@: 1,
        @mask_width@: 100,
        @connect@: {
            @host@: @10.40.3.113@,
            @port@: 8080,
            @web_only@: true,
            @validate_client@: false,
            @client_scripts@: @/groups/flyTEM/flyTEM/render/bin@,
            @memGB@: @1G@
        }
    },
    @transfer_tasks@: [
        @COPY_SCOPE_DAT_TO_CLUSTER@,
        @GENERATE_CLUSTER_H5_RAW@,
        @GENERATE_CLUSTER_H5_ALIGN@,
        @REMOVE_DAT_AFTER_H5_CONVERSION@,
        @ARCHIVE_H5_RAW@,
        @IMPORT_H5_ALIGN_INTO_RENDER@,
        ${LAST_TASKS}
    ],
    @cluster_job_project_for_billing@: @${COMPUTE_GROUP}@,
    @number_of_dats_converted_per_hour@: 80,
    @number_of_preview_workers@: 10
}" | sed 's/@/"/g' > "${TRANSFER_CONFIG_DIR}/${VOLUME_TRANSFER_JSON_FILE}"

chmod 644 "${TRANSFER_CONFIG_DIR}/${VOLUME_TRANSFER_JSON_FILE}"

echo "Created ${TRANSFER_CONFIG_DIR}/${VOLUME_TRANSFER_JSON_FILE}

Please don't forget to commit and push this file to the EM_recon_pipeline repository in:
  src/resources/transfer_info/${STORAGE_GROUP}/${VOLUME_TRANSFER_JSON_FILE}
"
