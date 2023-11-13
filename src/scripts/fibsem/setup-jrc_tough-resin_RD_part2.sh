VOLUME="jrc_tough-resin_RD_part2"

BASE_NRS_DIR="/nrs/fibsem/data/${VOLUME}"
DAT_TRANSFER_DIR="/groups/flyem/home/flyem/bin/dat_transfer/2022"
EMRP_DIR="/groups/flyem/data/render/git/EM_recon_pipeline"

# ---------------
# 1. setup nrs directories

mkdir -p ${BASE_NRS_DIR}/dat_xfer ${BASE_NRS_DIR}/dat
chmod -R 2775 ${BASE_NRS_DIR}

# ---------------
# 2. use Globus to transfer dat files from nearline to ${BASE_NRS_DIR}/dat_xfer

# ---------------
# 3. organize dat files into "standard" dat sub-directories and remove remaining dat_xfer stuff (e.g. png files)

${DAT_TRANSFER_DIR}/89_organize_dats.sh ${BASE_NRS_DIR}/dat_xfer ${BASE_NRS_DIR}/dat
rm -rf ${BASE_NRS_DIR}/dat_xfer

# ---------------
# 4. create transfer info json file with limited transfer_tasks and copy to ${DAT_TRANSFER_DIR}/config
#
#    https://github.com/JaneliaSciComp/EM_recon_pipeline/blob/main/src/resources/transfer_info/fibsem/volume_transfer_info.jrc_tough-resin_RD_part2.json

cp ${EMRP_DIR}/src/resources/transfer_info/fibsem/volume_transfer_info.${VOLUME}.json ${DAT_TRANSFER_DIR}/config

# ---------------
# 5. wait for convert_dat jobs to run and finish
#    - jenkins runs are every 2 hours
#    - last dat z layer will only be converted if dat files are older than 1 hour

# ---------------
# 6. setup alignment scripts for volume and archive volume transfer info json file

${DAT_TRANSFER_DIR}/11_setup_volume.sh
mv ${DAT_TRANSFER_DIR}/config/volume_transfer_info.${VOLUME}.json ${DAT_TRANSFER_DIR}/config/complete

# ---------------
# 7. run alignment pipeline scripts in /groups/fibsem/fibsem/render/align/${VOLUME}

cd /groups/fibsem/fibsem/render/align/${VOLUME}
./07_h5_to_render.sh

# edit 09_find_substacks.sh script to find z ranges for different test conditions
./09_find_substacks.sh

# edit 10_split_into_condition_stacks.sh script to split z ranges into condition stacks
./10_split_into_condition_stacks.sh