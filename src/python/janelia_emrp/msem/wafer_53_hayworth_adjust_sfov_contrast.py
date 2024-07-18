# MINIMAL_SCRIPT_FOR_ADJUSTING_sFOV_CONTRASTS.py -Kenneth Hayworth July 2024
#
# This is the minimal script needed to adjust the sFOV contrasts identically to what I originally did for Wafer53
#
# N: must be mapped to \\nrs\hess
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


import numpy as np
import os
import skimage.io as skimage_io
import sys


# These two *.npy files contain all the pre-computed parameters needed to adjust contrasts in Wafer53 run
LOAD_PATH =  r'N:\from_mdas\Hayworth\Wafer53\INTENSITY_EQ_FOR_CENTER_7_MFOVS_July2024\SAVED_NORMALIZATION_ARRAY.npy'
print(f'Loading: {LOAD_PATH}')
LOADED_NORMALIZATION_ARRAY = np.load(LOAD_PATH)

LOAD_PATH =  r'N:\from_mdas\Hayworth\Wafer53\INTENSITY_EQ_FOR_CENTER_7_MFOVS_July2024\SAVED_BEAM_BLANK_ARRAY.npy'
print(f'Loading: {LOAD_PATH}')
LOADED_BEAM_BLANK_ARRAY = np.load(LOAD_PATH)


# Source and target paths
MAIN_SOURCE_DIR_PATH = r'N:\from_mdas\ufomsem\acquisition\base\wafer_53\imaging\corrected_msem'
MAIN_TARGET_DIR_PATH = r'N:\from_mdas\Hayworth\Wafer53\INTENSITY_EQ_FOR_CENTER_7_MFOVS_July2024\scan_corrected_equalized_target_dir'

#######################
# Here is where you specify what files to convert
real_scan_index = 42
slab_directory_number = 110
mFOV_number = 10


# Find the correct source images...
temp_sub_dir_str = f'scan_{real_scan_index:03}'
SOURCE_PATH = os.path.join(MAIN_SOURCE_DIR_PATH, temp_sub_dir_str)
temp_list = os.listdir(SOURCE_PATH)
if len(temp_list) != 1:
    print(f'ERROR. Should only be one dir in: {SOURCE_PATH}')
    sys.exit()
SOURCE_PATH = os.path.join(SOURCE_PATH, temp_list[0])
slab_directory_str = f'{slab_directory_number:03}_'
SOURCE_PATH = os.path.join(SOURCE_PATH, slab_directory_str)
mFOV_directory_str = f'{mFOV_number:06}'
SOURCE_PATH = os.path.join(SOURCE_PATH, mFOV_directory_str)
temp_list_raw = os.listdir(SOURCE_PATH)
list_of_image_names = []
for i in range(0, len(temp_list_raw)):
    if len(temp_list_raw[i]) == len('001_000010_001_2022-09-17T0621004666315.png'):
        list_of_image_names.append(temp_list_raw[i])
list_of_image_names.sort() #puts in correct order of beams
if len(list_of_image_names) != 91:
    print(f'ERROR. Should be 91 images in: {SOURCE_PATH}')
    sys.exit()

# Create the target directory structure...
temp_sub_dir_str = f'scan_{real_scan_index:03}'
TARGET_PATH = os.path.join(MAIN_TARGET_DIR_PATH, temp_sub_dir_str)
if not os.path.exists(TARGET_PATH):
    print(f'Making directory: {TARGET_PATH}')
    os.mkdir(TARGET_PATH)
else:
    print(f'Already exists: {TARGET_PATH}')
slab_directory_str = f'{slab_directory_number:03}_'
TARGET_PATH = os.path.join(TARGET_PATH, slab_directory_str)
if not os.path.exists(TARGET_PATH):
    print(f'Making directory: {TARGET_PATH}')
    os.mkdir(TARGET_PATH)
else:
    print(f'Already exists: {TARGET_PATH}')
    mFOV_directory_str = f'{mFOV_number:06}'
TARGET_PATH = os.path.join(TARGET_PATH, mFOV_directory_str)
if not os.path.exists(TARGET_PATH):
    print(f'Making directory: {TARGET_PATH}')
    os.mkdir(TARGET_PATH)
else:
    print(f'Already exists: {TARGET_PATH}')

# Do intensity correection and save
for sFOV_index in range(0, len(list_of_image_names)):
    image_name = list_of_image_names[sFOV_index]
    path_to_source_image_file = os.path.join(SOURCE_PATH, image_name)
    print("        Reading: " + path_to_source_image_file)
    my_source_image = skimage_io.imread(path_to_source_image_file)

    processed_image_float = (my_source_image - LOADED_BEAM_BLANK_ARRAY[real_scan_index, sFOV_index]) * (1.0/LOADED_NORMALIZATION_ARRAY[real_scan_index,sFOV_index])
    processed_image_uint8 = processed_image_float.astype(np.uint8)

    save_target_file_path = os.path.join(TARGET_PATH, image_name)
    print("   Saving: " + save_target_file_path)
    skimage_io.imsave(save_target_file_path, processed_image_uint8)