# MINIMAL_SCRIPT_FOR_ADJUSTING_sFOV_CONTRASTS.py -Kenneth Hayworth July 2024
#
# This is the minimal script needed to adjust the sFOV contrasts identically to what I originally did for Wafer53
#
# Assuming N: is mapped to \\nrs\hess
#
# The original source images (for mFOV 000010) were scan corrected by Thomas Templier and put in:
#    N:\from_mdas\ufomsem\acquisition\base\wafer_53\imaging\corrected_msem
#
# My original program took these scan corrected images and adjusted their intensities to create the files in:
#    N:\from_mdas\Hayworth\Wafer53\scan_corrected_equalized_target_dir
# These were the images that I used to create the “RealOrder” images sent to Michal J. as described in:
#    N:\from_mdas\Hayworth\Wafer53\COMPLETE RECORD OF TRANSFORMATION for Wafer53.docx
#
# This script exactly replicates this process for demonstration purposes... reading in images from:
#    N:\from_mdas\ufomsem\acquisition\base\wafer_53\imaging\corrected_msem
# ... correcting their intensities, and then writing the new images to:
#    N:\from_mdas\Hayworth\Wafer53\INTENSITY_EQ_FOR_CENTER_7_MFOVS_July2024\scan_corrected_equalized_target_dir
#
# All of the complexities of the original program have been hidden by pre-computing two *.npy array files:
#    N:\from_mdas\Hayworth\Wafer53\INTENSITY_EQ_FOR_CENTER_7_MFOVS_July2024\SAVED_NORMALIZATION_ARRAY.npy
#    N:\from_mdas\Hayworth\Wafer53\INTENSITY_EQ_FOR_CENTER_7_MFOVS_July2024\SAVED_BEAM_BLANK_ARRAY.npy
# which are loaded at the beginning of this script.
import sys
import traceback

import numpy as np
import os
import skimage.io as skimage_io


def correct_mfov_for_scan(main_source_dir_path: str,
                          main_target_dir_path: str,
                          loaded_normalization_array: np.ndarray,
                          loaded_beam_blank_array: np.ndarray,
                          real_scan_index: int,
                          slab_directory_number: int,
                          mfov_number: int):

    # Find the correct source images...
    temp_sub_dir_str = f'scan_{real_scan_index:03}'
    source_path = os.path.join(main_source_dir_path, temp_sub_dir_str)
    temp_list = os.listdir(source_path)
    if len(temp_list) != 1:
        raise Warning(f'Skipping correction: found {len(temp_list)} instead of one dir in {source_path}')

    source_path = os.path.join(source_path, temp_list[0])
    slab_directory_str = f'{slab_directory_number:03}_'
    source_path = os.path.join(source_path, slab_directory_str)
    mfov_directory_str = f'{mfov_number:06}'
    source_path = os.path.join(source_path, mfov_directory_str)
    temp_list_raw = os.listdir(source_path)
    list_of_image_names = []
    for i in range(0, len(temp_list_raw)):
        if len(temp_list_raw[i]) == 43:  # len('001_000010_001_2022-09-17T0621004666315.png)'
            list_of_image_names.append(temp_list_raw[i])
    list_of_image_names.sort()  # puts in correct order of beams
    if len(list_of_image_names) != 91:
        raise Warning(f'Skipping correction: found {len(list_of_image_names)} instead of 91 images in {source_path}')

    # Create the target directory structure...
    temp_sub_dir_str = f'scan_{real_scan_index:03}'
    target_path = os.path.join(main_target_dir_path, temp_sub_dir_str)
    if not os.path.exists(target_path):
        print(f'Making directory: {target_path}')
        os.mkdir(target_path)
    else:
        print(f'Already exists: {target_path}')
    slab_directory_str = f'{slab_directory_number:03}_'
    target_path = os.path.join(target_path, slab_directory_str)
    if not os.path.exists(target_path):
        print(f'Making directory: {target_path}')
        os.mkdir(target_path)
    else:
        print(f'Already exists: {target_path}')
        mfov_directory_str = f'{mfov_number:06}'
    target_path = os.path.join(target_path, mfov_directory_str)
    if not os.path.exists(target_path):
        print(f'Making directory: {target_path}')
        os.mkdir(target_path)
    else:
        print(f'Already exists: {target_path}')

    # Do intensity correction and save
    for sFOV_index in range(0, len(list_of_image_names)):
        image_name = list_of_image_names[sFOV_index]
        path_to_source_image_file = os.path.join(source_path, image_name)
        print("        Reading: " + path_to_source_image_file)
        my_source_image = skimage_io.imread(path_to_source_image_file)

        processed_image_float = ((my_source_image - loaded_beam_blank_array[real_scan_index, sFOV_index]) *
                                 (1.0 / loaded_normalization_array[real_scan_index, sFOV_index]))
        processed_image_uint8 = processed_image_float.astype(np.uint8)

        save_target_file_path = os.path.join(target_path, image_name)
        print("   Saving: " + save_target_file_path)
        skimage_io.imsave(save_target_file_path, processed_image_uint8)


def correct_center7_mfovs_for_slab(slab_directory_number: int):
    print(f'Correcting slab {slab_directory_number}')

    # Source and target paths
    main_source_dir_path = r'/nrs/hess/from_mdas/ufomsem/acquisition/base/wafer_53/imaging/corrected_msem'
    main_target_dir_path = r'/nrs/hess/data/hess_wafer_53/scan_corrected_with_hayworth_contrast'

    # These two *.npy files contain all the pre-computed parameters needed to adjust contrasts in Wafer53 run
    load_path = r'../../../resources/wafer_53/SAVED_NORMALIZATION_ARRAY.npy'
    print(f'Loading {load_path}')
    loaded_normalization_array = np.load(load_path)

    load_path = r'../../../resources/wafer_53/SAVED_BEAM_BLANK_ARRAY.npy'
    print(f'Loading {load_path}')
    loaded_beam_blank_array = np.load(load_path)

    # skip scan_000 based on Thomas's doc, skip scan_047+ because scan_046 is last one referenced
    for real_scan_index in range(1, 47):
        for mfov_number in [5, 6, 9, 10, 11, 14, 15]:
            # noinspection PyBroadException
            try:
                correct_mfov_for_scan(main_source_dir_path,
                                      main_target_dir_path,
                                      loaded_normalization_array,
                                      loaded_beam_blank_array,
                                      real_scan_index,
                                      slab_directory_number,
                                      mfov_number)
            except Exception:
                traceback.print_exc()


if __name__ == '__main__':
    slab_indexes = []
    for arg_index in range(1, len(sys.argv)):
        slab_indexes.append(int(sys.argv[arg_index]))

    if len(slab_indexes) == 0:
        slab_indexes.append(110)  # TODO: remove testing hack
        print(f"USAGE: {sys.argv[0]} <slab_index> [slab index] ...")
        sys.exit(1)

    for slab_index in slab_indexes:
        correct_center7_mfovs_for_slab(slab_index)
